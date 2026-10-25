import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeInputService {
  static final NativeInputService _instance = NativeInputService._internal();
  factory NativeInputService() => _instance;
  NativeInputService._internal() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const MethodChannel _channel = MethodChannel('com.crosscontrol/input_channel');

  /// Callback when native platform intercepts a system-reserved key (e.g. Windows key or Alt+Space on Windows)
  void Function({required int vk, required bool isDown, required bool isWinKey, required bool alt})? onInterceptedKey;

  /// Callback when native platform emits a captured screen frame
  void Function(Uint8List frameBytes)? onScreenFrame;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onInterceptedKey') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      if (args != null) {
        final vk = args['vk'] as int? ?? 0;
        final isDown = args['isDown'] as bool? ?? true;
        final isWinKey = args['isWinKey'] as bool? ?? false;
        final alt = args['alt'] as bool? ?? false;
        onInterceptedKey?.call(vk: vk, isDown: isDown, isWinKey: isWinKey, alt: alt);
      }
    } else if (call.method == 'onScreenFrame') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      if (args != null) {
        final frame = args['frame'] as Uint8List?;
        if (frame != null) {
          onScreenFrame?.call(frame);
        }
      }
    }
  }

  /// Confine pointer to window / control surface bounds
  Future<void> confinePointer(bool enable) async {
    try {
      await _channel.invokeMethod('confinePointer', {'enable': enable});
    } catch (e) {
      debugPrint('Error confining pointer: $e');
    }
  }

  /// Warp pointer to specific coordinates, or window center if omitted
  Future<void> warpPointer([double? x, double? y]) async {
    try {
      final Map<String, dynamic> args = {};
      if (x != null && y != null) {
        args['x'] = x;
        args['y'] = y;
      }
      await _channel.invokeMethod('warpPointer', args);
    } catch (e) {
      debugPrint('Error warping pointer: $e');
    }
  }

  /// Reset remote cursor tracking on receiver
  Future<void> resetRemoteCursor() async {
    try {
      await _channel.invokeMethod('resetRemoteCursor');
    } catch (_) {}
  }

  /// Enable or disable low-level system key interception (e.g. Windows Start Menu suppression)
  Future<void> setLocalInputInterception(bool enable) async {
    try {
      await _channel.invokeMethod('setLocalInputInterception', {'enable': enable});
    } catch (e) {
      debugPrint('Error setting input interception: $e');
    }
  }

  /// Toggle native full-screen mode on macOS and Windows
  Future<void> setFullScreen(bool enable) async {
    try {
      await _channel.invokeMethod('setFullScreen', {'enable': enable});
    } catch (e) {
      debugPrint('Error toggling full screen: $e');
    }
  }

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
      final Map<String, dynamic> args = {
        'dx': dx,
        'dy': dy,
      };
      if (x != null) args['x'] = x;
      if (y != null) args['y'] = y;
      await _channel.invokeMethod('simulateMouseMove', args);
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

  /// Simulate key press or release with complete modifier states
  Future<void> simulateKey({
    required int keyCode,
    int? windowsVk,
    int? macosVk,
    required bool isDown,
    String? characters,
    bool meta = false,
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
  }) async {
    try {
      await _channel.invokeMethod('simulateKey', {
        'keyCode': keyCode,
        'windowsVk': ?windowsVk,
        'macosVk': ?macosVk,
        'isDown': isDown,
        'characters': ?characters,
        'meta': meta,
        'ctrl': ctrl,
        'alt': alt,
        'shift': shift,
      });
    } catch (e) {
      // Ignore or debug
    }
  }

  /// Check whether the app has Screen Recording permissions (macOS)
  Future<bool> checkScreenCapturePermission() async {
    if (!Platform.isMacOS) return true;
    try {
      final bool? trusted = await _channel.invokeMethod<bool>('checkScreenCapturePermission');
      return trusted ?? false;
    } catch (e) {
      debugPrint('Error checking screen capture permission: $e');
      return false;
    }
  }

  /// Request Screen Recording permissions via system prompt (macOS)
  Future<bool> requestScreenCapturePermission() async {
    if (!Platform.isMacOS) return true;
    try {
      final bool? trusted = await _channel.invokeMethod<bool>('requestScreenCapturePermission');
      return trusted ?? false;
    } catch (e) {
      debugPrint('Error requesting screen capture permission: $e');
      return false;
    }
  }

  /// Open System Settings to Screen Recording panel (macOS)
  Future<void> openScreenCaptureSettings() async {
    try {
      await _channel.invokeMethod('openScreenCaptureSettings');
    } catch (e) {
      debugPrint('Error opening screen capture settings: $e');
    }
  }

  /// Start continuous native screen capture streaming (SCStream on macOS, GDI on Windows)
  Future<bool> startScreenCapture({
    int fps = 20,
    double quality = 0.6,
    int width = 1280,
    int height = 720,
  }) async {
    try {
      final bool? res = await _channel.invokeMethod<bool>('startScreenCapture', {
        'fps': fps,
        'quality': quality,
        'width': width,
        'height': height,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Error starting native screen capture: $e');
      return false;
    }
  }

  /// Stop continuous native screen capture
  Future<void> stopScreenCapture() async {
    try {
      await _channel.invokeMethod('stopScreenCapture');
    } catch (e) {
      debugPrint('Error stopping native screen capture: $e');
    }
  }

  /// Capture a single screen frame on-demand as JPEG bytes
  Future<Uint8List?> captureScreenFrame({
    double quality = 0.6,
    int width = 1280,
    int height = 720,
  }) async {
    try {
      final dynamic res = await _channel.invokeMethod('captureScreenFrame', {
        'quality': quality,
        'width': width,
        'height': height,
      });
      if (res is Uint8List) {
        return res;
      }
      return null;
    } catch (e) {
      debugPrint('Error capturing single screen frame: $e');
      return null;
    }
  }
}
