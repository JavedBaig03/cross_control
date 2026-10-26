import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cross_control/models/connection_state.dart';
import 'package:cross_control/models/peer_info.dart';
import 'package:cross_control/ui/screens/controller_screen.dart';

void main() {
  group('Top Remote-Session Menu Auto-Hide & Edge Detection Tests', () {
    testWidgets('Top menu is visible initially, hides after 10s of inactivity, and reappears on top-edge hover', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool disconnected = false;
      final peer = PeerInfo(
        key: 'CC-TEST',
        name: "Javed's MacBook Air",
        ip: '127.0.0.1',
        port: 42070,
        os: 'macos',
      );

      await tester.pumpWidget(MaterialApp(
        home: ControllerScreen(
          peer: peer,
          mode: SessionMode.viewAndControl,
          onDisconnect: () {
            disconnected = true;
          },
        ),
      ));
      await tester.pump();

      // 1. Initial State: Top menu should be clearly displayed
      expect(find.text("Viewing & Controlling Javed's MacBook Air"), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      // Verify that the menu slide is at offset 0,0 and opacity 1.0
      final initialSlide = tester.widget<AnimatedSlide>(
        find.ancestor(
          of: find.text("Viewing & Controlling Javed's MacBook Air"),
          matching: find.byType(AnimatedSlide),
        ),
      );
      expect(initialSlide.offset, Offset.zero);

      final initialOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text("Viewing & Controlling Javed's MacBook Air"),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(initialOpacity.opacity, 1.0);

      // 2. User interacts after 5 seconds: moving mouse in workspace restarts 10s timer
      await tester.pump(const Duration(seconds: 5));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(500, 400));
      await gesture.moveTo(const Offset(510, 410));
      await tester.pump();

      // 4 seconds later (total 9s from start, but 4s from interaction): should STILL be visible!
      await tester.pump(const Duration(seconds: 4));
      final stillVisibleSlide = tester.widget<AnimatedSlide>(
        find.ancestor(
          of: find.text("Viewing & Controlling Javed's MacBook Air"),
          matching: find.byType(AnimatedSlide),
        ),
      );
      expect(stillVisibleSlide.offset, Offset.zero);

      // 3. Now let 10 seconds of full inactivity elapse without any interaction
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 300)); // finish animation

      final hiddenSlide = tester.widget<AnimatedSlide>(
        find.ancestor(
          of: find.text("Viewing & Controlling Javed's MacBook Air"),
          matching: find.byType(AnimatedSlide),
        ),
      );
      // Offset should be slid up out of view
      expect(hiddenSlide.offset.dy < 0, isTrue);

      final hiddenOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text("Viewing & Controlling Javed's MacBook Air"),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(hiddenOpacity.opacity, 0.0);

      // 4. While hidden, moving mouse in the center of the screen MUST NOT cause menu to pop up
      await gesture.moveTo(const Offset(600, 500));
      await tester.pump(const Duration(milliseconds: 100));

      final stillHiddenSlide = tester.widget<AnimatedSlide>(
        find.ancestor(
          of: find.text("Viewing & Controlling Javed's MacBook Air"),
          matching: find.byType(AnimatedSlide),
        ),
      );
      expect(stillHiddenSlide.offset.dy < 0, isTrue);

      // 5. Revealing: Moving cursor to the TOP EDGE (dy <= 20) reveals the menu immediately!
      await gesture.moveTo(const Offset(600, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // finish animation

      final revealedSlide = tester.widget<AnimatedSlide>(
        find.ancestor(
          of: find.text("Viewing & Controlling Javed's MacBook Air"),
          matching: find.byType(AnimatedSlide),
        ),
      );
      expect(revealedSlide.offset, Offset.zero);

      final revealedOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text("Viewing & Controlling Javed's MacBook Air"),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(revealedOpacity.opacity, 1.0);

      // 6. Access menu controls: clicking Disconnect when visible
      await tester.tap(find.text('Disconnect'));
      await tester.pump();
      expect(disconnected, isTrue);

      await gesture.removePointer();
    });

    testWidgets('Top bar in View Only mode also auto-hides after 10s and reveals on top edge', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final peer = PeerInfo(
        key: 'CC-VIEW',
        name: 'Remote Display',
        ip: '127.0.0.1',
        port: 42070,
        os: 'windows',
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

      final initialSlide = tester.widget<AnimatedSlide>(
        find.ancestor(
          of: find.text('VIEW ONLY'),
          matching: find.byType(AnimatedSlide),
        ),
      );
      expect(initialSlide.offset, Offset.zero);

      // 10s elapse with no interaction
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 300));

      final hiddenSlide = tester.widget<AnimatedSlide>(
        find.ancestor(
          of: find.text('VIEW ONLY'),
          matching: find.byType(AnimatedSlide),
        ),
      );
      expect(hiddenSlide.offset.dy < 0, isTrue);

      // Hover over top edge reveals it
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(400, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final revealedSlide = tester.widget<AnimatedSlide>(
        find.ancestor(
          of: find.text('VIEW ONLY'),
          matching: find.byType(AnimatedSlide),
        ),
      );
      expect(revealedSlide.offset, Offset.zero);

      await gesture.removePointer();
    });
  });
}
