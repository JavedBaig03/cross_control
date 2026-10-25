import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cross_control/models/connection_state.dart';
import 'package:cross_control/models/control_events.dart';
import 'package:cross_control/models/peer_info.dart';
import 'package:cross_control/ui/screens/controller_screen.dart';
import 'package:cross_control/ui/screens/receiver_screen.dart';
import 'package:cross_control/ui/widgets/connection_request_dialog.dart';

void main() {
  group('Connection Mode UI & Enforcement Tests', () {
    testWidgets('ConnectionRequestDialog displays correct mode label and security notice for each mode', (WidgetTester tester) async {
      // 1. Control Only
      final reqControl = ConnectionRequest(
        fromKey: 'CC-1111',
        deviceName: 'MacBook Alpha',
        platform: 'macos',
        ip: '192.168.1.100',
        mode: SessionMode.controlOnly,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConnectionRequestDialog(
            request: reqControl,
            onAccept: () {},
            onReject: () {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('Control Only'), findsOneWidget);
      expect(
        find.text('Approving will allow this device to control your mouse pointer and type keystrokes on this laptop.'),
        findsOneWidget,
      );

      // 2. View Only
      final reqView = ConnectionRequest(
        fromKey: 'CC-2222',
        deviceName: 'Windows Beta',
        platform: 'windows',
        ip: '192.168.1.101',
        mode: SessionMode.viewOnly,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConnectionRequestDialog(
            request: reqView,
            onAccept: () {},
            onReject: () {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('View Only'), findsOneWidget);
      expect(
        find.text('Approving will allow this device to view your screen in View Only mode. Remote keyboard and mouse control are disabled.'),
        findsOneWidget,
      );

      // 3. View & Control
      final reqBoth = ConnectionRequest(
        fromKey: 'CC-3333',
        deviceName: 'Ubuntu Gamma',
        platform: 'linux',
        ip: '192.168.1.102',
        mode: SessionMode.viewAndControl,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConnectionRequestDialog(
            request: reqBoth,
            onAccept: () {},
            onReject: () {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('View & Control'), findsOneWidget);
      expect(
        find.text('Approving will allow this device to view your screen and control your mouse pointer and keyboard.'),
        findsOneWidget,
      );
    });

    testWidgets('ReceiverScreen in View Only mode ignores mouse and key events', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final key = GlobalKey<ReceiverScreenState>();
      final request = ConnectionRequest(
        fromKey: 'CC-7777',
        deviceName: 'Remote Controller',
        platform: 'windows',
        ip: '192.168.1.200',
        mode: SessionMode.viewOnly,
      );

      await tester.pumpWidget(MaterialApp(
        home: ReceiverScreen(
          key: key,
          request: request,
          onDisconnect: () {},
        ),
      ));
      await tester.pump();

      expect(find.text('VIEW ONLY'), findsOneWidget);
      expect(find.text('Viewed by Remote Controller'), findsOneWidget);

      // Send MouseMoveEvent to receiver screen
      key.currentState?.handleIncomingEvent(MouseMoveEvent(dx: 50, dy: 50));
      await tester.pump(const Duration(milliseconds: 250));

      // In View Only mode, event description indicates input ignored
      expect(find.text('Input ignored: Session in View Only mode'), findsOneWidget);

      // Send KeyEventData to receiver screen
      key.currentState?.handleIncomingEvent(KeyEventData(
        keyCode: 65,
        label: 'A',
        isDown: true,
      ));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Input ignored: Session in View Only mode'), findsOneWidget);
    });

    testWidgets('ControllerScreen in View Only mode displays clean view interface without pointer confinement', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final peer = PeerInfo(
        key: 'CC-8888',
        name: 'Target Laptop',
        ip: '192.168.1.150',
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

      expect(find.text('VIEW ONLY'), findsOneWidget);
      expect(find.text('Connected to Target Laptop'), findsOneWidget);
      expect(find.text('Connection Mode: View Only'), findsOneWidget);
      expect(find.text('Disconnect Session'), findsOneWidget);
    });
  });
}
