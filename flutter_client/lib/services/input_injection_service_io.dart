import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/remote_event.dart';

class InputInjectionService {
  static const _channel = MethodChannel('com.remotecontrol/input');

  static bool get isSupported {
    return Platform.isMacOS || Platform.isLinux || Platform.isWindows;
  }

  Future<void> inject(RemoteInputEvent event) async {
    if (Platform.isMacOS) {
      await _injectMacOS(event);
      return;
    }

    if (Platform.isLinux) {
      await _injectLinux(event);
      return;
    }

    if (Platform.isWindows) {
      await _injectWindows(event);
    }
  }

  Future<void> _injectMacOS(RemoteInputEvent event) async {
    try {
      await _channel.invokeMethod('inject', event.toJson());
    } on PlatformException catch (e) {
      debugPrint('Input injection failed: ${e.message}');
    } on MissingPluginException {
      debugPrint('Input injection plugin not available');
    }
  }

  Future<void> setCaptureSource({
    String? sourceId,
    String? sourceName,
    String? sourceType,
  }) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('setCaptureSource', {
        'sourceId': sourceId,
        'sourceName': sourceName,
        'sourceType': sourceType,
      });
    } on PlatformException catch (e) {
      debugPrint('setCaptureSource failed: ${e.message}');
    } on MissingPluginException {
      debugPrint('Input injection plugin not available');
    }
  }

  Future<void> _injectLinux(RemoteInputEvent event) async {
    final size = await _screenSize();
    final x = (event.x * size.width).round();
    final y = (event.y * size.height).round();

    switch (event.type) {
      case 'mousemove':
        await Process.run('xdotool', ['mousemove', '$x', '$y']);
      case 'mousedown':
      case 'click':
        await Process.run('xdotool', [
          'mousemove',
          '$x',
          '$y',
          'click',
          event.button == 2 ? '3' : '1',
        ]);
      case 'scroll':
        final clicks = (event.deltaY / 40).round().clamp(-5, 5);
        if (clicks != 0) {
          await Process.run('xdotool', ['click', clicks > 0 ? '5' : '4']);
        }
      default:
        break;
    }
  }

  Future<void> _injectWindows(RemoteInputEvent event) async {
    final size = await _screenSize();
    final x = (event.x * size.width).round();
    final y = (event.y * size.height).round();

    if (event.type == 'mousemove' ||
        event.type == 'click' ||
        event.type == 'mousedown') {
      await Process.run('powershell', [
        '-Command',
        'Add-Type -AssemblyName System.Windows.Forms; '
            '[System.Windows.Forms.Cursor]::Position = '
            'New-Object System.Drawing.Point($x, $y)',
      ]);
    }
  }

  Future<({double width, double height})> _screenSize() async {
    if (Platform.isMacOS) {
      try {
        final result = await _channel.invokeMethod<Map>('getScreenSize');
        if (result != null) {
          return (
            width: (result['width'] as num).toDouble(),
            height: (result['height'] as num).toDouble(),
          );
        }
      } catch (_) {}
    }
    return (width: 1920.0, height: 1080.0);
  }
}
