import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeInputService {
  static final NativeInputService _instance = NativeInputService._internal();
  factory NativeInputService() => _instance;
  NativeInputService._internal();

  static const MethodChannel _channel = MethodChannel('com.crosscontrol/input_channel');

  /// Check whether the app has Accessibility permissions (macOS)
  Future<bool> checkAccessibilityPermission() async {
    if (!Platform.isMacOS) return true;
    try {
      final bool? trusted = await _channel.invokeMethod<bool>('checkAccessibilityPermission');
      return trusted ?? false;
    } catch (e) {
      debugPrint('Error checking accessibility: $e');
      return false;
    }
  }

  /// Request Accessibility permissions via system prompt (macOS)
  Future<bool> requestAccessibilityPermission() async {
    if (!Platform.isMacOS) return true;
    try {
      final bool? trusted = await _channel.invokeMethod<bool>('requestAccessibilityPermission');
      return trusted ?? false;
    } catch (e) {
      debugPrint('Error requesting accessibility: $e');
      return false;
    }
  }

  /// Open System Settings to Accessibility panel
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      debugPrint('Error opening accessibility settings: $e');
    }
  }

  /// Get device / computer name
  Future<String> getDeviceName() async {
    try {
      final String? name = await _channel.invokeMethod<String>('getDeviceName');
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } catch (e) {
      debugPrint('Error getting device name: $e');
    }

    if (Platform.isMacOS) return 'MacBook';
    if (Platform.isWindows) return 'Windows Laptop';
    return 'Laptop';
  }

  /// Get main screen size
  Future<Size> getScreenSize() async {
    try {
      final Map<dynamic, dynamic>? res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getScreenSize');
      if (res != null) {
        final double width = (res['width'] as num?)?.toDouble() ?? 1920.0;
        final double height = (res['height'] as num?)?.toDouble() ?? 1080.0;
        return Size(width, height);
      }
    } catch (e) {
      debugPrint('Error getting screen size: $e');
    }
    return const Size(1920, 1080);
  }

  /// Simulate mouse movement (delta or absolute)
  Future<void> simulateMouseMove({required double dx, required double dy, double? x, double? y}) async {
    try {
      await _channel.invokeMethod('simulateMouseMove', {
        'dx': dx,
        'dy': dy,
        'x': ?x,
        'y': ?y,
      });
    } catch (e) {
      // Ignore or debug
    }
  }

  /// Simulate mouse button press or release
  Future<void> simulateMouseButton({required int button, required bool isDown}) async {
    try {
      await _channel.invokeMethod('simulateMouseButton', {
        'button': button,
        'isDown': isDown,
      });
    } catch (e) {
      // Ignore or debug
    }
  }

  /// Simulate mouse wheel / scroll
  Future<void> simulateMouseScroll({required double dx, required double dy}) async {
    try {
      await _channel.invokeMethod('simulateMouseScroll', {
        'dx': dx,
        'dy': dy,
      });
    } catch (e) {
      // Ignore or debug
    }
  }

  /// Simulate key press or release
  Future<void> simulateKey({
    required int keyCode,
    required bool isDown,
    String? characters,
  }) async {
    try {
      await _channel.invokeMethod('simulateKey', {
        'keyCode': keyCode,
        'isDown': isDown,
        if (characters != null && characters.isNotEmpty) 'characters': characters,
      });
    } catch (e) {
      // Ignore or debug
    }
  }
}
