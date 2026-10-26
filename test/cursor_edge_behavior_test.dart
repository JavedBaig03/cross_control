import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cross_control/models/connection_state.dart';
import 'package:cross_control/models/peer_info.dart';
import 'package:cross_control/services/screen_stream_service.dart';
import 'package:cross_control/ui/screens/controller_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> nativeCalls = [];

  setUp(() {
    nativeCalls.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.crosscontrol/input_channel'),
      (MethodCall methodCall) async {
        nativeCalls.add(methodCall);
        if (methodCall.method == 'getScreenSize') {
          return {'width': 1920.0, 'height': 1080.0};
        }
        return true;
      },
    );
  });

  tearDown(() {
    ScreenStreamService().disconnectStream();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.crosscontrol/input_channel'),
      null,
    );
  });

  group('Cursor Edge Behavior Tests (View & Control vs Control Only)', () {
    testWidgets('View & Control mode: reaching screen edge NEVER warps pointer back to center', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final peer = PeerInfo(
        key: 'CC-9999',
        name: 'MacBook Pro',
        ip: '127.0.0.1',
        port: 42070,
        os: 'macos',
      );

      await tester.pumpWidget(MaterialApp(
        home: ControllerScreen(
          peer: peer,
          mode: SessionMode.viewAndControl,
          targetScreenWidth: 1920,
          targetScreenHeight: 1080,
          onDisconnect: () {},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Clear initial startup calls (confinePointer, warpPointer from initState)
      nativeCalls.clear();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(960, 540));
      await tester.pump();

      // 1. Move gradually toward left edge (x = 10 < edgeMargin of 40)
      for (double x = 960; x >= 10; x -= 50) {
        await gesture.moveTo(Offset(x, 540));
        await tester.pump(const Duration(milliseconds: 16));
      }

      // In View & Control mode, edge recentering must NOT be triggered
      final leftWarpCalls = nativeCalls.where((c) => c.method == 'warpPointer').toList();
      expect(leftWarpCalls, isEmpty, reason: 'warpPointer must NOT be called when pointer approaches the left edge in View & Control mode');

      // 2. Move gradually toward top edge (y = 5 < edgeMargin of 40)
      for (double y = 540; y >= 5; y -= 50) {
        await gesture.moveTo(Offset(500, y));
        await tester.pump(const Duration(milliseconds: 16));
      }

      final topWarpCalls = nativeCalls.where((c) => c.method == 'warpPointer').toList();
      expect(topWarpCalls, isEmpty, reason: 'warpPointer must NOT be called when pointer approaches the top edge in View & Control mode');

      // 3. Move gradually toward right edge (x = 1915 > 1920 - 40)
      for (double x = 500; x <= 1915; x += 50) {
        await gesture.moveTo(Offset(x, 540));
        await tester.pump(const Duration(milliseconds: 16));
      }

      final rightWarpCalls = nativeCalls.where((c) => c.method == 'warpPointer').toList();
      expect(rightWarpCalls, isEmpty, reason: 'warpPointer must NOT be called when pointer approaches the right edge in View & Control mode');

      // 4. Move gradually toward bottom edge (y = 1075 > 1080 - 40)
      for (double y = 540; y <= 1075; y += 50) {
        await gesture.moveTo(Offset(960, y));
        await tester.pump(const Duration(milliseconds: 16));
      }

      final bottomWarpCalls = nativeCalls.where((c) => c.method == 'warpPointer').toList();
      expect(bottomWarpCalls, isEmpty, reason: 'warpPointer must NOT be called when pointer approaches the bottom edge in View & Control mode');

      await gesture.removePointer();
      // Allow connection timeout timer to expire cleanly
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Control Only mode: reaching screen boundary preserves deliberate recentering for continuous trackpad motion', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final peer = PeerInfo(
        key: 'CC-9999',
        name: 'MacBook Pro',
        ip: '127.0.0.1',
        port: 42070,
        os: 'macos',
      );

      await tester.pumpWidget(MaterialApp(
        home: ControllerScreen(
          peer: peer,
          mode: SessionMode.controlOnly,
          targetScreenWidth: 1920,
          targetScreenHeight: 1080,
          onDisconnect: () {},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Clear initial startup calls
      nativeCalls.clear();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(960, 540));
      await tester.pump();

      // Send small move at center to clear the initial startup warp flag
      await gesture.moveTo(const Offset(960, 540));
      await tester.pump();

      // Wait 250ms wall-clock to ensure 200ms cooldown has passed
      sleep(const Duration(milliseconds: 250));
      await tester.pump();

      // Move gradually toward edge (< 40 margin) with realistic deltas
      for (double x = 960; x >= 60; x -= 50) {
        await gesture.moveTo(Offset(x, 540));
        await tester.pump(const Duration(milliseconds: 20));
      }
      // Step into the boundary edge (< 40px)
      await gesture.moveTo(const Offset(20, 540));
      await tester.pump(const Duration(milliseconds: 20));

      // In Control Only mode, edge recentering IS preserved to allow continuous motion
      final warpCalls = nativeCalls.where((c) => c.method == 'warpPointer').toList();
      expect(warpCalls, isNotEmpty, reason: 'warpPointer should be called in Control Only mode when approaching edge');

      await gesture.removePointer();
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
