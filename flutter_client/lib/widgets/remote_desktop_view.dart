import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/remote_event.dart';

class RemoteDesktopView extends StatefulWidget {
  const RemoteDesktopView({
    super.key,
    required this.renderer,
    required this.isReady,
    required this.onInput,
  });

  final RTCVideoRenderer renderer;
  final bool isReady;
  final void Function(RemoteInputEvent event) onInput;

  @override
  State<RemoteDesktopView> createState() => _RemoteDesktopViewState();
}

class _RemoteDesktopViewState extends State<RemoteDesktopView> {
  Offset? _pointerDownPosition;
  bool _isDragging = false;
  int _activeButton = 0;

  Offset _mapToVideo(Offset local, Size widgetSize) {
    final videoSize = widget.renderer.videoWidth > 0 && widget.renderer.videoHeight > 0
        ? Size(
            widget.renderer.videoWidth.toDouble(),
            widget.renderer.videoHeight.toDouble(),
          )
        : widgetSize;

    final videoAspect = videoSize.width / videoSize.height;
    final widgetAspect = widgetSize.width / widgetSize.height;

    double renderWidth;
    double renderHeight;
    double offsetX;
    double offsetY;

    if (videoAspect > widgetAspect) {
      renderWidth = widgetSize.width;
      renderHeight = widgetSize.width / videoAspect;
      offsetX = 0;
      offsetY = (widgetSize.height - renderHeight) / 2;
    } else {
      renderHeight = widgetSize.height;
      renderWidth = widgetSize.height * videoAspect;
      offsetX = (widgetSize.width - renderWidth) / 2;
      offsetY = 0;
    }

    final x = ((local.dx - offsetX) / renderWidth).clamp(0.0, 1.0);
    final y = ((local.dy - offsetY) / renderHeight).clamp(0.0, 1.0);
    return Offset(x, y);
  }

  void _send(String type, Offset norm, {int button = 0, double deltaY = 0}) {
    widget.onInput(RemoteInputEvent(
      type: type,
      x: norm.dx,
      y: norm.dy,
      button: button,
      deltaY: deltaY,
    ));
  }

  Widget _buildInputLayer(Size widgetSize) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          final norm = _mapToVideo(signal.localPosition, widgetSize);
          _send('scroll', norm, deltaY: signal.scrollDelta.dy);
        }
      },
      onPointerDown: (event) {
        _pointerDownPosition = event.localPosition;
        _isDragging = false;
        _activeButton = event.buttons == kSecondaryMouseButton ? 2 : 0;
        final norm = _mapToVideo(event.localPosition, widgetSize);
        _send('mousedown', norm, button: _activeButton);
      },
      onPointerHover: (event) {
        final norm = _mapToVideo(event.localPosition, widgetSize);
        _send('mousemove', norm);
      },
      onPointerMove: (event) {
        final norm = _mapToVideo(event.localPosition, widgetSize);
        if (event.buttons != 0) {
          _isDragging = true;
        }
        _send('mousemove', norm);
      },
      onPointerUp: (event) {
        final norm = _mapToVideo(event.localPosition, widgetSize);
        _send('mouseup', norm, button: _activeButton);

        if (!_isDragging && _pointerDownPosition != null) {
          final moved = (event.localPosition - _pointerDownPosition!).distance;
          if (moved < 8) {
            _send('click', norm, button: _activeButton);
          }
        }
        _pointerDownPosition = null;
        _isDragging = false;
        _activeButton = 0;
      },
      child: const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isReady) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('等待视频流...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);

        // RTCVideoView is a native view on desktop and intercepts pointer events.
        // Put a transparent Listener on top so the mouse can interact with remote desktop.
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: RTCVideoView(
                widget.renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
            ),
            _buildInputLayer(widgetSize),
          ],
        );
      },
    );
  }
}
