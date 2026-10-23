import 'package:flutter_test/flutter_test.dart';
import 'package:cross_control/models/control_events.dart';
import 'package:cross_control/services/storage_service.dart';

void main() {
  group('ControlEvent Protocol Tests', () {
    test('MouseMoveEvent serialization and deserialization', () {
      final event = MouseMoveEvent(dx: 12.5, dy: -8.2, x: 500, y: 300);
      final json = event.serialize();
      final restored = ControlEvent.deserialize(json);

      expect(restored, isA<MouseMoveEvent>());
      final m = restored as MouseMoveEvent;
      expect(m.dx, 12.5);
      expect(m.dy, -8.2);
      expect(m.x, 500);
      expect(m.y, 300);
    });

    test('MouseButtonEvent serialization and deserialization', () {
      final event = MouseButtonEvent(button: 1, isDown: true);
      final json = event.serialize();
      final restored = ControlEvent.deserialize(json);

      expect(restored, isA<MouseButtonEvent>());
      final b = restored as MouseButtonEvent;
      expect(b.button, 1);
      expect(b.isDown, true);
    });

    test('MouseScrollEvent serialization and deserialization', () {
      final event = MouseScrollEvent(dx: 0.0, dy: -45.0);
      final json = event.serialize();
      final restored = ControlEvent.deserialize(json);

      expect(restored, isA<MouseScrollEvent>());
      final s = restored as MouseScrollEvent;
      expect(s.dx, 0.0);
      expect(s.dy, -45.0);
    });

    test('KeyEventData serialization and deserialization', () {
      final event = KeyEventData(
        keyCode: 4,
        label: 'A',
        isDown: true,
        ctrl: true,
        meta: false,
      );
      final json = event.serialize();
      final restored = ControlEvent.deserialize(json);

      expect(restored, isA<KeyEventData>());
      final k = restored as KeyEventData;
      expect(k.keyCode, 4);
      expect(k.label, 'A');
      expect(k.isDown, true);
      expect(k.ctrl, true);
      expect(k.meta, false);
    });

    test('PauseEvent and ResumeEvent serialization', () {
      final pause = PauseEvent(isPaused: true);
      final restoredPause = ControlEvent.deserialize(pause.serialize()) as PauseEvent;
      expect(restoredPause.isPaused, true);

      final resume = ResumeEvent();
      final restoredResume = ControlEvent.deserialize(resume.serialize()) as ResumeEvent;
      expect(restoredResume.type, EventType.resumeControl);
    });

    test('Handshake Request and Response mapping', () {
      final req = ConnectionRequest(
        fromKey: 'CC-9821',
        deviceName: "Javed's MacBook",
        platform: 'macos',
        ip: '192.168.1.10',
      );
      final reqMap = req.toMap();
      final reqRestored = ConnectionRequest.fromMap(reqMap);
      expect(reqRestored.fromKey, 'CC-9821');
      expect(reqRestored.deviceName, "Javed's MacBook");

      final res = ConnectionResponse(
        accepted: true,
        screenWidth: 2560,
        screenHeight: 1440,
      );
      final resMap = res.toMap();
      final resRestored = ConnectionResponse.fromMap(resMap);
      expect(resRestored.accepted, true);
      expect(resRestored.screenWidth, 2560);
      expect(resRestored.screenHeight, 1440);
    });
  });

  group('StorageService Tests', () {
    test('Generated connection key starts with CC- and has valid length', () {
      final key = StorageService().connectionKey;
      expect(key.startsWith('CC-'), isTrue);
      expect(key.length, 7); // CC-XXXX
    });
  });
}
