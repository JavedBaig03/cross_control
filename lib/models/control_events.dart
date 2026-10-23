import 'dart:convert';

/// Types of control events transferred across the network.
enum EventType {
  mouseMove,
  mouseButton,
  mouseScroll,
  keyEvent,
  pauseControl,
  resumeControl,
  ping,
  pong,
  disconnect,
  handshakeRequest,
  handshakeResponse,
  readyInit,
  readyAck,
}

abstract class ControlEvent {
  final EventType type;
  final int timestamp;

  ControlEvent({required this.type, int? timestamp})
      : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap();

  String serialize() => jsonEncode(toMap());

  static ControlEvent? deserialize(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final typeStr = map['t'] as String?;
      if (typeStr == null) return null;

      switch (typeStr) {
        case 'm':
          return MouseMoveEvent(
            dx: (map['dx'] as num?)?.toDouble() ?? 0.0,
            dy: (map['dy'] as num?)?.toDouble() ?? 0.0,
            x: (map['x'] as num?)?.toDouble(),
            y: (map['y'] as num?)?.toDouble(),
            timestamp: map['ts'] as int?,
          );
        case 'b':
          return MouseButtonEvent(
            button: map['btn'] as int? ?? 0,
            isDown: map['down'] as bool? ?? true,
            timestamp: map['ts'] as int?,
          );
        case 's':
          return MouseScrollEvent(
            dx: (map['dx'] as num?)?.toDouble() ?? 0.0,
            dy: (map['dy'] as num?)?.toDouble() ?? 0.0,
            timestamp: map['ts'] as int?,
          );
        case 'k':
          return KeyEventData(
            keyCode: map['code'] as int? ?? 0,
            windowsVk: map['wvk'] as int? ?? map['code'] as int? ?? 0,
            macosVk: map['mvk'] as int? ?? map['code'] as int? ?? 0,
            character: map['ch'] as String?,
            label: map['lbl'] as String? ?? '',
            isDown: map['down'] as bool? ?? true,
            meta: map['m'] as bool? ?? false,
            ctrl: map['c'] as bool? ?? false,
            alt: map['a'] as bool? ?? false,
            shift: map['sh'] as bool? ?? false,
            timestamp: map['ts'] as int?,
          );
        case 'p':
          return PauseEvent(
            isPaused: map['p'] as bool? ?? true,
            timestamp: map['ts'] as int?,
          );
        case 'r':
          return ResumeEvent(
            timestamp: map['ts'] as int?,
          );
        case 'ping':
          return PingEvent(timestamp: map['ts'] as int?);
        case 'pong':
          return PongEvent(timestamp: map['ts'] as int?);
        case 'disc':
          return DisconnectEvent(
            reason: map['r'] as String?,
            timestamp: map['ts'] as int?,
          );
        case 'ready_init':
          return ReadyInitEvent(timestamp: map['ts'] as int?);
        case 'ready_ack':
          return ReadyAckEvent(
            screenWidth: (map['sw'] as num?)?.toDouble() ?? 1920.0,
            screenHeight: (map['sh'] as num?)?.toDouble() ?? 1080.0,
            timestamp: map['ts'] as int?,
          );
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

class MouseMoveEvent extends ControlEvent {
  final double dx;
  final double dy;
  final double? x;
  final double? y;

  MouseMoveEvent({
    required this.dx,
    required this.dy,
    this.x,
    this.y,
    super.timestamp,
  }) : super(type: EventType.mouseMove);

  @override
  Map<String, dynamic> toMap() => {
        't': 'm',
        'dx': dx,
        'dy': dy,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        'ts': timestamp,
      };
}

class MouseButtonEvent extends ControlEvent {
  final int button; // 0: left, 1: right, 2: middle
  final bool isDown;

  MouseButtonEvent({
    required this.button,
    required this.isDown,
    super.timestamp,
  }) : super(type: EventType.mouseButton);

  @override
  Map<String, dynamic> toMap() => {
        't': 'b',
        'btn': button,
        'down': isDown,
        'ts': timestamp,
      };
}

class MouseScrollEvent extends ControlEvent {
  final double dx;
  final double dy;

  MouseScrollEvent({
    required this.dx,
    required this.dy,
    super.timestamp,
  }) : super(type: EventType.mouseScroll);

  @override
  Map<String, dynamic> toMap() => {
        't': 's',
        'dx': dx,
        'dy': dy,
        'ts': timestamp,
      };
}

class KeyEventData extends ControlEvent {
  final int keyCode;
  final int windowsVk;
  final int macosVk;
  final String? character;
  final String label;
  final bool isDown;
  final bool meta;
  final bool ctrl;
  final bool alt;
  final bool shift;

  KeyEventData({
    required this.keyCode,
    int? windowsVk,
    int? macosVk,
    this.character,
    required this.label,
    required this.isDown,
    this.meta = false,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    super.timestamp,
  })  : windowsVk = windowsVk ?? keyCode,
        macosVk = macosVk ?? keyCode,
        super(type: EventType.keyEvent);

  @override
  Map<String, dynamic> toMap() => {
        't': 'k',
        'code': keyCode,
        'wvk': windowsVk,
        'mvk': macosVk,
        'ch': ?character,
        'lbl': label,
        'down': isDown,
        'm': meta,
        'c': ctrl,
        'a': alt,
        'sh': shift,
        'ts': timestamp,
      };
}

class PauseEvent extends ControlEvent {
  final bool isPaused;

  PauseEvent({
    this.isPaused = true,
    super.timestamp,
  }) : super(type: EventType.pauseControl);

  @override
  Map<String, dynamic> toMap() => {
        't': 'p',
        'p': isPaused,
        'ts': timestamp,
      };
}

class ResumeEvent extends ControlEvent {
  ResumeEvent({super.timestamp}) : super(type: EventType.resumeControl);

  @override
  Map<String, dynamic> toMap() => {
        't': 'r',
        'ts': timestamp,
      };
}

class PingEvent extends ControlEvent {
  PingEvent({super.timestamp}) : super(type: EventType.ping);

  @override
  Map<String, dynamic> toMap() => {
        't': 'ping',
        'ts': timestamp,
      };
}

class PongEvent extends ControlEvent {
  PongEvent({super.timestamp}) : super(type: EventType.pong);

  @override
  Map<String, dynamic> toMap() => {
        't': 'pong',
        'ts': timestamp,
      };
}

class DisconnectEvent extends ControlEvent {
  final String? reason;

  DisconnectEvent({this.reason, super.timestamp})
      : super(type: EventType.disconnect);

  @override
  Map<String, dynamic> toMap() => {
        't': 'disc',
        if (reason != null) 'r': reason,
        'ts': timestamp,
      };
}

/// Handshake message types
class ConnectionRequest {
  final String fromKey;
  final String deviceName;
  final String platform;
  final String ip;

  ConnectionRequest({
    required this.fromKey,
    required this.deviceName,
    required this.platform,
    required this.ip,
  });

  Map<String, dynamic> toMap() => {
        'type': 'connect_request',
        'fromKey': fromKey,
        'deviceName': deviceName,
        'platform': platform,
        'ip': ip,
      };

  factory ConnectionRequest.fromMap(Map<String, dynamic> map) {
    return ConnectionRequest(
      fromKey: map['fromKey'] as String? ?? 'UNKNOWN',
      deviceName: map['deviceName'] as String? ?? 'Remote Device',
      platform: map['platform'] as String? ?? 'unknown',
      ip: map['ip'] as String? ?? '',
    );
  }
}

class ConnectionResponse {
  final bool accepted;
  final String? reason;
  final double? screenWidth;
  final double? screenHeight;

  ConnectionResponse({
    required this.accepted,
    this.reason,
    this.screenWidth,
    this.screenHeight,
  });

  Map<String, dynamic> toMap() => {
        'type': 'connect_response',
        'accepted': accepted,
        if (reason != null) 'reason': reason,
        if (screenWidth != null) 'screenWidth': screenWidth,
        if (screenHeight != null) 'screenHeight': screenHeight,
      };

  factory ConnectionResponse.fromMap(Map<String, dynamic> map) {
    return ConnectionResponse(
      accepted: map['accepted'] as bool? ?? false,
      reason: map['reason'] as String?,
      screenWidth: (map['screenWidth'] as num?)?.toDouble(),
      screenHeight: (map['screenHeight'] as num?)?.toDouble(),
    );
  }
}

class ReadyInitEvent extends ControlEvent {
  ReadyInitEvent({super.timestamp}) : super(type: EventType.readyInit);

  @override
  Map<String, dynamic> toMap() => {
        't': 'ready_init',
        'ts': timestamp,
      };
}

class ReadyAckEvent extends ControlEvent {
  final double screenWidth;
  final double screenHeight;

  ReadyAckEvent({
    required this.screenWidth,
    required this.screenHeight,
    super.timestamp,
  }) : super(type: EventType.readyAck);

  @override
  Map<String, dynamic> toMap() => {
        't': 'ready_ack',
        'sw': screenWidth,
        'sh': screenHeight,
        'ts': timestamp,
      };
}

