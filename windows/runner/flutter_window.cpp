#include "flutter_window.h"

#include <optional>
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

double GetDoubleValue(const flutter::EncodableMap& map, const std::string& key, double defaultValue = 0.0) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return defaultValue;
  if (const auto* val = std::get_if<double>(&it->second)) {
    return *val;
  }
  if (const auto* val = std::get_if<int32_t>(&it->second)) {
    return static_cast<double>(*val);
  }
  if (const auto* val = std::get_if<int64_t>(&it->second)) {
    return static_cast<double>(*val);
  }
  return defaultValue;
}

int GetIntValue(const flutter::EncodableMap& map, const std::string& key, int defaultValue = 0) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return defaultValue;
  if (const auto* val = std::get_if<int32_t>(&it->second)) {
    return *val;
  }
  if (const auto* val = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*val);
  }
  if (const auto* val = std::get_if<double>(&it->second)) {
    return static_cast<int>(*val);
  }
  return defaultValue;
}

bool GetBoolValue(const flutter::EncodableMap& map, const std::string& key, bool defaultValue = true) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return defaultValue;
  if (const auto* val = std::get_if<bool>(&it->second)) {
    return *val;
  }
  return defaultValue;
}

std::string GetStringValue(const flutter::EncodableMap& map, const std::string& key, const std::string& defaultValue = "") {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return defaultValue;
  if (const auto* val = std::get_if<std::string>(&it->second)) {
    return *val;
  }
  return defaultValue;
}

// Global hooks and channel pointers for Windows low-level input interception
static HHOOK g_keyboardHook = NULL;
static bool g_isInputInterceptionActive = false;
static flutter::MethodChannel<flutter::EncodableValue>* g_channel = nullptr;
static double g_accDx = 0.0;
static double g_accDy = 0.0;
static bool g_isCursorHidden = false;

static void SetCursorVisibility(bool visible) {
  if (!visible && !g_isCursorHidden) {
    ShowCursor(FALSE);
    g_isCursorHidden = true;
  } else if (visible && g_isCursorHidden) {
    ShowCursor(TRUE);
    g_isCursorHidden = false;
  }
}

LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode == HC_ACTION && g_isInputInterceptionActive) {
    KBDLLHOOKSTRUCT* pKey = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
    bool isDown = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);

    // 1. Always let emergency pause shortcut through (Ctrl + Alt + P)
    bool ctrlPressed = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
    bool altPressed = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
    if (pKey->vkCode == 'P' && ctrlPressed && altPressed) {
      return CallNextHookEx(g_keyboardHook, nCode, wParam, lParam);
    }

    // 2. Intercept Windows Key (VK_LWIN = 0x5B, VK_RWIN = 0x5C)
    // Suppress local Start menu, notify Flutter channel so it maps to Command on Mac!
    if (pKey->vkCode == VK_LWIN || pKey->vkCode == VK_RWIN) {
      if (g_channel) {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("vk")] = flutter::EncodableValue(static_cast<int>(pKey->vkCode));
        map[flutter::EncodableValue("isDown")] = flutter::EncodableValue(isDown);
        map[flutter::EncodableValue("isWinKey")] = flutter::EncodableValue(true);
        map[flutter::EncodableValue("alt")] = flutter::EncodableValue(altPressed);
        g_channel->InvokeMethod("onInterceptedKey", std::make_unique<flutter::EncodableValue>(map));
      }
      return 1; // Block from Windows Shell!
    }

    // 3. Intercept Alt + Space to prevent Windows Window Menu (SC_KEYMENU)
    if (pKey->vkCode == VK_SPACE && altPressed) {
      if (g_channel) {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("vk")] = flutter::EncodableValue(static_cast<int>(VK_SPACE));
        map[flutter::EncodableValue("isDown")] = flutter::EncodableValue(isDown);
        map[flutter::EncodableValue("isWinKey")] = flutter::EncodableValue(false);
        map[flutter::EncodableValue("alt")] = flutter::EncodableValue(true);
        g_channel->InvokeMethod("onInterceptedKey", std::make_unique<flutter::EncodableValue>(map));
      }
      return 1; // Block system menu!
    }
  }
  return CallNextHookEx(g_keyboardHook, nCode, wParam, lParam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  input_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.crosscontrol/input_channel",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel = input_channel_.get();

  input_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());

        if (call.method_name() == "checkAccessibilityPermission") {
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "requestAccessibilityPermission") {
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "openAccessibilitySettings") {
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "getScreenSize") {
          int width = GetSystemMetrics(SM_CXSCREEN);
          int height = GetSystemMetrics(SM_CYSCREEN);
          flutter::EncodableMap map;
          map[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<double>(width));
          map[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<double>(height));
          result->Success(flutter::EncodableValue(map));
        } else if (call.method_name() == "getDeviceName") {
          char computerName[MAX_COMPUTERNAME_LENGTH + 1];
          DWORD size = sizeof(computerName);
          if (GetComputerNameA(computerName, &size)) {
            result->Success(flutter::EncodableValue(std::string(computerName)));
          } else {
            result->Success(flutter::EncodableValue("Windows PC"));
          }
        } else if (call.method_name() == "simulateMouseMove") {
          if (args) {
            double dx = GetDoubleValue(*args, "dx", 0.0);
            double dy = GetDoubleValue(*args, "dy", 0.0);
            bool hasExplicitCoords = (args->find(flutter::EncodableValue("x")) != args->end());

            if (!hasExplicitCoords || dx != 0.0 || dy != 0.0) {
              POINT pt;
              GetCursorPos(&pt);
              g_accDx += dx;
              g_accDy += dy;
              int moveX = static_cast<int>(g_accDx);
              int moveY = static_cast<int>(g_accDy);
              g_accDx -= moveX;
              g_accDy -= moveY;

              if (moveX != 0 || moveY != 0) {
                int minX = GetSystemMetrics(SM_XVIRTUALSCREEN);
                int minY = GetSystemMetrics(SM_YVIRTUALSCREEN);
                int maxX = minX + GetSystemMetrics(SM_CXVIRTUALSCREEN) - 1;
                int maxY = minY + GetSystemMetrics(SM_CYVIRTUALSCREEN) - 1;
                int targetX = (std::max)(minX, (std::min)(maxX, pt.x + moveX));
                int targetY = (std::max)(minY, (std::min)(maxY, pt.y + moveY));
                SetCursorPos(targetX, targetY);
              }
            } else {
              double x = GetDoubleValue(*args, "x", -1.0);
              double y = GetDoubleValue(*args, "y", -1.0);
              if (x >= 0.0 && y >= 0.0) {
                SetCursorPos(static_cast<int>(x), static_cast<int>(y));
              }
            }
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "simulateMouseButton") {
          if (args) {
            int button = GetIntValue(*args, "button", 0);
            bool isDown = GetBoolValue(*args, "isDown", true);

            INPUT input = {0};
            input.type = INPUT_MOUSE;
            if (button == 0) {
              input.mi.dwFlags = isDown ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
            } else if (button == 1) {
              input.mi.dwFlags = isDown ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
            } else {
              input.mi.dwFlags = isDown ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
            }
            SendInput(1, &input, sizeof(INPUT));
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "simulateMouseScroll") {
          if (args) {
            double dx = GetDoubleValue(*args, "dx", 0.0);
            double dy = GetDoubleValue(*args, "dy", 0.0);
            if (dy != 0.0) {
              INPUT input = {0};
              input.type = INPUT_MOUSE;
              input.mi.dwFlags = MOUSEEVENTF_WHEEL;
              input.mi.mouseData = static_cast<DWORD>(static_cast<int>(-dy));
              SendInput(1, &input, sizeof(INPUT));
            }
            if (dx != 0.0) {
              INPUT input = {0};
              input.type = INPUT_MOUSE;
              input.mi.dwFlags = MOUSEEVENTF_HWHEEL;
              input.mi.mouseData = static_cast<DWORD>(static_cast<int>(dx));
              SendInput(1, &input, sizeof(INPUT));
            }
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "simulateKey") {
          if (args) {
            int windowsVk = GetIntValue(*args, "windowsVk", 0);
            if (windowsVk == 0) {
              windowsVk = GetIntValue(*args, "keyCode", 0);
            }
            bool isDown = GetBoolValue(*args, "isDown", true);
            std::string characters = GetStringValue(*args, "characters", "");

            if (windowsVk != 0) {
              INPUT input = {0};
              input.type = INPUT_KEYBOARD;
              input.ki.wVk = static_cast<WORD>(windowsVk);
              input.ki.wScan = static_cast<WORD>(MapVirtualKeyA(windowsVk, MAPVK_VK_TO_VSC));
              input.ki.dwFlags = isDown ? 0 : KEYEVENTF_KEYUP;

              if (windowsVk == VK_LEFT || windowsVk == VK_UP || windowsVk == VK_RIGHT || windowsVk == VK_DOWN ||
                  windowsVk == VK_HOME || windowsVk == VK_END || windowsVk == VK_PRIOR || windowsVk == VK_NEXT ||
                  windowsVk == VK_INSERT || windowsVk == VK_DELETE || windowsVk == VK_RCONTROL || windowsVk == VK_RMENU) {
                input.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
              }
              SendInput(1, &input, sizeof(INPUT));
            } else if (!characters.empty()) {
              INPUT input = {0};
              input.type = INPUT_KEYBOARD;
              input.ki.dwFlags = KEYEVENTF_UNICODE | (isDown ? 0 : KEYEVENTF_KEYUP);
              input.ki.wScan = static_cast<WCHAR>(static_cast<unsigned char>(characters[0]));
              SendInput(1, &input, sizeof(INPUT));
            }
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "confinePointer") {
          bool enable = false;
          if (args) {
            enable = GetBoolValue(*args, "enable", false);
          }
          HWND hwnd = flutter_controller_->view()->GetNativeWindow();
          if (hwnd) {
            if (enable) {
              RECT rect;
              GetClientRect(hwnd, &rect);
              InflateRect(&rect, -10, -10);
              MapWindowPoints(hwnd, NULL, (LPPOINT)&rect, 2);
              ClipCursor(&rect);
              SetCursorVisibility(false);
            } else {
              ClipCursor(NULL);
              SetCursorVisibility(true);
            }
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "warpPointer") {
          HWND hwnd = flutter_controller_->view()->GetNativeWindow();
          if (hwnd) {
            POINT pt;
            if (args && args->find(flutter::EncodableValue("x")) != args->end() &&
                        args->find(flutter::EncodableValue("y")) != args->end()) {
              double x = GetDoubleValue(*args, "x", 0.0);
              double y = GetDoubleValue(*args, "y", 0.0);
              pt.x = static_cast<LONG>(x);
              pt.y = static_cast<LONG>(y);
            } else {
              RECT rect;
              GetClientRect(hwnd, &rect);
              pt.x = (rect.left + rect.right) / 2;
              pt.y = (rect.top + rect.bottom) / 2;
            }
            ClientToScreen(hwnd, &pt);
            SetCursorPos(pt.x, pt.y);
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "setLocalInputInterception") {
          bool enable = false;
          if (args) {
            enable = GetBoolValue(*args, "enable", false);
          }
          g_isInputInterceptionActive = enable;
          if (enable && !g_keyboardHook) {
            g_keyboardHook = SetWindowsHookEx(
                WH_KEYBOARD_LL,
                LowLevelKeyboardProc,
                GetModuleHandle(NULL),
                0);
          } else if (!enable && g_keyboardHook) {
            UnhookWindowsHookEx(g_keyboardHook);
            g_keyboardHook = NULL;
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "setFullScreen") {
          bool enable = false;
          if (args) {
            enable = GetBoolValue(*args, "enable", false);
          }
          HWND hwnd = flutter_controller_->view()->GetNativeWindow();
          if (hwnd) {
            HWND parent = GetAncestor(hwnd, GA_ROOT);
            if (parent) hwnd = parent;
            if (enable) {
              ShowWindow(hwnd, SW_MAXIMIZE);
            } else {
              ShowWindow(hwnd, SW_RESTORE);
              ClipCursor(NULL);
              SetCursorVisibility(true);
            }
          }
          result->Success(flutter::EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (g_keyboardHook) {
    UnhookWindowsHookEx(g_keyboardHook);
    g_keyboardHook = NULL;
  }
  g_isInputInterceptionActive = false;
  ClipCursor(NULL);
  SetCursorVisibility(true);
  g_channel = nullptr;

  if (input_channel_) {
    input_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_KILLFOCUS:
      ClipCursor(NULL);
      SetCursorVisibility(true);
      break;
    case WM_ACTIVATE:
      if (LOWORD(wparam) == WA_INACTIVE) {
        ClipCursor(NULL);
        SetCursorVisibility(true);
      }
      break;
    case WM_SYSKEYDOWN:
    case WM_SYSKEYUP:
      if (g_isInputInterceptionActive && wparam == VK_SPACE) {
        return 0; // Prevent window system menu from opening during control
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
