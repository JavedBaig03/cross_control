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
    // Verify Section 2 Header
    expect(find.text('Enter Connection Key'), findsOneWidget);
    // Verify Connect button
    expect(find.text('Connect'), findsOneWidget);
  });
}
