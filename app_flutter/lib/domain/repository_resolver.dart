import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'data_source.dart';
import 'data_sources/firebase_data_source.dart';
import 'data_sources/sqlite_data_source.dart';
import 'database_initializer.dart';
import 'package:flutter/foundation.dart';


/// Resolves the data-access backend at app startup.
///
/// Reads a JSON configuration file (or falls back to defaults) to decide
/// whether to initialise a local SQLite database or connect to Cloud
/// Firestore. Returns a [DataSource] that
/// the app uses for all read/write operations and schema discovery.
///
/// Call this once at startup, before any data-dependent widget builds.
/// The resolved datasource is then injected via dependency injection or passed
/// through the widget tree. Calling [resolve] multiple times creates
/// separate connections — doing so is not recommended.
class RepositoryResolver {
  static const _defaultConfig = 'assets/persistence-config.json';
  static const _defaultDbAsset = 'assets/properties_db.db.gz';

  static const _defaultEmulatorHost = 'localhost';
  static const _defaultEmulatorPort = 8080;

  static DataSource? _lastResolved;
  // NOTE: Once set, the Firebase SDK prevents reconfiguring the emulator
  // connection within a single process lifetime (BUG #216 — by design).
  static bool _firebaseEmulatorConfigured = false;

  // _isResolving guards against concurrent resolve() calls creating
  // duplicate connections (BUG #215).
  static bool _isResolving = false;

  /// Resolves and initialises the appropriate backend.
  ///
  /// Determines the backend type from (in priority order):
  /// 1. [dataSourceType] parameter (if non-null)
  /// 2. JSON config file at [configPath] or the default asset path
  /// 3. Falls back to SQLite if neither is available
  ///
  /// For SQLite: copies the bundled database from [dbAssetPath] to the
  /// app support directory (unless [sqliteInMemory] is true). Creates
  /// the tables if they do not exist via [DatabaseInitializer].
  ///
  /// For Firebase: initialises the Firebase app and optionally connects
  /// to the Firestore emulator at [useEmulator].
  ///
  /// Returns a [DataSource] ready for injection.
  /// Throws on network errors (Firebase init) or file I/O
  /// errors (asset copy failure). Always resolves to a non-null DataSource.
  static Future<DataSource> resolve({
    String? configPath,
    String? dbAssetPath,
    bool sqliteInMemory = false,
    String? dataSourceType,
    bool useEmulator = true,
  }) async {
    if (_isResolving) {
      if (_lastResolved != null) return _lastResolved!;
      while (_isResolving) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_lastResolved != null) return _lastResolved!;
    }
    _isResolving = true;
    try {
      String type = dataSourceType ?? 'sqlite';

      // If no explicit type, try reading from config file
      if (dataSourceType == null) {
        final path = configPath ?? _defaultConfig;
        try {
          final configJson = await rootBundle.loadString(path);
          final config = jsonDecode(configJson) as Map<String, dynamic>;
          type = config['repository_type'] as String? ?? 'sqlite';
        } catch (_) {}
      }

      await _lastResolved?.dispose();
      final DataSource resolved;
      switch (type) {
        case 'firebase':
          resolved = await _createFirebaseAdapter(useEmulator: useEmulator);
        case 'sqlite':
          resolved = await _createSqliteAdapter(
            dbAssetPath: dbAssetPath,
            inMemory: sqliteInMemory,
          );
        default:
          resolved = await _createSqliteAdapter(
            dbAssetPath: dbAssetPath,
            inMemory: sqliteInMemory,
          );
      }
      _lastResolved = resolved;
      return resolved;
    } finally {
      _isResolving = false;
    }
  }

  /// Initialies Firebase and returns a Firestore-backed DataSource.
  ///
  /// Calls [Firebase.initializeApp] first (idempotent if already called).
  /// When [useEmulator] is true, redirects Firestore to the local emulator
  /// at localhost:8080 — useful for development without a real Firebase
  /// project. Throws if Firebase initialisation fails (missing config, etc.).
  static Future<FirebaseDataSource> _createFirebaseAdapter({
    bool useEmulator = true,
  }) async {
    await Firebase.initializeApp();
    final firestore = FirebaseFirestore.instance;
    if (useEmulator && !_firebaseEmulatorConfigured) {
      firestore.useFirestoreEmulator(_defaultEmulatorHost, _defaultEmulatorPort);
      _firebaseEmulatorConfigured = true;
    }
    return FirebaseDataSource(firestore);
  }

  /// Initialises SQLite FFI and returns an SQLite-backed DataSource.
  ///
  /// When [inMemory] is true, creates a transient in-memory database
  /// (data is lost on app restart). Otherwise, copies the asset database
  /// from [dbAssetPath] (or the default asset) to the app support directory
  /// and opens it.
  /// Throws on file I/O errors or database corruption.
  static Future<DataSource> _createSqliteAdapter({
    String? dbAssetPath,
    bool inMemory = false,
  }) async {
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (!kIsWeb && (isTest || Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String dbPath;
    if (kIsWeb) {
      dbPath = inMemoryDatabasePath;
    } else {
      final dir = await getApplicationSupportDirectory();
      dbPath = inMemory ? inMemoryDatabasePath : p.join(dir.path, 'properties_db.db');
    }

    if (!kIsWeb && !inMemory) {
      final dbFile = File(dbPath);
      bool isOutdated = false;
      final exists = await dbFile.exists();
      if (exists) {
        Database? tempDb;
        try {
          tempDb = await databaseFactory.openDatabase(dbPath);
          final tables = ['properties', 'instances', 'type_definitions', 'type_attributes', 'type_relations'];
          final rows = await tempDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN (${tables.map((t) => "'$t'").join(', ')})"
          );
          if (rows.length < tables.length) {
            isOutdated = true;
          }
        } catch (_) {
          isOutdated = true;
        } finally {
          if (tempDb != null) {
            await tempDb.close();
          }
        }
      }

      if (!exists || isOutdated) {
        if (exists) {
          try {
            await dbFile.delete();
          } catch (e) {
            debugPrint('Failed to delete outdated database file: $e');
          }
        }
        final assetPath = dbAssetPath ?? _defaultDbAsset;
        try {
          final bytes = await rootBundle.load(assetPath);
          List<int> decodedBytes = bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          );
          if (assetPath.endsWith('.gz')) {
            decodedBytes = await compute(gzip.decode, decodedBytes);
          }
          await dbFile.writeAsBytes(decodedBytes);
        } catch (e) {
          debugPrint('Failed to write database file "$dbPath": $e');
        }
      }
    }

    final db = await DatabaseInitializer.create(dbPath: dbPath, seed: true);
    return SqliteDataSource(db);
  }
}
