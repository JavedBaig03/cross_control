import Cocoa
import FlutterMacOS
import ApplicationServices

class MainFlutterWindow: NSWindow {
  private var isLeftMouseDown = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupMethodChannel(controller: flutterViewController)

    super.awakeFromNib()
  }

  private func setupMethodChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.crosscontrol/input_channel",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any]

      switch call.method {
      case "checkAccessibilityPermission":
        let isTrusted = AXIsProcessTrusted()
        result(isTrusted)

      case "requestAccessibilityPermission":
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        result(isTrusted)

      case "openAccessibilitySettings":
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
          NSWorkspace.shared.open(url)
        }
        result(true)

      case "getScreenSize":
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        result(["width": Double(screen.width), "height": Double(screen.height)])

      case "getDeviceName":
        let name = Host.current().localizedName ?? Host.current().name ?? "MacBook"
        result(name)

      case "simulateMouseMove":
        if let args = args {
          self.handleMouseMove(args: args)
        }
        result(true)

      case "simulateMouseButton":
        if let args = args {
          self.handleMouseButton(args: args)
        }
        result(true)

      case "simulateMouseScroll":
        if let args = args {
          self.handleMouseScroll(args: args)
        }
        result(true)

      case "simulateKey":
        if let args = args {
          self.handleKey(args: args)
        }
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleMouseMove(args: [String: Any]) {
    var targetPt: CGPoint
    let current = CGEvent(source: nil)?.location ?? CGPoint(x: 500, y: 500)

    if let x = args["x"] as? Double, let y = args["y"] as? Double {
      targetPt = CGPoint(x: CGFloat(x), y: CGFloat(y))
    } else {
      let dx = args["dx"] as? Double ?? 0.0
      let dy = args["dy"] as? Double ?? 0.0
      let mainFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
      let newX = max(0, min(mainFrame.width - 1, current.x + CGFloat(dx)))
      let newY = max(0, min(mainFrame.height - 1, current.y + CGFloat(dy)))
      targetPt = CGPoint(x: newX, y: newY)
    }

    let eventType: CGEventType = isLeftMouseDown ? .leftMouseDragged : .mouseMoved
    let mouseEvent = CGEvent(
      mouseEventSource: nil,
      mouseType: eventType,
      mouseCursorPosition: targetPt,
      mouseButton: .left
    )
    mouseEvent?.post(tap: .cghidEventTap)
  }

  private func handleMouseButton(args: [String: Any]) {
    let button = args["button"] as? Int ?? 0 // 0: left, 1: right, 2: middle
    let isDown = args["isDown"] as? Bool ?? true
    let current = CGEvent(source: nil)?.location ?? CGPoint(x: 500, y: 500)

    var eventType: CGEventType
    var cgButton: CGMouseButton

    if button == 0 {
      isLeftMouseDown = isDown
      eventType = isDown ? .leftMouseDown : .leftMouseUp
      cgButton = .left
    } else if button == 1 {
      eventType = isDown ? .rightMouseDown : .rightMouseUp
      cgButton = .right
    } else {
      eventType = isDown ? .otherMouseDown : .otherMouseUp
      cgButton = .center
    }

    let mouseEvent = CGEvent(
      mouseEventSource: nil,
      mouseType: eventType,
      mouseCursorPosition: current,
      mouseButton: cgButton
    )
    mouseEvent?.post(tap: .cghidEventTap)
  }

  private func handleMouseScroll(args: [String: Any]) {
    let dx = args["dx"] as? Double ?? 0.0
    let dy = args["dy"] as? Double ?? 0.0
    let scrollEvent = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .pixel,
      wheelCount: 2,
      wheel1: Int32(dy),
      wheel2: Int32(dx),
      wheel3: 0
    )
    scrollEvent?.post(tap: .cghidEventTap)
  }

  private func handleKey(args: [String: Any]) {
    let macosVk = args["macosVk"] as? Int ?? args["keyCode"] as? Int ?? 0
    let isDown = args["isDown"] as? Bool ?? true
    let characters = args["characters"] as? String

    if let keyEvent = CGEvent(
      keyboardEventSource: nil,
      virtualKey: CGKeyCode(macosVk),
      keyDown: isDown
    ) {
      // Non-character control keys: Delete/Backspace (51), Return (36), Tab (48), Esc (53), ForwardDel (117), Arrows (123-126), Modifiers (55-62)
      let nonCharKeys: Set<Int> = [51, 36, 48, 53, 117, 123, 124, 125, 126, 55, 56, 57, 58, 59, 60, 61, 62]
      if let chars = characters, !chars.isEmpty && isDown && !nonCharKeys.contains(macosVk) {
        let utf16Chars = Array(chars.utf16)
        keyEvent.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
      }
      keyEvent.post(tap: .cghidEventTap)
    }
  }
}

