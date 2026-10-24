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
import '../widgets/device_avatar.dart';
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

  final Set<int> _downButtons = {};
  bool _isWarpPending = false;
  Offset? _warpTarget;
  int _lastWarpTimeMs = 0;

  @override
  void initState() {
    super.initState();

    // Enter full screen, confine pointer, and activate native input interception
    NativeInputService().setFullScreen(true);
    NativeInputService().confinePointer(true);
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
      _recenterPointer();
    });
  }

  @override
  void dispose() {
    NativeInputService().onInterceptedKey = null;
    NativeInputService().confinePointer(false);
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

  void _recenterPointer([Offset? targetCenter]) {
    if (!mounted) return;
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final Size size = renderBox?.hasSize == true
        ? renderBox!.size
        : MediaQuery.maybeOf(context)?.size ?? const Size(1920, 1080);
    final center = targetCenter ?? Offset(size.width / 2, size.height / 2);

    _isWarpPending = true;
    _warpTarget = center;
    _lastWarpTimeMs = DateTime.now().millisecondsSinceEpoch;

    NativeInputService().warpPointer(center.dx, center.dy);
  }

  void _togglePauseControl() {
    setState(() {
      _isControlActive = !_isControlActive;
    });

    if (_isControlActive) {
      NativeInputService().setFullScreen(true);
      NativeInputService().confinePointer(true);
      NativeInputService().setLocalInputInterception(true);
      NetworkService().sendEvent(ResumeEvent());
      _focusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recenterPointer();
      });
    } else {
      NativeInputService().confinePointer(false);
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

  /// Unified pointer movement handler for pure relative movement and edge recentering
  void _handlePointerMovement(PointerEvent event) {
    if (!_isControlActive) return;

    // Discard synthetic repositioning event generated by warp
    if (_isWarpPending) {
      // The synthetic warp event repositions the cursor across a large delta to recenter it.
      // Intercept and consume it immediately so it is never treated as genuine user input.
      if (event.delta.distance > 20 ||
          (_warpTarget != null && (event.position - _warpTarget!).distance < 60)) {
        _isWarpPending = false;
        return;
      }

      // Safety timeout: if warp took more than 200ms, clear the pending flag
      if (DateTime.now().millisecondsSinceEpoch - _lastWarpTimeMs > 200) {
        _isWarpPending = false;
      }
    }

    // Critical anomaly guard: Real physical mouse/trackpad motion never generates > 80px in a single frame.
    // Any delta > 80px is a synthetic warp, OS recenter, or window boundary jump.
    if (event.delta.distance > 80) {
      _isWarpPending = false;
      return;
    }

    final dx = event.delta.dx * _sensitivity;
    final dy = event.delta.dy * _sensitivity;

    if (dx != 0.0 || dy != 0.0) {
      // Stream pure relative deltas without clamping to local screen limits!
      NetworkService().sendEvent(MouseMoveEvent(
        dx: dx,
        dy: dy,
      ));
    }

    // Only recenter when pointer actually approaches physical screen boundaries (edges)
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final size = renderBox.size;
      const double edgeMargin = 40.0;
      final bool isNearEdge = event.position.dx < edgeMargin ||
          event.position.dx > size.width - edgeMargin ||
          event.position.dy < edgeMargin ||
          event.position.dy > size.height - edgeMargin;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (isNearEdge && !_isWarpPending && (now - _lastWarpTimeMs > 200)) {
        final center = Offset(size.width / 2, size.height / 2);
        _recenterPointer(center);
      }
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isControlActive) return;

    int button = 0; // left
    if (event.buttons & kSecondaryMouseButton != 0) {
      button = 1; // right
    } else if (event.buttons & kMiddleMouseButton != 0) {
      button = 2; // middle
    }
    _downButtons.add(button);

    NetworkService().sendEvent(MouseButtonEvent(
      button: button,
      isDown: true,
    ));
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isControlActive) return;

    if (_downButtons.isEmpty) {
      NetworkService().sendEvent(MouseButtonEvent(
        button: 0,
        isDown: false,
      ));
    } else {
      for (final btn in _downButtons.toList()) {
        NetworkService().sendEvent(MouseButtonEvent(
          button: btn,
          isDown: false,
        ));
      }
      _downButtons.clear();
    }
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

              // Small unobtrusive floating shortcut pill at the top (IgnorePointer ensures 100% mouse transparency)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.emerald,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Controlling ${widget.peer.name}  •  Press $shortcutText to pause',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
      ),
      child: Row(
        children: [
          // Left: Remote laptop info
          Row(
            children: [
              DeviceAvatar(
                size: 32,
                isMac: widget.peer.os.contains('mac'),
                showPlatformBadge: true,
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          widget.peer.key,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
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
                    'Direct Stream • ${widget.peer.ip}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
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
          const SizedBox(width: 8),

          ValueListenableBuilder<int>(
            valueListenable: NetworkService().eventsSentNotifier,
            builder: (context, sent, _) {
              return StatusPill(
                label: '$sent events',
                color: AppColors.textSecondary,
                icon: Icons.sync_alt_rounded,
                isPulsing: false,
              );
            },
          ),
          const SizedBox(width: 8),

          // Control state pill
          const StatusPill(
            label: 'PAUSED',
            color: AppColors.amber,
            isPulsing: false,
          ),
          const SizedBox(width: 14),

          // Resume Button
          ElevatedButton.icon(
            onPressed: _togglePauseControl,
            icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
            label: Text(
              'Resume ($shortcutText)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 8),

          // Disconnect Button
          OutlinedButton(
            onPressed: () {
              NativeInputService().setFullScreen(false);
              NativeInputService().setLocalInputInterception(false);
              NetworkService().disconnect();
              widget.onDisconnect();
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.borderStrong),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text(
              'Disconnect',
              style: TextStyle(color: AppColors.coral, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPausedCard(String shortcutText) {
    return GlassCard(
      borderRadius: 4,
      borderColor: AppColors.borderStrong,
      backgroundColor: AppColors.surface,
      padding: const EdgeInsets.all(28),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.amberLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.amber.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.pause_rounded, color: AppColors.amber, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remote Control Paused',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Local input restored to this machine',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Your keyboard and pointer inputs are operating locally. Press $shortcutText to resume remote control.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),

            // Sensitivity setting while paused
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Text(
                    'Pointer Speed:',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      value: _sensitivity,
                      min: 0.5,
                      max: 2.5,
                      divisions: 8,
                      activeColor: AppColors.primary,
                      inactiveColor: AppColors.borderStrong,
                      onChanged: (val) {
                        setState(() => _sensitivity = val);
                      },
                    ),
                  ),
                  Text(
                    '${_sensitivity.toStringAsFixed(1)}x',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () {
                    NativeInputService().setFullScreen(false);
                    NativeInputService().setLocalInputInterception(false);
                    NetworkService().disconnect();
                    widget.onDisconnect();
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.borderStrong),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text(
                    'Disconnect',
                    style: TextStyle(color: AppColors.coral, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _togglePauseControl,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                  label: Text(
                    'Resume ($shortcutText)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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
