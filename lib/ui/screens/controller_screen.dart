import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/control_events.dart';
import '../../models/peer_info.dart';
import '../../services/key_mapping_service.dart';
import '../../services/native_input_service.dart';
import '../../services/network_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/status_pill.dart';

class ControllerScreen extends StatefulWidget {
  final PeerInfo peer;
  final double targetScreenWidth;
  final double targetScreenHeight;
  final VoidCallback onDisconnect;

  const ControllerScreen({
    super.key,
    required this.peer,
    this.targetScreenWidth = 1920.0,
    this.targetScreenHeight = 1080.0,
    required this.onDisconnect,
  });

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final FocusNode _focusNode = FocusNode();
  bool _isControlActive = true;
  double _sensitivity = 1.0;

  // Remote cursor position mapped to the receiver's screen resolution
  late double _remoteCursorX;
  late double _remoteCursorY;

  @override
  void initState() {
    super.initState();
    _remoteCursorX = widget.targetScreenWidth / 2;
    _remoteCursorY = widget.targetScreenHeight / 2;

    // Enter full screen and activate native input interception
    NativeInputService().setFullScreen(true);
    NativeInputService().setLocalInputInterception(true);

    NativeInputService().onInterceptedKey = ({
      required int vk,
      required bool isDown,
      required bool isWinKey,
      required bool alt,
    }) {
      if (!_isControlActive) return;

      if (isWinKey) {
        // Map Windows key directly to macOS Command key (Carbon code 55)
        NetworkService().sendEvent(KeyEventData(
          keyCode: 0x5B,
          windowsVk: 0x5B,
          macosVk: 55, // kVK_Command
          label: 'Meta',
          isDown: isDown,
          meta: isDown,
        ));
      } else if (alt && vk == 0x20) {
        // Alt + Space (Option + Space on Mac)
        NetworkService().sendEvent(KeyEventData(
          keyCode: 0x20,
          windowsVk: 0x20,
          macosVk: 49, // kVK_Space
          label: 'Space',
          isDown: isDown,
          alt: true,
        ));
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    NativeInputService().onInterceptedKey = null;
    NativeInputService().setFullScreen(false);
    NativeInputService().setLocalInputInterception(false);
    _focusNode.dispose();
    super.dispose();
  }

  /// Check for Control + Option + P (macOS) or Ctrl + Alt + P (Windows)
  bool _isPauseResumeShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isP = event.logicalKey == LogicalKeyboardKey.keyP;

    return isCtrl && isAlt && isP;
  }

  void _togglePauseControl() {
    setState(() {
      _isControlActive = !_isControlActive;
    });

    if (_isControlActive) {
      NativeInputService().setFullScreen(true);
      NativeInputService().setLocalInputInterception(true);
      NetworkService().sendEvent(ResumeEvent());
      _focusNode.requestFocus();
    } else {
      NativeInputService().setFullScreen(false);
      NativeInputService().setLocalInputInterception(false);
      NetworkService().sendEvent(PauseEvent(isPaused: true));
    }
  }

  KeyEventResult _onFocusKeyEvent(FocusNode node, KeyEvent event) {
    // Intercept pause/resume shortcut first
    if (_isPauseResumeShortcut(event)) {
      _togglePauseControl();
      return KeyEventResult.handled;
    }

    // If control is paused, allow local OS/apps to process keys normally
    if (!_isControlActive) {
      return KeyEventResult.ignored;
    }

    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final codes = KeyMappingService().resolveNativeCodes(event);

    final keyData = KeyEventData(
      keyCode: codes.windowsVk,
      windowsVk: codes.windowsVk,
      macosVk: codes.macosVk,
      character: event.character,
      label: event.logicalKey.keyLabel,
      isDown: isDown,
      meta: HardwareKeyboard.instance.isMetaPressed,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );

    NetworkService().sendEvent(keyData);

    // CRITICAL: Consume the event so the local laptop does not trigger local actions/typing
    return KeyEventResult.handled;
  }

  /// Unified pointer movement handler for both hover and drag movements across built-in trackpads and external mice
  void _handlePointerMovement(PointerEvent event) {
    if (!_isControlActive) return;

    final dx = event.delta.dx * _sensitivity;
    final dy = event.delta.dy * _sensitivity;

    if (dx == 0.0 && dy == 0.0) return;

    _remoteCursorX = (_remoteCursorX + dx).clamp(0.0, widget.targetScreenWidth - 1);
    _remoteCursorY = (_remoteCursorY + dy).clamp(0.0, widget.targetScreenHeight - 1);

    NetworkService().sendEvent(MouseMoveEvent(
      dx: dx,
      dy: dy,
      x: _remoteCursorX,
      y: _remoteCursorY,
    ));
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isControlActive) return;

    int button = 0; // left
    if (event.buttons == 2) button = 1; // right
    if (event.buttons == 4) button = 2; // middle

    NetworkService().sendEvent(MouseButtonEvent(
      button: button,
      isDown: true,
    ));
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isControlActive) return;

    NetworkService().sendEvent(MouseButtonEvent(
      button: 0,
      isDown: false,
    ));
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_isControlActive) return;

    if (event is PointerScrollEvent) {
      NetworkService().sendEvent(MouseScrollEvent(
        dx: event.scrollDelta.dx,
        dy: event.scrollDelta.dy,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortcutText = StorageService().shortcutLabel;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        canRequestFocus: true,
        descendantsAreFocusable: false,
        descendantsAreTraversable: false,
        onKeyEvent: _onFocusKeyEvent,
        child: _isControlActive
            ? _buildFullScreenControlSurface(shortcutText)
            : _buildPausedInterface(shortcutText),
      ),
    );
  }

  /// Full-Screen Remote Control Interface: No buttons, no menus, completely unobstructed surface
  Widget _buildFullScreenControlSurface(String shortcutText) {
    return MouseRegion(
      cursor: SystemMouseCursors.none,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerHover: _handlePointerMovement,
        onPointerMove: _handlePointerMovement,
        onPointerDown: _handlePointerDown,
        onPointerUp: _handlePointerUp,
        onPointerSignal: _handlePointerSignal,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF070A10),
          child: Stack(
            children: [
              // Subtle ambient glow in center
              Center(
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.cyan.withOpacity(0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Small unobtrusive floating shortcut pill at the top
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101622).withOpacity(0.85),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.emerald,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Controlling ${widget.peer.name}  •  Press $shortcutText to pause',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Paused Interface: Normal UI revealed with all stats and control buttons
  Widget _buildPausedInterface(String shortcutText) {
    return Column(
      children: [
        // Top HUD Bar
        _buildTopBar(shortcutText),

        // Main Paused Card View
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: _buildPausedCard(shortcutText),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(String shortcutText) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          // Left: Remote laptop info
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.peer.os.contains('mac')
                      ? Icons.laptop_mac_rounded
                      : Icons.laptop_windows_rounded,
                  color: AppColors.cyan,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.peer.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          widget.peer.key,
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Direct Control Stream (${widget.peer.ip})',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const Spacer(),

          // Status & Stats Pills
          ValueListenableBuilder<int>(
            valueListenable: NetworkService().latencyMsNotifier,
            builder: (context, latency, _) {
              return StatusPill(
                label: '$latency ms',
                color: latency < 15 ? AppColors.emerald : AppColors.amber,
                icon: Icons.speed_rounded,
                isPulsing: false,
              );
            },
          ),
          const SizedBox(width: 10),

          ValueListenableBuilder<int>(
            valueListenable: NetworkService().eventsSentNotifier,
            builder: (context, sent, _) {
              return StatusPill(
                label: '$sent events',
                color: AppColors.cyan,
                icon: Icons.sync_alt_rounded,
                isPulsing: false,
              );
            },
          ),
          const SizedBox(width: 10),

          // Control state pill
          const StatusPill(
            label: 'PAUSED (LOCAL MODE)',
            color: AppColors.amber,
            isPulsing: false,
          ),
          const SizedBox(width: 16),

          // Resume Button
          ElevatedButton.icon(
            onPressed: _togglePauseControl,
            icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.black),
            label: Text(
              'Resume ($shortcutText)',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 12),

          // Disconnect Button
          OutlinedButton.icon(
            onPressed: () {
              NativeInputService().setFullScreen(false);
              NativeInputService().setLocalInputInterception(false);
              NetworkService().disconnect();
              widget.onDisconnect();
            },
            icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.coral),
            label: const Text(
              'Disconnect',
              style: TextStyle(color: AppColors.coral, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.coral.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPausedCard(String shortcutText) {
    return GlassCard(
      borderColor: AppColors.amber.withOpacity(0.5),
      backgroundColor: AppColors.surfaceElevated.withOpacity(0.95),
      padding: const EdgeInsets.all(36),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.amber.withOpacity(0.4)),
              ),
              child: const Icon(Icons.pause_circle_rounded, color: AppColors.amber, size: 44),
            ),
            const SizedBox(height: 20),
            const Text(
              'Remote Control Paused',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your keyboard, mouse, and trackpad have returned to normal local operation on this laptop.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Press $shortcutText to resume remote control at any time.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.cyan,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),

            // Sensitivity setting while paused
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.speed_rounded, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                const Text(
                  'Pointer Speed:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                SizedBox(
                  width: 140,
                  child: Slider(
                    value: _sensitivity,
                    min: 0.5,
                    max: 2.5,
                    divisions: 8,
                    activeColor: AppColors.cyan,
                    inactiveColor: AppColors.border,
                    onChanged: (val) {
                      setState(() => _sensitivity = val);
                    },
                  ),
                ),
                Text(
                  '${_sensitivity.toStringAsFixed(1)}x',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _togglePauseControl,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                  label: Text(
                    'Resume Control ($shortcutText)',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    NativeInputService().setFullScreen(false);
                    NativeInputService().setLocalInputInterception(false);
                    NetworkService().disconnect();
                    widget.onDisconnect();
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.coral.withOpacity(0.6)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'Disconnect',
                    style: TextStyle(color: AppColors.coral, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
