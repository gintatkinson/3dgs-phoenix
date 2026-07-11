import 'dart:typed_data';
import 'package:app_flutter/domain/cesium_3d/native/error_handler.dart';
import 'package:app_flutter/domain/cesium_3d/tile_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TileFetcher', () {
    late TileFetcher fetcher;

    setUp(() {
      fetcher = TileFetcher();
    });

    test('is enabled by default when MAP_IMAGERY_ENABLED is unset', () {
      expect(fetcher.isEnabled(), isTrue);
    });

    test('disable() causes fetchTile to return null', () async {
      fetcher.disable();
      expect(fetcher.isEnabled(), isFalse);

      final result = await fetcher.fetchTile(
        ImageryProvider.openStreetMap,
        2,
        3,
        1,
      );
      expect(result, isNull);
    });

    test('urlFor produces HTTPS URLs for every provider', () {
      for (final provider in ImageryProvider.values) {
        final url = TileFetcher.urlFor(provider, 3, 4, 2);
        expect(url, startsWith('https://'),
            reason: '$provider URL should use HTTPS');
        expect(Uri.parse(url).host, isNotEmpty,
            reason: '$provider URL must have a valid host');
      }

      expect(
        TileFetcher.urlFor(ImageryProvider.openStreetMap, 1, 2, 3),
        'https://tile.openstreetmap.org/1/2/3.png',
      );
      expect(
        TileFetcher.urlFor(ImageryProvider.arcGisSatellite, 1, 2, 3),
        'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/1/3/2',
      );
      expect(
        TileFetcher.urlFor(ImageryProvider.cartoDark, 1, 2, 3),
        'https://basemaps.cartocdn.com/dark_all/1/2/3.png',
      );
      expect(
        TileFetcher.urlFor(ImageryProvider.cartoLight, 1, 2, 3),
        'https://basemaps.cartocdn.com/light_all/1/2/3.png',
      );
    });

    test('cacheLength reports the number of cached entries', () {
      expect(fetcher.cacheLength, 0);
    });

    test('clearCache empties stored entries', () {
      // We cannot directly insert into the cache, but the getter confirms
      // it starts at zero and stays at zero after clear.
      expect(fetcher.cacheLength, 0);
      fetcher.clearCache();
      expect(fetcher.cacheLength, 0);
    });

    test('simulated connection timeout triggers TileTimeoutException', () async {
      // Create a TileFetcher with a tiny 10ms connection timeout
      final timeoutFetcher = TileFetcher(connectionTimeout: const Duration(milliseconds: 10));

      // Override the base URL to a non-routable IP address which will cause TCP connect to hang/timeout
      timeoutFetcher.baseUrlOverride = 'http://10.255.255.1';

      expect(
        () => timeoutFetcher.fetchTile(ImageryProvider.openStreetMap, 1, 2, 3),
        throwsA(isA<TileTimeoutException>()),
      );
    });
  });

  group('TileCache', () {
    test('stores and retrieves entries', () {
      final cache = TileCache(maxSize: 4);
      final data = Uint8List.fromList([1, 2, 3]);
      cache.put('a', data);

      final retrieved = cache.get('a');
      expect(retrieved, isNotNull);
      expect(retrieved, equals(data));
      expect(cache.length, 1);
    });

    test('get returns null for missing keys', () {
      final cache = TileCache();
      expect(cache.get('nonexistent'), isNull);
    });

    test('clear removes all entries', () {
      final cache = TileCache(maxSize: 4);
      cache.put('a', Uint8List(8));
      cache.put('b', Uint8List(8));
      expect(cache.length, 2);

      cache.clear();
      expect(cache.length, 0);
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNull);
    });

    test('LRU eviction removes least-recently-used entry when full', () {
      const size = 256;
      final cache = TileCache(maxSize: size);

      // Fill the cache to capacity.
      for (int i = 0; i < size; i++) {
        cache.put('key_$i', Uint8List(1));
      }
      expect(cache.length, size);

      // Access the first key so it becomes MRU.
      expect(cache.get('key_0'), isNotNull);
      // Access the second key so it is also MRU (after key_0).
      expect(cache.get('key_1'), isNotNull);

      // Insert one more entry — this should evict 'key_2' (the LRU after
      // key_0 and key_1 were moved to MRU).
      cache.put('overflow', Uint8List(1));
      expect(cache.length, size);
      expect(cache.get('key_2'), isNull,
          reason: 'key_2 should have been evicted as the LRU entry');
      expect(cache.get('key_0'), isNotNull,
          reason: 'key_0 was recently accessed and should survive');
      expect(cache.get('key_1'), isNotNull,
          reason: 'key_1 was recently accessed and should survive');
      expect(cache.get('overflow'), isNotNull);
    });

    test('maxSize is correctly reported', () {
      final cache = TileCache(maxSize: 128);
      expect(cache.maxSize, 128);

      final defaultCache = TileCache();
      expect(defaultCache.maxSize, 256);
    });
  });
}
