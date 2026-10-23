#include "flutter_window.h"

#include <optional>
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

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
            auto dx_it = args->find(flutter::EncodableValue("dx"));
            auto dy_it = args->find(flutter::EncodableValue("dy"));
            double dx = (dx_it != args->end()) ? std::get<double>(dx_it->second) : 0.0;
            double dy = (dy_it != args->end()) ? std::get<double>(dy_it->second) : 0.0;
            SetCursorPos(pt.x + static_cast<int>(dx), pt.y + static_cast<int>(dy));
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "simulateMouseButton") {
          if (args) {
            auto btn_it = args->find(flutter::EncodableValue("button"));
            auto down_it = args->find(flutter::EncodableValue("isDown"));
            int button = (btn_it != args->end()) ? std::get<int>(btn_it->second) : 0;
            bool isDown = (down_it != args->end()) ? std::get<bool>(down_it->second) : true;

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
            auto dy_it = args->find(flutter::EncodableValue("dy"));
            double dy = (dy_it != args->end()) ? std::get<double>(dy_it->second) : 0.0;
            INPUT input = {0};
            input.type = INPUT_MOUSE;
            input.mi.dwFlags = MOUSEEVENTF_WHEEL;
            input.mi.mouseData = static_cast<DWORD>(dy * 120.0);
            SendInput(1, &input, sizeof(INPUT));
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "simulateKey") {
          if (args) {
            auto key_it = args->find(flutter::EncodableValue("keyCode"));
            auto down_it = args->find(flutter::EncodableValue("isDown"));
            int keyCode = (key_it != args->end()) ? std::get<int>(key_it->second) : 0;
            bool isDown = (down_it != args->end()) ? std::get<bool>(down_it->second) : true;

            INPUT input = {0};
            input.type = INPUT_KEYBOARD;
            input.ki.wVk = static_cast<WORD>(keyCode);
            if (!isDown) {
              input.ki.dwFlags = KEYEVENTF_KEYUP;
            }
            SendInput(1, &input, sizeof(INPUT));
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
