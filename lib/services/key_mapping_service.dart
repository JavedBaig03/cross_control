import 'package:flutter/services.dart';

class NativeKeyCodes {
  final int windowsVk;
  final int macosVk;

  const NativeKeyCodes({
    required this.windowsVk,
    required this.macosVk,
  });
}

class KeyMappingService {
  static final KeyMappingService _instance = KeyMappingService._internal();
  factory KeyMappingService() => _instance;
  KeyMappingService._internal();

  /// Map LogicalKeyboardKey & PhysicalKeyboardKey to Windows Virtual Key (VK_...) and macOS Carbon Keycode (kVK_...)
  NativeKeyCodes resolveNativeCodes(KeyEvent event) {
    return resolve(event.logicalKey, event.physicalKey);
  }

  /// Resolve native codes directly from logical and physical keys
  NativeKeyCodes resolve(LogicalKeyboardKey logical, PhysicalKeyboardKey physical) {
    // 1. Navigation, Editing, and Control Keys
    if (logical == LogicalKeyboardKey.backspace) {
      return const NativeKeyCodes(windowsVk: 0x08, macosVk: 51); // VK_BACK, kVK_Delete
    }
    if (logical == LogicalKeyboardKey.enter || logical == LogicalKeyboardKey.numpadEnter) {
      return const NativeKeyCodes(windowsVk: 0x0D, macosVk: 36); // VK_RETURN, kVK_Return
    }
    if (logical == LogicalKeyboardKey.tab) {
      return const NativeKeyCodes(windowsVk: 0x09, macosVk: 48); // VK_TAB, kVK_Tab
    }
    if (logical == LogicalKeyboardKey.space) {
      return const NativeKeyCodes(windowsVk: 0x20, macosVk: 49); // VK_SPACE, kVK_Space
    }
    if (logical == LogicalKeyboardKey.escape) {
      return const NativeKeyCodes(windowsVk: 0x1B, macosVk: 53); // VK_ESCAPE, kVK_Escape
    }
    if (logical == LogicalKeyboardKey.delete) {
      return const NativeKeyCodes(windowsVk: 0x2E, macosVk: 117); // VK_DELETE, kVK_ForwardDelete
    }

    // Arrows
    if (logical == LogicalKeyboardKey.arrowLeft) {
      return const NativeKeyCodes(windowsVk: 0x25, macosVk: 123); // VK_LEFT, kVK_LeftArrow
    }
    if (logical == LogicalKeyboardKey.arrowUp) {
      return const NativeKeyCodes(windowsVk: 0x26, macosVk: 126); // VK_UP, kVK_UpArrow
    }
    if (logical == LogicalKeyboardKey.arrowRight) {
      return const NativeKeyCodes(windowsVk: 0x27, macosVk: 124); // VK_RIGHT, kVK_RightArrow
    }
    if (logical == LogicalKeyboardKey.arrowDown) {
      return const NativeKeyCodes(windowsVk: 0x28, macosVk: 125); // VK_DOWN, kVK_DownArrow
    }

    // Navigation
    if (logical == LogicalKeyboardKey.home) {
      return const NativeKeyCodes(windowsVk: 0x24, macosVk: 115);
    }
    if (logical == LogicalKeyboardKey.end) {
      return const NativeKeyCodes(windowsVk: 0x23, macosVk: 119);
    }
    if (logical == LogicalKeyboardKey.pageUp) {
      return const NativeKeyCodes(windowsVk: 0x21, macosVk: 116);
    }
    if (logical == LogicalKeyboardKey.pageDown) {
      return const NativeKeyCodes(windowsVk: 0x22, macosVk: 121);
    }

    // Modifiers
    if (logical == LogicalKeyboardKey.shiftLeft) {
      return const NativeKeyCodes(windowsVk: 0xA0, macosVk: 56);
    }
    if (logical == LogicalKeyboardKey.shiftRight) {
      return const NativeKeyCodes(windowsVk: 0xA1, macosVk: 60);
    }
    if (logical == LogicalKeyboardKey.controlLeft) {
      return const NativeKeyCodes(windowsVk: 0xA2, macosVk: 59);
    }
    if (logical == LogicalKeyboardKey.controlRight) {
      return const NativeKeyCodes(windowsVk: 0xA3, macosVk: 62);
    }
    if (logical == LogicalKeyboardKey.altLeft) {
      return const NativeKeyCodes(windowsVk: 0xA4, macosVk: 58);
    }
    if (logical == LogicalKeyboardKey.altRight) {
      return const NativeKeyCodes(windowsVk: 0xA5, macosVk: 61);
    }
    if (logical == LogicalKeyboardKey.metaLeft) {
      return const NativeKeyCodes(windowsVk: 0x5B, macosVk: 55); // Win / Command
    }
    if (logical == LogicalKeyboardKey.metaRight) {
      return const NativeKeyCodes(windowsVk: 0x5C, macosVk: 55);
    }
    if (logical == LogicalKeyboardKey.capsLock) {
      return const NativeKeyCodes(windowsVk: 0x14, macosVk: 57);
    }

    // Function keys F1 - F12
    if (logical == LogicalKeyboardKey.f1) return const NativeKeyCodes(windowsVk: 0x70, macosVk: 122);
    if (logical == LogicalKeyboardKey.f2) return const NativeKeyCodes(windowsVk: 0x71, macosVk: 120);
    if (logical == LogicalKeyboardKey.f3) return const NativeKeyCodes(windowsVk: 0x72, macosVk: 99);
    if (logical == LogicalKeyboardKey.f4) return const NativeKeyCodes(windowsVk: 0x73, macosVk: 118);
    if (logical == LogicalKeyboardKey.f5) return const NativeKeyCodes(windowsVk: 0x74, macosVk: 96);
    if (logical == LogicalKeyboardKey.f6) return const NativeKeyCodes(windowsVk: 0x75, macosVk: 97);
    if (logical == LogicalKeyboardKey.f7) return const NativeKeyCodes(windowsVk: 0x76, macosVk: 98);
    if (logical == LogicalKeyboardKey.f8) return const NativeKeyCodes(windowsVk: 0x77, macosVk: 100);
    if (logical == LogicalKeyboardKey.f9) return const NativeKeyCodes(windowsVk: 0x78, macosVk: 101);
    if (logical == LogicalKeyboardKey.f10) return const NativeKeyCodes(windowsVk: 0x79, macosVk: 109);
    if (logical == LogicalKeyboardKey.f11) return const NativeKeyCodes(windowsVk: 0x7A, macosVk: 103);
    if (logical == LogicalKeyboardKey.f12) return const NativeKeyCodes(windowsVk: 0x7B, macosVk: 111);

    // Physical key mappings for Letters
    if (physical == PhysicalKeyboardKey.keyA) return const NativeKeyCodes(windowsVk: 0x41, macosVk: 0);
    if (physical == PhysicalKeyboardKey.keyB) return const NativeKeyCodes(windowsVk: 0x42, macosVk: 11);
    if (physical == PhysicalKeyboardKey.keyC) return const NativeKeyCodes(windowsVk: 0x43, macosVk: 8);
    if (physical == PhysicalKeyboardKey.keyD) return const NativeKeyCodes(windowsVk: 0x44, macosVk: 2);
    if (physical == PhysicalKeyboardKey.keyE) return const NativeKeyCodes(windowsVk: 0x45, macosVk: 14);
    if (physical == PhysicalKeyboardKey.keyF) return const NativeKeyCodes(windowsVk: 0x46, macosVk: 3);
    if (physical == PhysicalKeyboardKey.keyG) return const NativeKeyCodes(windowsVk: 0x47, macosVk: 5);
    if (physical == PhysicalKeyboardKey.keyH) return const NativeKeyCodes(windowsVk: 0x48, macosVk: 4);
    if (physical == PhysicalKeyboardKey.keyI) return const NativeKeyCodes(windowsVk: 0x49, macosVk: 34);
    if (physical == PhysicalKeyboardKey.keyJ) return const NativeKeyCodes(windowsVk: 0x4A, macosVk: 38);
    if (physical == PhysicalKeyboardKey.keyK) return const NativeKeyCodes(windowsVk: 0x4B, macosVk: 40);
    if (physical == PhysicalKeyboardKey.keyL) return const NativeKeyCodes(windowsVk: 0x4C, macosVk: 37);
    if (physical == PhysicalKeyboardKey.keyM) return const NativeKeyCodes(windowsVk: 0x4D, macosVk: 46);
    if (physical == PhysicalKeyboardKey.keyN) return const NativeKeyCodes(windowsVk: 0x4E, macosVk: 45);
    if (physical == PhysicalKeyboardKey.keyO) return const NativeKeyCodes(windowsVk: 0x4F, macosVk: 31);
    if (physical == PhysicalKeyboardKey.keyP) return const NativeKeyCodes(windowsVk: 0x50, macosVk: 35);
    if (physical == PhysicalKeyboardKey.keyQ) return const NativeKeyCodes(windowsVk: 0x51, macosVk: 12);
    if (physical == PhysicalKeyboardKey.keyR) return const NativeKeyCodes(windowsVk: 0x52, macosVk: 15);
    if (physical == PhysicalKeyboardKey.keyS) return const NativeKeyCodes(windowsVk: 0x53, macosVk: 1);
    if (physical == PhysicalKeyboardKey.keyT) return const NativeKeyCodes(windowsVk: 0x54, macosVk: 17);
    if (physical == PhysicalKeyboardKey.keyU) return const NativeKeyCodes(windowsVk: 0x55, macosVk: 32);
    if (physical == PhysicalKeyboardKey.keyV) return const NativeKeyCodes(windowsVk: 0x56, macosVk: 9);
    if (physical == PhysicalKeyboardKey.keyW) return const NativeKeyCodes(windowsVk: 0x57, macosVk: 13);
    if (physical == PhysicalKeyboardKey.keyX) return const NativeKeyCodes(windowsVk: 0x58, macosVk: 7);
    if (physical == PhysicalKeyboardKey.keyY) return const NativeKeyCodes(windowsVk: 0x59, macosVk: 16);
    if (physical == PhysicalKeyboardKey.keyZ) return const NativeKeyCodes(windowsVk: 0x5A, macosVk: 6);

    // Number Row
    if (physical == PhysicalKeyboardKey.digit1) return const NativeKeyCodes(windowsVk: 0x31, macosVk: 18);
    if (physical == PhysicalKeyboardKey.digit2) return const NativeKeyCodes(windowsVk: 0x32, macosVk: 19);
    if (physical == PhysicalKeyboardKey.digit3) return const NativeKeyCodes(windowsVk: 0x33, macosVk: 20);
    if (physical == PhysicalKeyboardKey.digit4) return const NativeKeyCodes(windowsVk: 0x34, macosVk: 21);
    if (physical == PhysicalKeyboardKey.digit5) return const NativeKeyCodes(windowsVk: 0x35, macosVk: 23);
    if (physical == PhysicalKeyboardKey.digit6) return const NativeKeyCodes(windowsVk: 0x36, macosVk: 22);
    if (physical == PhysicalKeyboardKey.digit7) return const NativeKeyCodes(windowsVk: 0x37, macosVk: 26);
    if (physical == PhysicalKeyboardKey.digit8) return const NativeKeyCodes(windowsVk: 0x38, macosVk: 28);
    if (physical == PhysicalKeyboardKey.digit9) return const NativeKeyCodes(windowsVk: 0x39, macosVk: 25);
    if (physical == PhysicalKeyboardKey.digit0) return const NativeKeyCodes(windowsVk: 0x30, macosVk: 29);

    // Symbols & Punctuation
    if (physical == PhysicalKeyboardKey.minus) return const NativeKeyCodes(windowsVk: 0xBD, macosVk: 27);
    if (physical == PhysicalKeyboardKey.equal) return const NativeKeyCodes(windowsVk: 0xBB, macosVk: 24);
    if (physical == PhysicalKeyboardKey.bracketLeft) return const NativeKeyCodes(windowsVk: 0xDB, macosVk: 33);
    if (physical == PhysicalKeyboardKey.bracketRight) return const NativeKeyCodes(windowsVk: 0xDD, macosVk: 30);
    if (physical == PhysicalKeyboardKey.backslash) return const NativeKeyCodes(windowsVk: 0xDC, macosVk: 42);
    if (physical == PhysicalKeyboardKey.semicolon) return const NativeKeyCodes(windowsVk: 0xBA, macosVk: 41);
    if (physical == PhysicalKeyboardKey.quote) return const NativeKeyCodes(windowsVk: 0xDE, macosVk: 39);
    if (physical == PhysicalKeyboardKey.comma) return const NativeKeyCodes(windowsVk: 0xBC, macosVk: 43);
    if (physical == PhysicalKeyboardKey.period) return const NativeKeyCodes(windowsVk: 0xBE, macosVk: 47);
    if (physical == PhysicalKeyboardKey.slash) return const NativeKeyCodes(windowsVk: 0xBF, macosVk: 44);
    if (physical == PhysicalKeyboardKey.backquote) return const NativeKeyCodes(windowsVk: 0xC0, macosVk: 50);

    // Fallback: use keyId / usbHid
    final usbHid = physical.usbHidUsage & 0xFF;
    return NativeKeyCodes(windowsVk: usbHid, macosVk: usbHid);
  }
}
