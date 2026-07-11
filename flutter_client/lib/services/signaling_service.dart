import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

typedef SignalingCallback = void Function(Map<String, dynamic> message);

class SignalingService {
  WebSocketChannel? _channel;
  SignalingCallback? onMessage;
  final _connectionController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(String serverUrl) async {
    await disconnect();
    final uri = Uri.parse(serverUrl);
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;

    _channel!.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          onMessage?.call(msg);
        } catch (_) {}
      },
      onDone: () {
        _connectionController.add(false);
      },
      onError: (_) {
        _connectionController.add(false);
      },
    );

    _connectionController.add(true);
  }

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _connectionController.close();
  }
}
