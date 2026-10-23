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

  input_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
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
            POINT pt;
            GetCursorPos(&pt);
            double dx = GetDoubleValue(*args, "dx", 0.0);
            double dy = GetDoubleValue(*args, "dy", 0.0);
            SetCursorPos(pt.x + static_cast<int>(dx), pt.y + static_cast<int>(dy));
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
            double dy = GetDoubleValue(*args, "dy", 0.0);
            INPUT input = {0};
            input.type = INPUT_MOUSE;
            input.mi.dwFlags = MOUSEEVENTF_WHEEL;
            input.mi.mouseData = static_cast<DWORD>(dy * 120.0);
            SendInput(1, &input, sizeof(INPUT));
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
