import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/remote_event.dart';
import 'signaling_service.dart';

class WebRTCService {
  WebRTCService(this._signaling);

  final SignalingService _signaling;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCDataChannel? _dataChannel;

  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();

  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  MediaStream? get remoteStream => _remoteStream;
  String? _peerId;

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  final List<Map<String, dynamic>> _pendingCandidates = [];

  void setClientId(String id) {
    // Reserved for future multi-viewer routing.
  }

  Future<void> initAsViewer() async {
    await _createPeerConnection(isHost: false);
    _statusController.add(ConnectionStatus.connecting);
  }

  Future<void> initAsHost({String? screenSourceId}) async {
    await _createPeerConnection(isHost: true);
    await _startScreenShare(screenSourceId: screenSourceId);
    _statusController.add(ConnectionStatus.connecting);
  }

  Future<void> _createPeerConnection({required bool isHost}) async {
    await disposePeer();

    _peerConnection = await createPeerConnection(_iceServers);

    _peerConnection!.onIceCandidate = (candidate) {
      if (_peerId != null) {
        _signaling.send({
          'type': 'ice-candidate',
          'targetId': _peerId,
          'payload': candidate.toMap(),
        });
      }
    };

    _peerConnection!.onTrack = (event) async {
      MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        stream = await createLocalMediaStream('remote-${event.track.id}');
        await stream.addTrack(event.track);
      }
      _remoteStream = stream;
      _remoteStreamController.add(_remoteStream);
      _statusController.add(ConnectionStatus.streaming);
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _statusController.add(ConnectionStatus.connected);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _statusController.add(ConnectionStatus.error);
      }
    };

    if (isHost) {
      _dataChannel = await _peerConnection!.createDataChannel(
        'input',
        RTCDataChannelInit()..ordered = true,
      );
      _setupDataChannel(_dataChannel!);
    } else {
      _peerConnection!.onDataChannel = (channel) {
        _dataChannel = channel;
        _setupDataChannel(channel);
      };
    }
  }

  void _setupDataChannel(RTCDataChannel channel) {
    channel.onMessage = (message) {
      // Host receives input via signaling; data channel reserved for future use.
    };
  }

  Future<void> _startScreenShare({String? screenSourceId}) async {
    final videoConstraints = screenSourceId != null
        ? <String, dynamic>{
            'deviceId': {'exact': screenSourceId},
            'mandatory': {'frameRate': 30.0},
          }
        : <String, dynamic>{
            'mandatory': {'frameRate': 30.0},
          };

    _localStream = await navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
      'audio': false,
      'video': videoConstraints,
    });

    for (final track in _localStream!.getVideoTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  Future<void> handleOffer(Map<String, dynamic> offer, String fromId) async {
    _peerId = fromId;
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
    );

    for (final c in _pendingCandidates) {
      await _peerConnection!.addCandidate(RTCIceCandidate(
        c['candidate'] as String,
        c['sdpMid'] as String?,
        c['sdpMLineIndex'] as int?,
      ));
    }
    _pendingCandidates.clear();

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _signaling.send({
      'type': 'answer',
      'targetId': fromId,
      'payload': answer.toMap(),
    });
  }

  Future<void> handleAnswer(Map<String, dynamic> answer) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
    );

    for (final c in _pendingCandidates) {
      await _peerConnection!.addCandidate(RTCIceCandidate(
        c['candidate'] as String,
        c['sdpMid'] as String?,
        c['sdpMLineIndex'] as int?,
      ));
    }
    _pendingCandidates.clear();
  }

  Future<void> handleIceCandidate(Map<String, dynamic> candidate) async {
    final remote = await _peerConnection?.getRemoteDescription();
    if (remote != null) {
      await _peerConnection!.addCandidate(RTCIceCandidate(
        candidate['candidate'] as String,
        candidate['sdpMid'] as String?,
        candidate['sdpMLineIndex'] as int?,
      ));
    } else {
      _pendingCandidates.add(candidate);
    }
  }

  Future<void> createOfferForViewer(String viewerId) async {
    _peerId = viewerId;
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _signaling.send({
      'type': 'offer',
      'targetId': viewerId,
      'payload': offer.toMap(),
    });
  }

  void sendInputEvent(RemoteInputEvent event) {
    _signaling.send({
      'type': 'input-event',
      'payload': event.toJson(),
    });
  }

  Future<void> disposePeer() async {
    await _dataChannel?.close();
    _dataChannel = null;

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    await _peerConnection?.close();
    _peerConnection = null;
    _remoteStream = null;
    _remoteStreamController.add(null);
    _peerId = null;
    _pendingCandidates.clear();
  }

  void dispose() {
    disposePeer();
    _remoteStreamController.close();
    _statusController.close();
  }
}
