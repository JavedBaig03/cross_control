import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/connection_state.dart';
import '../../models/control_events.dart';
import '../../models/peer_info.dart';
import '../../services/key_mapping_service.dart';
import '../../services/native_input_service.dart';
import '../../services/network_service.dart';
import '../../services/screen_stream_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/device_avatar.dart';
import '../widgets/glass_card.dart';
import '../widgets/status_pill.dart';

class ControllerScreen extends StatefulWidget {
  final PeerInfo peer;
  final double targetScreenWidth;
  final double targetScreenHeight;
  final SessionMode mode;
  final VoidCallback onDisconnect;

  const ControllerScreen({
    super.key,
    required this.peer,
    this.targetScreenWidth = 1920.0,
    this.targetScreenHeight = 1080.0,
    this.mode = SessionMode.controlOnly,
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

  // Auto-hide Top Remote-Session Menu state (10s inactivity countdown)
  bool _isTopMenuVisible = true;
  Timer? _menuAutoHideTimer;
  bool _isMouseHoveringMenu = false;

  void _startMenuAutoHideTimer() {
    _menuAutoHideTimer?.cancel();
    _menuAutoHideTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_isTopMenuVisible && !_isMouseHoveringMenu) {
        setState(() {
          _isTopMenuVisible = false;
        });
      }
    });
  }

  void _onUserInteraction() {
    // Only resets 10-second timer when menu is already visible.
    // Prevents the menu from repeatedly flashing while typing/working.
    if (_isTopMenuVisible && !_isMouseHoveringMenu) {
      _startMenuAutoHideTimer();
    }
  }

  void _showTopMenu() {
    if (!_isTopMenuVisible) {
      setState(() {
        _isTopMenuVisible = true;
      });
    }
    _startMenuAutoHideTimer();
  }

  @override
  void initState() {
    super.initState();

    _startMenuAutoHideTimer();

    if (widget.mode.allowsView) {
      ScreenStreamService().connectToStream(
        host: widget.peer.ip,
        port: StorageService.tcpScreenPort,
      );
    }

    if (widget.mode.allowsControl) {
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
  }

  @override
  void dispose() {
    _menuAutoHideTimer?.cancel();
    if (widget.mode.allowsView) {
      ScreenStreamService().disconnectStream();
    }
    if (widget.mode.allowsControl) {
      NativeInputService().onInterceptedKey = null;
      NativeInputService().confinePointer(false);
      NativeInputService().setFullScreen(false);
      NativeInputService().setLocalInputInterception(false);
    }
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
    if (!widget.mode.allowsControl) return;

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
    _onUserInteraction();

    if (!widget.mode.allowsControl) {
      return KeyEventResult.ignored;
    }

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
    // Reveal top menu when pointer moves to the top edge of the window
    if (event.position.dy <= 20.0) {
      _showTopMenu();
    } else {
      _onUserInteraction();
    }

    if (!_isControlActive || !widget.mode.allowsControl) return;

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

    // Critical anomaly guard: Real physical mouse/trackpad motion never generates > 250px in a single frame.
    // Any delta > 250px is a synthetic warp, OS recenter, or window boundary jump.
    if (event.delta.distance > 250) {
      _isWarpPending = false;
      return;
    }

    final dx = event.delta.dx * _sensitivity;
    final dy = event.delta.dy * _sensitivity;

    double? remoteX;
    double? remoteY;
    if (widget.mode.allowsView) {
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final size = renderBox.size;
        final double srcWidth = ScreenStreamService().currentImageNotifier.value?.width.toDouble() ?? widget.targetScreenWidth;
        final double srcHeight = ScreenStreamService().currentImageNotifier.value?.height.toDouble() ?? widget.targetScreenHeight;

        final double scale = min(
          size.width / srcWidth,
          size.height / srcHeight,
        );
        if (scale > 0) {
          final double renderedWidth = srcWidth * scale;
          final double renderedHeight = srcHeight * scale;
          final double offsetX = (size.width - renderedWidth) / 2;
          final double offsetY = (size.height - renderedHeight) / 2;
          remoteX = ((event.position.dx - offsetX) / scale).clamp(0.0, widget.targetScreenWidth - 1.0);
          remoteY = ((event.position.dy - offsetY) / scale).clamp(0.0, widget.targetScreenHeight - 1.0);
        }
      }
    }

    if (dx != 0.0 || dy != 0.0 || remoteX != null) {
      // Stream relative deltas and absolute mapped coordinates
      NetworkService().sendEvent(MouseMoveEvent(
        dx: dx,
        dy: dy,
        x: remoteX,
        y: remoteY,
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
    _onUserInteraction();
    if (!_isControlActive || !widget.mode.allowsControl) return;

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
    _onUserInteraction();
    if (!_isControlActive || !widget.mode.allowsControl) return;

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
    _onUserInteraction();
    if (!_isControlActive || !widget.mode.allowsControl) return;

    if (event is PointerScrollEvent) {
      NetworkService().sendEvent(MouseScrollEvent(
        dx: event.scrollDelta.dx,
        dy: event.scrollDelta.dy,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == SessionMode.viewOnly) {
      return _buildViewOnlyInterface();
    }

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
              // Background: Live screen stream when view is allowed, or subtle ambient glow in control-only
              if (widget.mode.allowsView)
                Positioned.fill(
                  child: ValueListenableBuilder<ui.Image?>(
                    valueListenable: ScreenStreamService().currentImageNotifier,
                    builder: (context, uiImage, _) {
                      if (uiImage != null) {
                        return Center(
                          child: RawImage(
                            image: uiImage,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        );
                      }
                      return ValueListenableBuilder<Uint8List?>(
                        valueListenable: ScreenStreamService().currentFrameNotifier,
                        builder: (context, frameBytes, _) {
                          if (frameBytes != null && frameBytes.isNotEmpty) {
                            return Center(
                              child: Image.memory(
                                frameBytes,
                                gaplessPlayback: true,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                              ),
                            );
                          }
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.cyan),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Connecting to screen stream from ${widget.peer.name}...',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                )
              else
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

              // Top edge hover trigger strip to reveal menu when cursor moves to the top edge
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 20,
                child: MouseRegion(
                  onHover: (_) => _showTopMenu(),
                  onEnter: (_) => _showTopMenu(),
                  child: const SizedBox.expand(),
                ),
              ),

              // Top Remote-Session Menu Bar with 10s auto-hide and accessible controls
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  offset: _isTopMenuVisible ? Offset.zero : const Offset(0, -1.8),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: AnimatedOpacity(
                    opacity: _isTopMenuVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_isTopMenuVisible,
                      child: Center(
                        child: MouseRegion(
                          onEnter: (_) {
                            _isMouseHoveringMenu = true;
                            _menuAutoHideTimer?.cancel();
                          },
                          onExit: (_) {
                            _isMouseHoveringMenu = false;
                            _startMenuAutoHideTimer();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withOpacity(0.92),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF334155)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
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
                                  decoration: BoxDecoration(
                                    color: widget.mode == SessionMode.viewAndControl ? AppColors.cyan : AppColors.emerald,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.mode == SessionMode.viewAndControl
                                      ? 'Viewing & Controlling ${widget.peer.name}'
                                      : 'Controlling ${widget.peer.name}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (widget.mode.allowsView)
                                  ValueListenableBuilder<int>(
                                    valueListenable: ScreenStreamService().fpsNotifier,
                                    builder: (context, fps, _) {
                                      if (fps <= 0) return const SizedBox.shrink();
                                      return Text(
                                        '  •  $fps FPS',
                                        style: const TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w500),
                                      );
                                    },
                                  ),
                                ValueListenableBuilder<int>(
                                  valueListenable: NetworkService().latencyMsNotifier,
                                  builder: (context, latency, _) {
                                    return Text(
                                      '  •  $latency ms',
                                      style: TextStyle(
                                        color: latency < 20 ? AppColors.emerald : AppColors.amber,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  },
                                ),
                                Text(
                                  '  •  Press $shortcutText to pause',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                InkWell(
                                  onTap: () {
                                    NativeInputService().setFullScreen(false);
                                    NativeInputService().setLocalInputInterception(false);
                                    NetworkService().disconnect();
                                    widget.onDisconnect();
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.coral.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.coral.withOpacity(0.4)),
                                    ),
                                    child: const Text(
                                      'Disconnect',
                                      style: TextStyle(
                                        color: AppColors.coral,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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

          // Mode pill
          StatusPill(
            label: widget.mode.label.toUpperCase(),
            color: widget.mode == SessionMode.viewAndControl ? AppColors.emerald : AppColors.primary,
            icon: widget.mode == SessionMode.viewAndControl ? Icons.devices_outlined : Icons.mouse_outlined,
            isPulsing: false,
          ),
          const SizedBox(width: 8),

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

  /// Clean desktop interface displayed when session is connected in View Only mode
  Widget _buildViewOnlyInterface() {
    final isMac = widget.peer.os.contains('mac');
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (event) {
          if (event.position.dy <= 20.0) {
            _showTopMenu();
          } else {
            _onUserInteraction();
          }
        },
        child: Stack(
          children: [
            // Central live screen view
            Positioned.fill(
              child: Container(
                color: const Color(0xFF070A10),
                child: ValueListenableBuilder<ui.Image?>(
                  valueListenable: ScreenStreamService().currentImageNotifier,
                  builder: (context, uiImage, _) {
                    if (uiImage != null) {
                      return Stack(
                        children: [
                          Center(
                            child: RawImage(
                              image: uiImage,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                          _buildViewOnlyLockBadge(),
                        ],
                      );
                    }
                    return ValueListenableBuilder<Uint8List?>(
                      valueListenable: ScreenStreamService().currentFrameNotifier,
                      builder: (context, frameBytes, _) {
                        if (frameBytes != null && frameBytes.isNotEmpty) {
                          return Stack(
                            children: [
                              Center(
                                child: Image.memory(
                                  frameBytes,
                                  gaplessPlayback: true,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                ),
                              ),
                              _buildViewOnlyLockBadge(),
                            ],
                          );
                        }

                        return Center(
                          child: GlassCard(
                            borderRadius: 4,
                            borderColor: AppColors.borderStrong,
                            padding: const EdgeInsets.all(28),
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.cyan),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Connecting to ${widget.peer.name}...',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Establishing real-time screen stream over local network...',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  OutlinedButton(
                                    onPressed: () {
                                      NetworkService().disconnect();
                                      widget.onDisconnect();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: AppColors.borderStrong),
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    ),
                                    child: const Text(
                                      'Cancel Connection',
                                      style: TextStyle(color: AppColors.coral, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            // Top edge hover sensor strip
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 20,
              child: MouseRegion(
                onHover: (_) => _showTopMenu(),
                onEnter: (_) => _showTopMenu(),
                child: const SizedBox.expand(),
              ),
            ),

            // Top Bar with 10s auto-hide animation
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                offset: _isTopMenuVisible ? Offset.zero : const Offset(0, -1.0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: AnimatedOpacity(
                  opacity: _isTopMenuVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_isTopMenuVisible,
                    child: MouseRegion(
                      onEnter: (_) {
                        _isMouseHoveringMenu = true;
                        _menuAutoHideTimer?.cancel();
                      },
                      onExit: (_) {
                        _isMouseHoveringMenu = false;
                        _startMenuAutoHideTimer();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withOpacity(0.96),
                          border: const Border(bottom: BorderSide(color: AppColors.borderStrong)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            DeviceAvatar(
                              size: 32,
                              isMac: isMac,
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
                                  'Direct Connection • ${widget.peer.ip}',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),

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
                              valueListenable: ScreenStreamService().fpsNotifier,
                              builder: (context, fps, _) {
                                return StatusPill(
                                  label: '$fps FPS',
                                  color: fps > 0 ? AppColors.cyan : AppColors.textMuted,
                                  icon: Icons.videocam_outlined,
                                  isPulsing: false,
                                );
                              },
                            ),
                            const SizedBox(width: 8),

                            StatusPill(
                              label: '${widget.targetScreenWidth.toInt()}×${widget.targetScreenHeight.toInt()}',
                              color: AppColors.textMuted,
                              icon: Icons.aspect_ratio_rounded,
                              isPulsing: false,
                            ),
                            const SizedBox(width: 8),

                            const StatusPill(
                              label: 'VIEW ONLY',
                              color: AppColors.cyan,
                              icon: Icons.visibility_outlined,
                              isPulsing: false,
                            ),
                            const SizedBox(width: 14),

                            OutlinedButton.icon(
                              onPressed: () {
                                NetworkService().disconnect();
                                widget.onDisconnect();
                              },
                              icon: const Icon(Icons.close_rounded, size: 14, color: AppColors.coral),
                              label: const Text(
                                'Disconnect',
                                style: TextStyle(color: AppColors.coral, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.borderStrong),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewOnlyLockBadge() {
    return Positioned(
      bottom: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.85),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 12, color: AppColors.cyan),
            SizedBox(width: 6),
            Text(
              'Input Disabled (View Only)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
