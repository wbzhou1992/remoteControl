import '../models/remote_event.dart';

class InputInjectionService {
  static bool get isSupported => false;

  Future<void> inject(RemoteInputEvent event) async {}

  Future<void> setCaptureSource({
    String? sourceId,
    String? sourceName,
    String? sourceType,
  }) async {}
}
