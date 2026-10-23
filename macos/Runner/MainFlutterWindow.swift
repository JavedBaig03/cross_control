import Cocoa
import FlutterMacOS
import ApplicationServices

class MainFlutterWindow: NSWindow {
  private var isLeftMouseDown = false
  private var isRightMouseDown = false
  private var isCursorHidden = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupMethodChannel(controller: flutterViewController)

    NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: self,
      queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      if self.isCursorHidden {
        NSCursor.unhide()
        self.isCursorHidden = false
      }
    }

    super.awakeFromNib()
  }

  deinit {
    if isCursorHidden {
      NSCursor.unhide()
      isCursorHidden = false
    }
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

      case "confinePointer":
        let enable = args?["enable"] as? Bool ?? false
        if enable {
          if !self.isCursorHidden {
            NSCursor.hide()
            self.isCursorHidden = true
          }
        } else {
          self.currentModifierFlags = []
          self.isLeftMouseDown = false
          self.isRightMouseDown = false
          self.remoteCursorPosition = nil
          if self.isCursorHidden {
            NSCursor.unhide()
            self.isCursorHidden = false
          }
        }
        result(true)

      case "setFullScreen":
        let enable = args?["enable"] as? Bool ?? false
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          if enable {
            if !self.styleMask.contains(.fullScreen) {
              self.toggleFullScreen(nil)
            }
          } else {
            if self.styleMask.contains(.fullScreen) {
              self.toggleFullScreen(nil)
            }
            if self.isCursorHidden {
              NSCursor.unhide()
              self.isCursorHidden = false
            }
          }
        }
        result(true)

      case "warpPointer":
        if let x = args?["x"] as? Double, let y = args?["y"] as? Double {
          let viewHeight = self.contentViewController?.view.bounds.height ?? self.frame.height
          let windowPoint = NSPoint(x: CGFloat(x), y: viewHeight - CGFloat(y))
          let screenPoint = self.convertToScreen(NSRect(origin: windowPoint, size: .zero)).origin
          let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
          let quartzY = primaryHeight - screenPoint.y
          let quartzX = screenPoint.x
          CGWarpMouseCursorPosition(CGPoint(x: quartzX, y: quartzY))
        } else {
          let windowFrame = self.frame
          let cocoaCenter = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
          let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
          let quartzCenter = CGPoint(x: cocoaCenter.x, y: primaryHeight - cocoaCenter.y)
          CGWarpMouseCursorPosition(quartzCenter)
        }
        result(true)

      case "setLocalInputInterception":
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private var remoteCursorPosition: CGPoint? = nil
  private var lastMouseMoveTime: TimeInterval = 0

  private func getInitialCursorPosition() -> CGPoint {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
    let cocoaPos = NSEvent.mouseLocation
    return CGPoint(x: cocoaPos.x, y: primaryHeight - cocoaPos.y)
  }

  private func handleMouseMove(args: [String: Any]) {
    let now = ProcessInfo.processInfo.systemUptime
    let dx = args["dx"] as? Double ?? 0.0
    let dy = args["dy"] as? Double ?? 0.0
    let hasExplicitX = (args["x"] != nil)

    // Calculate union bounding box of all screens in Quartz display coordinates
    var unionRect = CGRect.zero
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080
    for screen in NSScreen.screens {
      let quartzY = primaryHeight - (screen.frame.origin.y + screen.frame.height)
      let quartzRect = CGRect(x: screen.frame.origin.x, y: quartzY, width: screen.frame.width, height: screen.frame.height)
      unionRect = unionRect.isEmpty ? quartzRect : unionRect.union(quartzRect)
    }
    if unionRect.isEmpty {
      unionRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    var targetPt: CGPoint
    if hasExplicitX {
      let x = args["x"] as? Double ?? 0.0
      let y = args["y"] as? Double ?? 0.0
      targetPt = CGPoint(x: CGFloat(x), y: CGFloat(y))
      remoteCursorPosition = targetPt
    } else {
      if remoteCursorPosition == nil || (now - lastMouseMoveTime > 0.5) {
        remoteCursorPosition = getInitialCursorPosition()
      }
      let current = remoteCursorPosition!
      let newX = max(unionRect.minX, min(unionRect.maxX - 1, current.x + CGFloat(dx)))
      let newY = max(unionRect.minY, min(unionRect.maxY - 1, current.y + CGFloat(dy)))
      targetPt = CGPoint(x: newX, y: newY)
      remoteCursorPosition = targetPt
    }
    lastMouseMoveTime = now

    let eventType: CGEventType
    if isLeftMouseDown {
      eventType = .leftMouseDragged
    } else if isRightMouseDown {
      eventType = .rightMouseDragged
    } else {
      eventType = .mouseMoved
    }

    let mouseEvent = CGEvent(
      mouseEventSource: nil,
      mouseType: eventType,
      mouseCursorPosition: targetPt,
      mouseButton: isRightMouseDown ? .right : .left
    )
    mouseEvent?.post(tap: .cghidEventTap)
  }

  private func handleMouseButton(args: [String: Any]) {
    let button = args["button"] as? Int ?? 0 // 0: left, 1: right, 2: middle
    let isDown = args["isDown"] as? Bool ?? true
    let current = remoteCursorPosition ?? getInitialCursorPosition()

    var eventType: CGEventType
    var cgButton: CGMouseButton

    if button == 0 {
      isLeftMouseDown = isDown
      eventType = isDown ? .leftMouseDown : .leftMouseUp
      cgButton = .left
    } else if button == 1 {
      isRightMouseDown = isDown
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

  private var currentModifierFlags: CGEventFlags = []

  private func handleKey(args: [String: Any]) {
    let macosVk = args["macosVk"] as? Int ?? args["keyCode"] as? Int ?? 0
    let isDown = args["isDown"] as? Bool ?? true
    let characters = args["characters"] as? String
    let meta = args["meta"] as? Bool ?? false
    let ctrl = args["ctrl"] as? Bool ?? false
    let alt = args["alt"] as? Bool ?? false
    let shift = args["shift"] as? Bool ?? false

    // Maintain modifier flag states
    if macosVk == 55 { // Command
      if isDown { currentModifierFlags.insert(.maskCommand) } else { currentModifierFlags.remove(.maskCommand) }
    } else if macosVk == 58 || macosVk == 61 { // Option
      if isDown { currentModifierFlags.insert(.maskAlternate) } else { currentModifierFlags.remove(.maskAlternate) }
    } else if macosVk == 59 || macosVk == 62 { // Control
      if isDown { currentModifierFlags.insert(.maskControl) } else { currentModifierFlags.remove(.maskControl) }
    } else if macosVk == 56 || macosVk == 60 { // Shift
      if isDown { currentModifierFlags.insert(.maskShift) } else { currentModifierFlags.remove(.maskShift) }
    }

    if let keyEvent = CGEvent(
      keyboardEventSource: nil,
      virtualKey: CGKeyCode(macosVk),
      keyDown: isDown
    ) {
      var flags = currentModifierFlags
      if meta { flags.insert(.maskCommand) }
      if ctrl { flags.insert(.maskControl) }
      if alt { flags.insert(.maskAlternate) }
      if shift { flags.insert(.maskShift) }
      keyEvent.flags = flags

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

