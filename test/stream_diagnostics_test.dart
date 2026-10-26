import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cross_control/services/screen_stream_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Screen Stream Diagnostics & Metrics Tests', () {
    test('ScreenStreamService exposes reactive notifiers for FPS, Bitrate, and Resolution', () {
      final service = ScreenStreamService();

      expect(service.fpsNotifier.value, equals(0));
      expect(service.receivedFpsNotifier.value, equals(0));
      expect(service.bitrateMbpsNotifier.value, equals(0.0));
      expect(service.streamResolutionNotifier.value, isEmpty);
      expect(service.isStreamingNotifier.value, isFalse);
    });

    test('disconnectStream resets all diagnostic counters and notifiers', () async {
      final service = ScreenStreamService();

      service.fpsNotifier.value = 32;
      service.receivedFpsNotifier.value = 32;
      service.bitrateMbpsNotifier.value = 4.8;
      service.streamResolutionNotifier.value = '1920x1080';
      service.isStreamingNotifier.value = true;

      await service.disconnectStream();

      expect(service.fpsNotifier.value, equals(0));
      expect(service.receivedFpsNotifier.value, equals(0));
      expect(service.bitrateMbpsNotifier.value, equals(0.0));
      expect(service.streamResolutionNotifier.value, isEmpty);
      expect(service.isStreamingNotifier.value, isFalse);
    });

    test('Stream client receives multiple framed packets cleanly without backlog', () async {
      final service = ScreenStreamService();

      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      Socket? serverClient;
      server.listen((c) => serverClient = c);

      final frames = <Uint8List>[];
      final connected = await service.connectToStream(
        host: '127.0.0.1',
        port: port,
        onFrame: (f) => frames.add(f),
      );

      expect(connected, isTrue);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(serverClient, isNotNull);

      // Send 5 test frames
      final dummyPayload = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9
      ]);

      for (int i = 0; i < 5; i++) {
        final header = ByteData(4)..setUint32(0, dummyPayload.length, Endian.big);
        serverClient!.add(header.buffer.asUint8List());
        serverClient!.add(dummyPayload);
      }
      await serverClient!.flush();

      await Future.delayed(const Duration(milliseconds: 150));
      expect(frames.length, equals(5));

      await service.disconnectStream();
      await server.close();
    });
  });
}
