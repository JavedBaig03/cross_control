import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:cross_control/main.dart';

void main() {
  testWidgets('CrossControl app launches and displays title and sections', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CrossControlApp());
    await tester.pump();

    // Verify Title
    expect(find.text('CrossControl'), findsOneWidget);
    // Verify Section 1 Header
    expect(find.text('CONNECT TO SYSTEM'), findsOneWidget);
    // Verify Connection Mode Header and default option
    expect(find.text('Connection Mode'), findsOneWidget);
    expect(find.text('Control Only'), findsWidgets);
    // Verify Section 2 Header
    expect(find.text('Enter Connection Key'), findsOneWidget);
    // Verify Connect button
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('Connection Mode dropdown allows selecting View Only and View & Control', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CrossControlApp());
    await tester.pump();

    // Default description for Control Only
    expect(
      find.text('Control the remote device using the keyboard and mouse, without screen streaming.'),
      findsOneWidget,
    );

    // Tap dropdown to open menu
    await tester.tap(find.text('Control Only').first);
    await tester.pump(const Duration(milliseconds: 300));

    // Select View Only
    await tester.tap(find.text('View Only').last);
    await tester.pump(const Duration(milliseconds: 300));

    // Description should update
    expect(
      find.text("View the remote device's screen without controlling its keyboard or mouse."),
      findsOneWidget,
    );

    // Tap dropdown again
    await tester.tap(find.text('View Only').first);
    await tester.pump(const Duration(milliseconds: 300));

    // Select View & Control
    await tester.tap(find.text('View & Control').last);
    await tester.pump(const Duration(milliseconds: 300));

    // Description should update
    expect(
      find.text('View the remote screen and control its keyboard and mouse simultaneously.'),
      findsOneWidget,
    );
  });
}
