import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ThumbnailUtils {
  static const _channel = MethodChannel('com.remotecontrol/input');

  static Future<Uint8List?> loadForSource(DesktopCapturerSource source) async {
    Uint8List? raw = source.thumbnail;
    if (raw == null || raw.isEmpty) {
      raw = await _fetchRawThumbnail(source);
    }
    if (raw == null || raw.isEmpty) return null;
    return decodeDisplayBytes(raw);
  }

  static Future<Uint8List?> _fetchRawThumbnail(DesktopCapturerSource source) async {
    try {
      final response = await WebRTC.invokeMethod(
        'getDesktopSourceThumbnail',
        <String, dynamic>{
          'sourceId': source.id,
          'thumbnailSize': const {'width': 480, 'height': 270},
        },
      );
      if (response is Uint8List && response.isNotEmpty) {
        return response;
      }
    } catch (e) {
      debugPrint('fetch thumbnail failed: $e');
    }
    return null;
  }

  static Future<Uint8List?> decodeDisplayBytes(Uint8List raw) async {
    if (_looksLikePng(raw) || _looksLikeJpeg(raw)) {
      return raw;
    }

    if (Platform.isMacOS) {
      try {
        final decoded = await _channel.invokeMethod('decodeThumbnail', raw);
        if (decoded is Uint8List && decoded.isNotEmpty) {
          return decoded;
        }
      } catch (e) {
        debugPrint('decode thumbnail failed: $e');
      }
      return null;
    }

    return null;
  }

  static bool _looksLikePng(Uint8List bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
  }

  static bool _looksLikeJpeg(Uint8List bytes) {
    return bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  }
}
