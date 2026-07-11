import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/remote_event.dart';
import '../services/input_injection_service.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';

class SessionController extends ChangeNotifier {
  SessionController() {
    _signaling.onMessage = _handleSignalingMessage;
  }

  final SignalingService _signaling = SignalingService();
  late final WebRTCService _webrtc = WebRTCService(_signaling);
  final InputInjectionService _inputInjection = InputInjectionService();

  String serverUrl = 'ws://localhost:3000/ws';
  String? roomId;
  String? clientId;
  SessionRole? role;
  ConnectionStatus status = ConnectionStatus.disconnected;
  String? errorMessage;

  SignalingService get signaling => _signaling;
  WebRTCService get webrtc => _webrtc;

  Future<void> connectAsHost({
    String? screenSourceId,
    String? screenSourceName,
    String? screenSourceType,
  }) async {
    role = SessionRole.host;
    roomId = null;
    status = ConnectionStatus.connecting;
    errorMessage = null;
    notifyListeners();

    try {
      await _signaling.connect(serverUrl);
      _signaling.send({'type': 'create-room'});
      await _waitForRoomId();
      await _webrtc.initAsHost(screenSourceId: screenSourceId);
      await _inputInjection.setCaptureSource(
        sourceId: screenSourceId,
        sourceName: screenSourceName,
        sourceType: screenSourceType,
      );
    } catch (e) {
      status = ConnectionStatus.error;
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _waitForRoomId({Duration timeout = const Duration(seconds: 10)}) async {
    final deadline = DateTime.now().add(timeout);
    while (roomId == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (roomId == null) {
      throw StateError('未获取到房间号，请确认信令服务器已启动（npm run server）');
    }
  }

  Future<void> connectAsViewer(String targetRoomId) async {
    role = SessionRole.viewer;
    roomId = targetRoomId.trim();
    status = ConnectionStatus.connecting;
    errorMessage = null;
    notifyListeners();

    try {
      await _signaling.connect(serverUrl);
      await _webrtc.initAsViewer();
      _signaling.send({'type': 'join-room', 'roomId': roomId});
    } catch (e) {
      status = ConnectionStatus.error;
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _handleSignalingMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'room-created':
        roomId = msg['roomId'] as String?;
        clientId = msg['clientId'] as String?;
        _webrtc.setClientId(clientId ?? '');
        status = ConnectionStatus.connected;
        notifyListeners();
        break;

      case 'joined':
        roomId = msg['roomId'] as String?;
        clientId = msg['clientId'] as String?;
        _webrtc.setClientId(clientId ?? '');
        status = ConnectionStatus.connected;
        notifyListeners();
        break;

      case 'offer':
        final fromId = msg['fromId'] as String?;
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (fromId != null && payload != null) {
          unawaited(_webrtc.handleOffer(payload, fromId).catchError((Object e) {
            status = ConnectionStatus.error;
            errorMessage = e.toString();
            notifyListeners();
          }));
        }
        break;

      case 'answer':
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          unawaited(_webrtc.handleAnswer(payload).catchError((Object e) {
            status = ConnectionStatus.error;
            errorMessage = e.toString();
            notifyListeners();
          }));
        }
        break;

      case 'ice-candidate':
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          unawaited(_webrtc.handleIceCandidate(payload));
        }
        break;

      case 'viewer-joined':
        final viewerId = msg['clientId'] as String?;
        if (viewerId != null && role == SessionRole.host) {
          _webrtc.createOfferForViewer(viewerId);
        }
        break;

      case 'input-event':
        if (role == SessionRole.host) {
          final payload = msg['payload'] as Map<String, dynamic>?;
          if (payload != null) {
            _inputInjection.inject(RemoteInputEvent.fromJson(payload));
          }
        }
        break;

      case 'host-disconnected':
        status = ConnectionStatus.error;
        errorMessage = '主机已断开连接';
        notifyListeners();
        break;

      case 'error':
        status = ConnectionStatus.error;
        errorMessage = msg['message'] as String? ?? '未知错误';
        notifyListeners();
        break;
    }
  }

  void sendInput(RemoteInputEvent event) {
    if (role == SessionRole.viewer) {
      _webrtc.sendInputEvent(event);
    }
  }

  Future<void> disconnect() async {
    await _webrtc.disposePeer();
    await _signaling.disconnect();
    status = ConnectionStatus.disconnected;
    roomId = null;
    clientId = null;
    role = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _webrtc.dispose();
    _signaling.dispose();
    super.dispose();
  }
}
