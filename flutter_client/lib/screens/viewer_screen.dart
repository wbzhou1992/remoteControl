import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../widgets/remote_desktop_view.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  RTCVideoRenderer? _renderer;
  bool _rendererReady = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  void _attachStream(RTCVideoRenderer renderer, MediaStream stream) {
    renderer.srcObject = stream;
    for (final track in stream.getVideoTracks()) {
      track.onMute = () {
        if (mounted) setState(() => _rendererReady = false);
      };
      track.onUnMute = () {
        if (mounted) setState(() => _rendererReady = true);
      };
    }
    if (mounted) {
      setState(() => _rendererReady = true);
    }
  }

  Future<void> _initRenderer() async {
    final renderer = RTCVideoRenderer();
    await renderer.initialize();

    renderer.onResize = () {
      if (!mounted) return;
      if (renderer.videoWidth > 0 && renderer.videoHeight > 0) {
        setState(() => _rendererReady = true);
      }
    };

    if (!mounted) return;
    final session = context.read<SessionController>();

    session.webrtc.remoteStreamStream.listen((stream) {
      if (stream != null && mounted) {
        _attachStream(renderer, stream);
      }
    });

    final existing = session.webrtc.remoteStream;
    if (existing != null) {
      _attachStream(renderer, existing);
    }

    setState(() => _renderer = renderer);
  }

  @override
  void dispose() {
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('远程桌面 · ${session.roomId ?? ''}'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: () {},
            tooltip: '全屏',
          ),
        ],
      ),
      body: _renderer == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RemoteDesktopView(
              renderer: _renderer!,
              isReady: _rendererReady,
              onInput: session.sendInput,
            ),
    );
  }
}
