class RemoteInputEvent {
  const RemoteInputEvent({
    required this.type,
    this.x = 0,
    this.y = 0,
    this.button = 0,
    this.key,
    this.modifiers = const [],
    this.deltaY = 0,
  });

  final String type;
  final double x;
  final double y;
  final int button;
  final String? key;
  final List<String> modifiers;
  final double deltaY;

  Map<String, dynamic> toJson() => {
        'type': type,
        'x': x,
        'y': y,
        'button': button,
        if (key != null) 'key': key,
        if (modifiers.isNotEmpty) 'modifiers': modifiers,
        if (deltaY != 0) 'deltaY': deltaY,
      };

  factory RemoteInputEvent.fromJson(Map<String, dynamic> json) {
    return RemoteInputEvent(
      type: json['type'] as String,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      button: json['button'] as int? ?? 0,
      key: json['key'] as String?,
      modifiers: (json['modifiers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      deltaY: (json['deltaY'] as num?)?.toDouble() ?? 0,
    );
  }
}

enum SessionRole { host, viewer }

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  streaming,
  error,
}
