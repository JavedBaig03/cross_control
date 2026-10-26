#include "flutter_window.h"

#include <optional>
#include <algorithm>
#include <windows.h>
#include <gdiplus.h>
#include <thread>
#include <atomic>
#include <vector>
#include <chrono>
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
static bool g_isPointerConfined = false;

// Windows desktop screen capture via GDI and GDI+
static ULONG_PTR g_gdiplusToken = 0;
static std::atomic<bool> g_isScreenCaptureRunning(false);
static std::thread g_screenCaptureThread;

static CLSID g_jpegClsid = { 0 };
static bool g_hasJpegClsid = false;

int GetEncoderClsid(const WCHAR* format, CLSID* pClsid) {
  if (g_hasJpegClsid && wcscmp(format, L"image/jpeg") == 0) {
    *pClsid = g_jpegClsid;
    return 0;
  }
  UINT num = 0;
  UINT size = 0;
  Gdiplus::GetImageEncodersSize(&num, &size);
  if (size == 0) return -1;
  auto* pImageCodecInfo = (Gdiplus::ImageCodecInfo*)(malloc(size));
  if (!pImageCodecInfo) return -1;
  Gdiplus::GetImageEncoders(num, size, pImageCodecInfo);
  for (UINT j = 0; j < num; ++j) {
    if (wcscmp(pImageCodecInfo[j].MimeType, format) == 0) {
      *pClsid = pImageCodecInfo[j].Clsid;
      if (wcscmp(format, L"image/jpeg") == 0) {
        g_jpegClsid = *pClsid;
        g_hasJpegClsid = true;
      }
      free(pImageCodecInfo);
      return j;
    }
  }
  free(pImageCodecInfo);
  return -1;
}

std::vector<uint8_t> CaptureDesktopJpeg(int targetWidth, int targetHeight, ULONG quality) {
  std::vector<uint8_t> resultBytes;

  int screenWidth = GetSystemMetrics(SM_CXSCREEN);
  int screenHeight = GetSystemMetrics(SM_CYSCREEN);
  if (screenWidth <= 0 || screenHeight <= 0) return resultBytes;

  // Preserve native aspect ratio up to 1080p
  int finalWidth = screenWidth;
  int finalHeight = screenHeight;

  if (targetWidth > 0 && targetHeight > 0) {
    finalWidth = targetWidth;
    finalHeight = targetHeight;
  } else if (screenWidth > 1920) {
    finalWidth = 1920;
    finalHeight = static_cast<int>((static_cast<double>(screenHeight) * 1920.0) / screenWidth);
  }

  HDC hScreenDC = GetDC(NULL);
  HDC hCaptureDC = CreateCompatibleDC(hScreenDC);
  HBITMAP hCaptureBitmap = CreateCompatibleBitmap(hScreenDC, screenWidth, screenHeight);
  HBITMAP hOldCaptureBitmap = (HBITMAP)SelectObject(hCaptureDC, hCaptureBitmap);

  BitBlt(hCaptureDC, 0, 0, screenWidth, screenHeight, hScreenDC, 0, 0, SRCCOPY | CAPTUREBLT);

  // Render hardware cursor into frame
  CURSORINFO cursorInfo = { 0 };
  cursorInfo.cbSize = sizeof(cursorInfo);
  if (GetCursorInfo(&cursorInfo) && cursorInfo.flags == CURSOR_SHOWING) {
    ICONINFO iconInfo = { 0 };
    if (GetIconInfo(cursorInfo.hCursor, &iconInfo)) {
      int x = cursorInfo.ptScreenPos.x - iconInfo.xHotspot;
      int y = cursorInfo.ptScreenPos.y - iconInfo.yHotspot;
      DrawIconEx(hCaptureDC, x, y, cursorInfo.hCursor, 0, 0, 0, NULL, DI_NORMAL);
      if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
      if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
    }
  }

  HBITMAP hFinalBitmap = hCaptureBitmap;
  HDC hScaledDC = NULL;
  HBITMAP hScaledBitmap = NULL;
  HBITMAP hOldScaledBitmap = NULL;

  if (finalWidth != screenWidth || finalHeight != screenHeight) {
    hScaledDC = CreateCompatibleDC(hScreenDC);
    hScaledBitmap = CreateCompatibleBitmap(hScreenDC, finalWidth, finalHeight);
    hOldScaledBitmap = (HBITMAP)SelectObject(hScaledDC, hScaledBitmap);

    SetStretchBltMode(hScaledDC, HALFTONE);
    SetBrushOrgEx(hScaledDC, 0, 0, NULL);
    StretchBlt(hScaledDC, 0, 0, finalWidth, finalHeight, hCaptureDC, 0, 0, screenWidth, screenHeight, SRCCOPY);
    hFinalBitmap = hScaledBitmap;
  }

  Gdiplus::Bitmap rawBitmap(hFinalBitmap, NULL);

  CLSID encoderClsid;
  if (GetEncoderClsid(L"image/jpeg", &encoderClsid) >= 0) {
    IStream* pStream = NULL;
    if (CreateStreamOnHGlobal(NULL, TRUE, &pStream) == S_OK) {
      Gdiplus::EncoderParameters encoderParameters;
      encoderParameters.Count = 1;
      encoderParameters.Parameter[0].Guid = Gdiplus::EncoderQuality;
      encoderParameters.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
      encoderParameters.Parameter[0].NumberOfValues = 1;
      encoderParameters.Parameter[0].Value = &quality;

      if (rawBitmap.Save(pStream, &encoderClsid, &encoderParameters) == Gdiplus::Ok) {
        STATSTG stat;
        if (pStream->Stat(&stat, STATFLAG_NONAME) == S_OK) {
          DWORD size = (DWORD)stat.cbSize.LowPart;
          resultBytes.resize(size);
          LARGE_INTEGER liZero = { 0 };
          pStream->Seek(liZero, STREAM_SEEK_SET, NULL);
          ULONG bytesRead = 0;
          pStream->Read(resultBytes.data(), size, &bytesRead);
        }
      }
      pStream->Release();
    }
  }

  if (hScaledDC) {
    SelectObject(hScaledDC, hOldScaledBitmap);
    DeleteObject(hScaledBitmap);
    DeleteDC(hScaledDC);
  }

  SelectObject(hCaptureDC, hOldCaptureBitmap);
  DeleteObject(hCaptureBitmap);
  DeleteDC(hCaptureDC);
  ReleaseDC(NULL, hScreenDC);

  return resultBytes;
}

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

  if (g_gdiplusToken == 0) {
    Gdiplus::GdiplusStartupInput gdiplusStartupInput;
    Gdiplus::GdiplusStartup(&g_gdiplusToken, &gdiplusStartupInput, NULL);
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
              g_accDx += dx;
              g_accDy += dy;
              int moveX = static_cast<int>(g_accDx);
              int moveY = static_cast<int>(g_accDy);
              g_accDx -= moveX;
              g_accDy -= moveY;

              if (moveX != 0 || moveY != 0) {
                INPUT input = {0};
                input.type = INPUT_MOUSE;
                input.mi.dwFlags = MOUSEEVENTF_MOVE;
                input.mi.dx = moveX;
                input.mi.dy = moveY;
                SendInput(1, &input, sizeof(INPUT));
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
        } else if (call.method_name() == "resetRemoteCursor") {
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "confinePointer") {
          bool enable = false;
          if (args) {
            enable = GetBoolValue(*args, "enable", false);
          }
          g_isPointerConfined = enable;
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
            double dpiScale = 1.0;
            HMODULE user32 = GetModuleHandleA("user32.dll");
            if (user32) {
              typedef UINT(WINAPI * GetDpiForWindowFn)(HWND);
              GetDpiForWindowFn getDpiForWindow =
                  reinterpret_cast<GetDpiForWindowFn>(GetProcAddress(user32, "GetDpiForWindow"));
              if (getDpiForWindow) {
                UINT dpi = getDpiForWindow(hwnd);
                if (dpi > 0) {
                  dpiScale = static_cast<double>(dpi) / 96.0;
                }
              }
            }

            if (args && args->find(flutter::EncodableValue("x")) != args->end() &&
                        args->find(flutter::EncodableValue("y")) != args->end()) {
              double x = GetDoubleValue(*args, "x", 0.0);
              double y = GetDoubleValue(*args, "y", 0.0);
              pt.x = static_cast<LONG>(x * dpiScale);
              pt.y = static_cast<LONG>(y * dpiScale);
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
        } else if (call.method_name() == "checkScreenCapturePermission") {
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "requestScreenCapturePermission") {
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "openScreenCaptureSettings") {
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "captureScreenFrame") {
          int width = args ? GetIntValue(*args, "width", 0) : 0;
          int height = args ? GetIntValue(*args, "height", 0) : 0;
          double qualityD = args ? GetDoubleValue(*args, "quality", 0.75) : 0.75;
          ULONG quality = static_cast<ULONG>(qualityD * 100.0);
          std::vector<uint8_t> jpeg = CaptureDesktopJpeg(width, height, quality);
          if (!jpeg.empty()) {
            result->Success(flutter::EncodableValue(jpeg));
          } else {
            result->Success();
          }
        } else if (call.method_name() == "startScreenCapture") {
          int fps = args ? GetIntValue(*args, "fps", 30) : 30;
          int width = args ? GetIntValue(*args, "width", 0) : 0;
          int height = args ? GetIntValue(*args, "height", 0) : 0;
          double qualityD = args ? GetDoubleValue(*args, "quality", 0.75) : 0.75;
          ULONG quality = static_cast<ULONG>(qualityD * 100.0);

          if (!g_isScreenCaptureRunning) {
            g_isScreenCaptureRunning = true;
            if (g_screenCaptureThread.joinable()) {
              g_screenCaptureThread.join();
            }
            g_screenCaptureThread = std::thread([fps, width, height, quality]() {
              int intervalMs = (std::max)(10, 1000 / (std::max)(1, fps));
              while (g_isScreenCaptureRunning) {
                auto start = std::chrono::steady_clock::now();
                std::vector<uint8_t> jpeg = CaptureDesktopJpeg(width, height, quality);
                if (!jpeg.empty() && g_channel) {
                  flutter::EncodableMap map;
                  map[flutter::EncodableValue("frame")] = flutter::EncodableValue(jpeg);
                  g_channel->InvokeMethod("onScreenFrame", std::make_unique<flutter::EncodableValue>(map));
                }
                auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - start).count();
                int sleepMs = intervalMs - static_cast<int>(elapsed);
                if (sleepMs > 0 && g_isScreenCaptureRunning) {
                  std::this_thread::sleep_for(std::chrono::milliseconds(sleepMs));
                }
              }
            });
          }
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "stopScreenCapture") {
          g_isScreenCaptureRunning = false;
          if (g_screenCaptureThread.joinable()) {
            g_screenCaptureThread.join();
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
  g_isPointerConfined = false;
  ClipCursor(NULL);
  SetCursorVisibility(true);
  g_channel = nullptr;

  if (input_channel_) {
    input_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  g_isScreenCaptureRunning = false;
  if (g_screenCaptureThread.joinable()) {
    g_screenCaptureThread.join();
  }
  if (g_gdiplusToken != 0) {
    Gdiplus::GdiplusShutdown(g_gdiplusToken);
    g_gdiplusToken = 0;
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
      } else if (g_isPointerConfined) {
        HWND childHwnd = flutter_controller_ && flutter_controller_->view() ? flutter_controller_->view()->GetNativeWindow() : hwnd;
        RECT rect;
        GetClientRect(childHwnd, &rect);
        InflateRect(&rect, -10, -10);
        MapWindowPoints(childHwnd, NULL, (LPPOINT)&rect, 2);
        ClipCursor(&rect);
        SetCursorVisibility(false);
      }
      break;
    case WM_SIZE:
      if (g_isPointerConfined) {
        HWND childHwnd = flutter_controller_ && flutter_controller_->view() ? flutter_controller_->view()->GetNativeWindow() : hwnd;
        RECT rect;
        GetClientRect(childHwnd, &rect);
        InflateRect(&rect, -10, -10);
        MapWindowPoints(childHwnd, NULL, (LPPOINT)&rect, 2);
        ClipCursor(&rect);
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
