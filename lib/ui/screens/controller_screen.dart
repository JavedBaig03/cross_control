import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/control_events.dart';
import '../../models/peer_info.dart';
import '../../services/key_mapping_service.dart';
import '../../services/network_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/status_pill.dart';

class ControllerScreen extends StatefulWidget {
  final PeerInfo peer;
  final VoidCallback onDisconnect;

  const ControllerScreen({
    super.key,
    required this.peer,
    required this.onDisconnect,
  });

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final FocusNode _focusNode = FocusNode();
  bool _isControlActive = true;
  double _sensitivity = 1.0;

  // Trackpad simulation visualizer coordinates
  double _localPointerX = 0.5;
  double _localPointerY = 0.5;
  bool _isPointerDown = false;
  String _lastKeyStroke = 'None';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
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
      NetworkService().sendEvent(ResumeEvent());
      _focusNode.requestFocus();
    } else {
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

    setState(() {
      _lastKeyStroke = '${event.logicalKey.keyLabel} (${isDown ? 'Down' : 'Up'})';
    });

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

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isControlActive) return;

    final dx = event.delta.dx * _sensitivity;
    final dy = event.delta.dy * _sensitivity;

    setState(() {
      _localPointerX = (_localPointerX + (dx / 500)).clamp(0.05, 0.95);
      _localPointerY = (_localPointerY + (dy / 500)).clamp(0.05, 0.95);
    });

    NetworkService().sendEvent(MouseMoveEvent(
      dx: dx,
      dy: dy,
    ));
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isControlActive) return;

    int button = 0; // left
    if (event.buttons == 2) button = 1; // right
    if (event.buttons == 4) button = 2; // middle

    setState(() => _isPointerDown = true);

    NetworkService().sendEvent(MouseButtonEvent(
      button: button,
      isDown: true,
    ));
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isControlActive) return;

    setState(() => _isPointerDown = false);

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
        child: Column(
          children: [
            // Top HUD Control Bar
            _buildTopBar(shortcutText),

            // Main Control Surface
            Expanded(
              child: Stack(
                children: [
                  // Interactive Pointer & Touch Capture Canvas
                  MouseRegion(
                    cursor: _isControlActive ? SystemMouseCursors.none : SystemMouseCursors.basic,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerMove: _handlePointerMove,
                      onPointerDown: _handlePointerDown,
                      onPointerUp: _handlePointerUp,
                      onPointerSignal: _handlePointerSignal,
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: _isControlActive
                            ? AppColors.surface.withOpacity(0.4)
                            : AppColors.background,
                        child: _buildControlSurfaceContent(shortcutText),
                      ),
                    ),
                  ),

                  // Overlay when control is paused
                  if (!_isControlActive)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.7),
                        child: Center(
                          child: _buildPausedCard(shortcutText),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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
          StatusPill(
            label: _isControlActive ? 'IN CONTROL' : 'PAUSED (LOCAL MODE)',
            color: _isControlActive ? AppColors.emerald : AppColors.amber,
            isPulsing: _isControlActive,
          ),
          const SizedBox(width: 16),

          // Pause / Resume Toggle Button
          ElevatedButton.icon(
            onPressed: _togglePauseControl,
            icon: Icon(
              _isControlActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 16,
              color: Colors.white,
            ),
            label: Text(
              _isControlActive ? 'Pause ($shortcutText)' : 'Resume ($shortcutText)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isControlActive ? AppColors.amber.withOpacity(0.8) : AppColors.emerald,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 12),

          // Disconnect Button
          OutlinedButton.icon(
            onPressed: () {
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

  Widget _buildControlSurfaceContent(String shortcutText) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 820),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active Control Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.touch_app_rounded, color: AppColors.cyan, size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REMOTE CONTROL ACTIVE',
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Move mouse or type anywhere in this window to control ${widget.peer.name}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Simulated Trackpad & Visual Feedback Canvas
            Expanded(
              child: GlassCard(
                borderColor: AppColors.cyan.withOpacity(0.4),
                backgroundColor: AppColors.surfaceElevated.withOpacity(0.7),
                padding: const EdgeInsets.all(24),
                child: Stack(
                  children: [
                    // Grid background lines
                    Positioned.fill(
                      child: CustomPaint(
                        painter: GridBackgroundPainter(),
                      ),
                    ),

                    // Center instruction
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.mouse_rounded,
                            size: 40,
                            color: AppColors.textMuted.withOpacity(0.4),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Pointer & Keyboard Capture Surface',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Press $shortcutText at any time to pause and restore local control',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Live Animated Pointer Reticle
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Positioned(
                          left: constraints.maxWidth * _localPointerX - 16,
                          top: constraints.maxHeight * _localPointerY - 16,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 40),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isPointerDown
                                  ? AppColors.emerald.withOpacity(0.6)
                                  : AppColors.cyan.withOpacity(0.35),
                              border: Border.all(
                                color: _isPointerDown ? AppColors.emerald : AppColors.cyan,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isPointerDown ? AppColors.emerald : AppColors.cyan)
                                      .withOpacity(0.5),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.near_me_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Last Keystroke visualizer in bottom left
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.background.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.keyboard_rounded, size: 14, color: AppColors.cyan),
                            const SizedBox(width: 8),
                            Text(
                              'Key: $_lastKeyStroke',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontFamily: 'Courier',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Sensitivity Slider in bottom right
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: Row(
                        children: [
                          const Icon(Icons.speed_rounded, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          const Text(
                            'Sensitivity',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          SizedBox(
                            width: 120,
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
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPausedCard(String shortcutText) {
    return GlassCard(
      borderColor: AppColors.amber.withOpacity(0.5),
      backgroundColor: AppColors.surfaceElevated.withOpacity(0.95),
      padding: const EdgeInsets.all(32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
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
              child: const Icon(Icons.pause_circle_rounded, color: AppColors.amber, size: 40),
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _togglePauseControl,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Resume Control ($shortcutText)',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border.withOpacity(0.3)
      ..strokeWidth = 1.0;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
