import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cross_control/models/connection_state.dart';
import 'package:cross_control/models/control_events.dart';
import 'package:cross_control/services/storage_service.dart';
import 'package:cross_control/services/key_mapping_service.dart';

void main() {
  group('ControlEvent Protocol Tests', () {
    test('MouseMoveEvent serialization and deserialization with absolute coords', () {
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

    test('MouseMoveEvent serialization and deserialization pure relative delta', () {
      final event = MouseMoveEvent(dx: 14.2, dy: -9.8);
      final json = event.serialize();
      final restored = ControlEvent.deserialize(json);

      expect(restored, isA<MouseMoveEvent>());
      final m = restored as MouseMoveEvent;
      expect(m.dx, 14.2);
      expect(m.dy, -9.8);
      expect(m.x, isNull);
      expect(m.y, isNull);
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
        windowsVk: 0x41,
        macosVk: 0,
        character: 'A',
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
      expect(k.windowsVk, 0x41);
      expect(k.macosVk, 0);
      expect(k.character, 'A');
    });

    test('PauseEvent and ResumeEvent serialization', () {
      final pause = PauseEvent(isPaused: true);
      final restoredPause = ControlEvent.deserialize(pause.serialize()) as PauseEvent;
      expect(restoredPause.isPaused, true);

      final resume = ResumeEvent();
      final restoredResume = ControlEvent.deserialize(resume.serialize()) as ResumeEvent;
      expect(restoredResume.type, EventType.resumeControl);
    });

    test('ReadyInitEvent and ReadyAckEvent 3-way handshake serialization', () {
      final init = ReadyInitEvent();
      final restoredInit = ControlEvent.deserialize(init.serialize()) as ReadyInitEvent;
      expect(restoredInit.type, EventType.readyInit);

      final ack = ReadyAckEvent(screenWidth: 2560, screenHeight: 1440);
      final restoredAck = ControlEvent.deserialize(ack.serialize()) as ReadyAckEvent;
      expect(restoredAck.type, EventType.readyAck);
      expect(restoredAck.screenWidth, 2560);
      expect(restoredAck.screenHeight, 1440);
    });

    test('KeyMappingService maps Backspace and keys accurately for Mac and Windows', () {
      final mapper = KeyMappingService();

      // Backspace: Win32 VK_BACK is 0x08, macOS kVK_Delete is 51 (NOT 42)
      final backspace = mapper.resolve(
        LogicalKeyboardKey.backspace,
        PhysicalKeyboardKey.backspace,
      );
      expect(backspace.windowsVk, 0x08);
      expect(backspace.macosVk, 51); // 51 is kVK_Delete, 42 was kVK_ANSI_Backslash causing the '\' bug

      // Return/Enter: Win32 VK_RETURN is 0x0D, macOS kVK_Return is 36
      final enter = mapper.resolve(
        LogicalKeyboardKey.enter,
        PhysicalKeyboardKey.enter,
      );
      expect(enter.windowsVk, 0x0D);
      expect(enter.macosVk, 36);

      // Key A: Win32 VK 0x41, macOS kVK_ANSI_A is 0
      final keyA = mapper.resolve(
        LogicalKeyboardKey.keyA,
        PhysicalKeyboardKey.keyA,
      );
      expect(keyA.windowsVk, 0x41);
      expect(keyA.macosVk, 0);
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
      expect(reqRestored.mode, SessionMode.controlOnly); // default
    });

    test('SessionMode labels, descriptions, and wire conversions', () {
      expect(SessionMode.controlOnly.label, 'Control Only');
      expect(SessionMode.viewOnly.label, 'View Only');
      expect(SessionMode.viewAndControl.label, 'View & Control');

      expect(SessionMode.controlOnly.description,
          'Control the remote device using the keyboard and mouse, without screen streaming.');
      expect(SessionMode.viewOnly.description,
          "View the remote device's screen without controlling its keyboard or mouse.");
      expect(SessionMode.viewAndControl.description,
          'View the remote screen and control its keyboard and mouse simultaneously.');

      expect(SessionMode.controlOnly.allowsControl, isTrue);
      expect(SessionMode.controlOnly.allowsView, isFalse);

      expect(SessionMode.viewOnly.allowsControl, isFalse);
      expect(SessionMode.viewOnly.allowsView, isTrue);

      expect(SessionMode.viewAndControl.allowsControl, isTrue);
      expect(SessionMode.viewAndControl.allowsView, isTrue);

      expect(SessionMode.fromWireString('control_only'), SessionMode.controlOnly);
      expect(SessionMode.fromWireString('view_only'), SessionMode.viewOnly);
      expect(SessionMode.fromWireString('view_and_control'), SessionMode.viewAndControl);
      expect(SessionMode.fromWireString('unknown'), SessionMode.controlOnly);
      expect(SessionMode.fromWireString(null), SessionMode.controlOnly);
    });

    test('ConnectionRequest and Response preserve explicit SessionMode', () {
      for (final mode in SessionMode.values) {
        final req = ConnectionRequest(
          fromKey: 'CC-1234',
          deviceName: 'Tester PC',
          platform: 'windows',
          ip: '192.168.1.50',
          mode: mode,
        );
        final map = req.toMap();
        expect(map['mode'], mode.toWireString());

        final restored = ConnectionRequest.fromMap(map);
        expect(restored.mode, mode);

        final res = ConnectionResponse(
          accepted: true,
          mode: mode,
        );
        final resMap = res.toMap();
        expect(resMap['mode'], mode.toWireString());

        final resRestored = ConnectionResponse.fromMap(resMap);
        expect(resRestored.mode, mode);
      }
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
