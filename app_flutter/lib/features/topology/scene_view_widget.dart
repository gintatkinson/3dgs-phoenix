import 'package:flutter/material.dart';
import 'package:app_flutter/domain/cesium_3d/grpc_channel.dart';
import 'package:app_flutter/features/topology/topographical_view.dart';
import 'package:app_flutter/features/topology/topology_defaults.dart';
import 'package:app_flutter/features/topology/topology_map.dart';

class SceneViewWidget extends StatefulWidget {
  final String sceneId;
  final GrpcChannel? grpcChannel; // Enables passing a mock channel for verification tests

  const SceneViewWidget({
    super.key,
    required this.sceneId,
    this.grpcChannel,
  });

  @override
  State<SceneViewWidget> createState() => _SceneViewWidgetState();
}

class _SceneViewWidgetState extends State<SceneViewWidget> {
  late final GrpcChannel _channel;
  bool _isLoading = true;
  bool _hasFault = false;
  TopologyData? _topologyData;

  @override
  void initState() {
    super.initState();
    _channel = widget.grpcChannel ?? GrpcChannel(socketPath: '/tmp/uds_${widget.sceneId}.sock');
    _initializeConnectionAndData();
  }

  Future<void> _initializeConnectionAndData() async {
    // 1. Listen to UDS socket connection changes
    _channel.connectionStateChanges.listen((connected) {
      if (mounted) {
        setState(() {
          _hasFault = !connected;
        });
      }
    });

    // 2. Load the topology data asset and connect to UDS in parallel
    try {
      final results = await Future.wait([
        _channel.connect(),
        loadTopologyData(),
      ]);

      final connected = results[0] as bool;
      final topoData = results[1] as TopologyData;

      if (mounted) {
        setState(() {
          _topologyData = topoData;
          _isLoading = false;
          _hasFault = !connected;
        });
      }
    } catch (e, st) {
      debugPrint('INITIALIZATION ERROR in SceneViewWidget: $e\n$st');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasFault = true;
        });
      }
    }
  }

  @override
  void dispose() {
    // Only dispose the channel if we created it locally
    if (widget.grpcChannel == null) {
      _channel.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasFault) {
      // Fault State: displays persistent warning banner "Connection Lost" if UDS drops or disconnects
      return Scaffold(
        body: Stack(
          children: [
            // Underneath we display the topographical view (frozen/retained)
            if (_topologyData != null)
              Positioned.fill(child: _buildTopographicalView()),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.red.shade800,
                elevation: 4.0,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    alignment: Alignment.center,
                    child: const Text(
                      'Connection Lost',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      // Loading State: displays circular progress spinner while connecting to UDS
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Active State: mounts topographical view filling the entire screen
    return Scaffold(
      body: _buildTopographicalView(),
    );
  }

  Widget _buildTopographicalView() {
    // Explicit CSS containment: "contain: layout paint;" is simulated in Flutter
    // using RepaintBoundary (paint containment) and BoxConstraints.expand (layout containment).
    // The literal style string is preserved as requested by the specification.
    const String style = 'contain: layout paint;';

    return RepaintBoundary(
      child: Container(
        constraints: const BoxConstraints.expand(),
        key: const ValueKey(style),
        child: TopographicalView(
          currentView: widget.sceneId,
          onViewSelected: (viewId) {},
          topologyData: _topologyData ?? emptyTopologyData,
          treeData: const [],
        ),
      ),
    );
  }
}
