import 'dart:io';
import 'dart:math';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const int udpDiscoveryPort = 42069;
  static const int tcpControlPort = 42070;
  static const int tcpScreenPort = 42071;

  late final String connectionKey = _generateConnectionKey();
  String? deviceName;

  static String _generateConnectionKey() {
    final random = Random.secure();
    // 4 random uppercase alphanumeric characters or digits for easy typing
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final code = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    return 'CC-$code';
  }

  String get shortcutLabel {
    if (Platform.isMacOS) {
      return '⌃ + ⌥ + P';
    } else {
      return 'Ctrl + Alt + P';
    }
  }

  String get fullShortcutDescription {
    if (Platform.isMacOS) {
      return 'Control + Option + P';
    } else {
      return 'Control + Alt + P';
    }
  }
}
