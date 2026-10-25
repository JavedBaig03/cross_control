import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cross_control/models/connection_state.dart';
import 'package:cross_control/models/peer_info.dart';
import 'package:cross_control/services/screen_stream_service.dart';
import 'package:cross_control/services/storage_service.dart';
import 'package:cross_control/ui/screens/controller_screen.dart';

void main() {
  group('Screen Stream Pipeline & Architecture Tests', () {
    test('StorageService defines tcpScreenPort correctly', () {
      expect(StorageService.tcpScreenPort, 42071);
      expect(StorageService.tcpControlPort, 42070);
      expect(StorageService.udpDiscoveryPort, 42069);
    });

    test('ScreenStreamService handles stream packet framing and reassembly', () async {
      final service = ScreenStreamService();

      // Start local test server on an ephemeral port
      final testServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final testPort = testServer.port;

      // Dummy 1x1 JPEG frame header
      final sampleJpeg = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9
      ]);

      Socket? serverClient;
      testServer.listen((client) {
        serverClient = client;
      });

      final receivedFrames = <Uint8List>[];
      final connected = await service.connectToStream(
        host: '127.0.0.1',
        port: testPort,
        onFrame: (frame) {
          receivedFrames.add(frame);
        },
      );

      expect(connected, isTrue);
      expect(service.isControllerStreamConnected, isTrue);

      // Wait a moment for server to register connection
      await Future.delayed(const Duration(milliseconds: 100));
      expect(serverClient, isNotNull);

      // Send framed payload: [4-byte big-endian length] + [sampleJpeg]
      final header = ByteData(4)..setUint32(0, sampleJpeg.length, Endian.big);
      serverClient!.add(header.buffer.asUint8List());
      serverClient!.add(sampleJpeg);
      await serverClient!.flush();

      // Wait for client to parse and deliver frame
      await Future.delayed(const Duration(milliseconds: 150));

      expect(receivedFrames.length, 1);
      expect(receivedFrames.first, equals(sampleJpeg));
      expect(service.currentFrameNotifier.value, equals(sampleJpeg));

      // Test split chunks / fragmented delivery across TCP packets
      serverClient!.add(header.buffer.asUint8List().sublist(0, 2)); // partial header
      await serverClient!.flush();
      await Future.delayed(const Duration(milliseconds: 50));

      serverClient!.add(header.buffer.asUint8List().sublist(2, 4)); // rest of header
      serverClient!.add(sampleJpeg.sublist(0, 10)); // partial payload
      await serverClient!.flush();
      await Future.delayed(const Duration(milliseconds: 50));

      serverClient!.add(sampleJpeg.sublist(10)); // remaining payload
      await serverClient!.flush();
      await Future.delayed(const Duration(milliseconds: 150));

      expect(receivedFrames.length, 2);
      expect(receivedFrames[1], equals(sampleJpeg));

      // Clean teardown
      await service.disconnectStream();
      expect(service.isControllerStreamConnected, isFalse);
      expect(service.currentFrameNotifier.value, isNull);

      await serverClient?.close();
      await testServer.close();
    });

    testWidgets('ControllerScreen renders live screen frame in View Only mode when received', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final peer = PeerInfo(
        key: 'CC-TEST',
        name: 'Streaming Machine',
        ip: '127.0.0.1',
        port: 42070,
        os: 'macos',
      );

      await tester.pumpWidget(MaterialApp(
        home: ControllerScreen(
          peer: peer,
          mode: SessionMode.viewOnly,
          onDisconnect: () {},
        ),
      ));
      await tester.pump();

      // Initially shows connecting state
      expect(find.text('Connecting to Streaming Machine...'), findsOneWidget);

      // Feed a sample 1x1 image into currentFrameNotifier
      // Minimal valid 1x1 PNG or JPEG
      final sampleImageBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
      ]);

      ScreenStreamService().currentFrameNotifier.value = sampleImageBytes;
      await tester.pump();

      // Now it displays the MemoryImage and the View Only non-intrusive badge
      expect(find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage), findsOneWidget);
      expect(find.text('Input Disabled (View Only)'), findsOneWidget);

      // Cleanup
      ScreenStreamService().currentFrameNotifier.value = null;
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('ControllerScreen renders live screen frame in View & Control mode with active input', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final peer = PeerInfo(
        key: 'CC-BOTH',
        name: 'Workstation',
        ip: '127.0.0.1',
        port: 42070,
        os: 'windows',
      );

      await tester.pumpWidget(MaterialApp(
        home: ControllerScreen(
          peer: peer,
          mode: SessionMode.viewAndControl,
          onDisconnect: () {},
        ),
      ));
      await tester.pump();

      final sampleImageBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
      ]);

      ScreenStreamService().currentFrameNotifier.value = sampleImageBytes;
      await tester.pump();

      expect(find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage), findsOneWidget);
      expect(find.text('Viewing & Controlling Workstation'), findsOneWidget);

      ScreenStreamService().currentFrameNotifier.value = null;
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
