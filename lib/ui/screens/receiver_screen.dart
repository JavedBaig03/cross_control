import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/connection_state.dart';
import '../../models/control_events.dart';
import '../../services/native_input_service.dart';
import '../../services/network_service.dart';
import '../theme/app_colors.dart';
import '../widgets/device_avatar.dart';
import '../widgets/glass_card.dart';
import '../widgets/status_pill.dart';

class ReceiverScreen extends StatefulWidget {
  final ConnectionRequest request;
  final VoidCallback onDisconnect;

  const ReceiverScreen({
    super.key,
    required this.request,
    required this.onDisconnect,
  });

  @override
  State<ReceiverScreen> createState() => ReceiverScreenState();
}

class ReceiverScreenState extends State<ReceiverScreen> {
  bool _isRemotePaused = false;
  int _mouseMoveCount = 0;
  int _clickCount = 0;
  int _keyCount = 0;
  int _scrollCount = 0;
  String _lastEventDescription = 'Waiting for input...';
  bool _hasAccessibility = true;

  @override
  void initState() {
    super.initState();
    _checkAccessibility();
  }

  Future<void> _checkAccessibility() async {
    final hasPerm = await NativeInputService().checkAccessibilityPermission();
    if (mounted) {
      setState(() => _hasAccessibility = hasPerm);
    }
  }

  Timer? _uiThrottleTimer;
  bool _uiNeedsUpdate = false;

  void _scheduleUiUpdate() {
    _uiNeedsUpdate = true;
    if (_uiThrottleTimer == null || !_uiThrottleTimer!.isActive) {
      _uiThrottleTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted && _uiNeedsUpdate) {
          setState(() {
            _uiNeedsUpdate = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _uiThrottleTimer?.cancel();
    NativeInputService().simulateMouseButton(button: 0, isDown: false);
    NativeInputService().simulateMouseButton(button: 1, isDown: false);
    NativeInputService().resetRemoteCursor();
    super.dispose();
  }

  /// Called whenever a ControlEvent is received from the network
  void handleIncomingEvent(ControlEvent event) {
    if (event is PauseEvent) {
      _isRemotePaused = event.isPaused;
      _lastEventDescription = event.isPaused ? 'Remote control paused' : 'Remote control resumed';
      if (event.isPaused) {
        NativeInputService().simulateMouseButton(button: 0, isDown: false);
        NativeInputService().simulateMouseButton(button: 1, isDown: false);
      }
      setState(() {});
      return;
    }

    if (event is ResumeEvent) {
      _isRemotePaused = false;
      _lastEventDescription = 'Remote control resumed';
      setState(() {});
      return;
    }

    if (_isRemotePaused) return;

    // If the agreed session mode is View Only, strictly ignore any remote keyboard/mouse inputs
    if (!widget.request.mode.allowsControl) {
      if (event is MouseMoveEvent ||
          event is MouseButtonEvent ||
          event is MouseScrollEvent ||
          event is KeyEventData) {
        _lastEventDescription = 'Input ignored: Session in View Only mode';
        _scheduleUiUpdate();
        return;
      }
    }

    if (event is MouseMoveEvent) {
      // 1. Simulate mouse movement IMMEDIATELY with zero UI thread overhead
      NativeInputService().simulateMouseMove(
        dx: event.dx,
        dy: event.dy,
        x: event.x,
        y: event.y,
      );
      // 2. Schedule throttled UI counter update
      _mouseMoveCount++;
      _lastEventDescription = 'Mouse delta: (${event.dx.toStringAsFixed(1)}, ${event.dy.toStringAsFixed(1)})';
      _scheduleUiUpdate();
    } else if (event is MouseButtonEvent) {
      NativeInputService().simulateMouseButton(
        button: event.button,
        isDown: event.isDown,
      );
      _clickCount++;
      _lastEventDescription = 'Button ${event.button == 0 ? "Left" : (event.button == 1 ? "Right" : "Middle")} ${event.isDown ? "Down" : "Up"}';
      _scheduleUiUpdate();
    } else if (event is MouseScrollEvent) {
      NativeInputService().simulateMouseScroll(
        dx: event.dx,
        dy: event.dy,
      );
      _scrollCount++;
      _lastEventDescription = 'Scroll (${event.dx.toStringAsFixed(0)}, ${event.dy.toStringAsFixed(0)})';
      _scheduleUiUpdate();
    } else if (event is KeyEventData) {
      NativeInputService().simulateKey(
        keyCode: event.keyCode,
        windowsVk: event.windowsVk,
        macosVk: event.macosVk,
        isDown: event.isDown,
        characters: event.character ?? (event.label.length == 1 ? event.label : null),
        meta: event.meta,
        ctrl: event.ctrl,
        alt: event.alt,
        shift: event.shift,
      );
      _keyCount++;
      _lastEventDescription = 'Key: "${event.label}" ${event.isDown ? "Down" : "Up"}';
      _scheduleUiUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMac = widget.request.platform.toLowerCase().contains('mac');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Top HUD
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
            ),
            child: Row(
              children: [
                DeviceAvatar(
                  size: 32,
                  isMac: isMac,
                  showPlatformBadge: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.request.mode == SessionMode.viewOnly
                                  ? 'Viewed by ${widget.request.deviceName}'
                                  : 'Controlled by ${widget.request.deviceName}',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
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
                              widget.request.fromKey,
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
                        widget.request.mode == SessionMode.viewOnly
                            ? 'View Only mode • Remote keyboard and pointer control are disabled'
                            : (widget.request.mode == SessionMode.viewAndControl
                                ? 'View & Control mode • Remote screen viewing and input control'
                                : 'Control Only mode • Keyboard and pointer inputs are shared'),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Mode pill
                StatusPill(
                  label: widget.request.mode.label.toUpperCase(),
                  color: widget.request.mode == SessionMode.viewOnly
                      ? AppColors.cyan
                      : (widget.request.mode == SessionMode.viewAndControl
                          ? AppColors.emerald
                          : AppColors.primary),
                  isPulsing: false,
                ),
                const SizedBox(width: 8),

                // Status pill
                StatusPill(
                  label: _isRemotePaused
                      ? 'PAUSED'
                      : (widget.request.mode == SessionMode.viewOnly
                          ? 'STREAMING SCREEN'
                          : (widget.request.mode == SessionMode.viewAndControl
                              ? 'STREAMING & INPUT'
                              : 'RECEIVING INPUT')),
                  color: _isRemotePaused
                      ? AppColors.amber
                      : (widget.request.mode == SessionMode.viewOnly ? AppColors.cyan : AppColors.emerald),
                  isPulsing: !_isRemotePaused,
                ),
                const SizedBox(width: 12),

                // Revoke button
                OutlinedButton(
                  onPressed: () {
                    NetworkService().disconnect();
                    widget.onDisconnect();
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.borderStrong),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text(
                    'Revoke Control',
                    style: TextStyle(color: AppColors.coral, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    children: [
                      // Accessibility Warning Banner if needed on macOS
                      if (Platform.isMacOS && !_hasAccessibility) ...[
                        _buildAccessibilityAlert(),
                        const SizedBox(height: 18),
                      ],

                      // Session Overview Card
                      GlassCard(
                        borderRadius: 4,
                        borderColor: AppColors.borderStrong,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.desktop_windows_outlined,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Active Control Session',
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${widget.request.deviceName} is forwarding input over local network',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // 4 Stats Cards Grid
                            Row(
                              children: [
                                Expanded(child: _buildStatCard('Mouse Moves', '$_mouseMoveCount', Icons.mouse_rounded)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildStatCard('Clicks', '$_clickCount', Icons.touch_app_rounded)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildStatCard('Keystrokes', '$_keyCount', Icons.keyboard_rounded)),
                                const SizedBox(width: 10),
                                Expanded(child: _buildStatCard('Scrolls', '$_scrollCount', Icons.swap_vert_rounded)),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // Real-time Event Feed
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  const Text(
                                    'Live Event:',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _lastEventDescription,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 12,
                                        fontFamily: 'Courier',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Information Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: AppColors.textMuted, size: 16),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'You can take back mouse and keyboard control at any moment by moving your mouse or clicking "Revoke Control".',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 14, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessibilityAlert() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberLight.withOpacity(0.35),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'macOS Accessibility Permission Required',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'To simulate pointer and keyboard inputs globally on this Mac, enable CrossControl under Accessibility settings.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () async {
              await NativeInputService().requestAccessibilityPermission();
              await NativeInputService().openAccessibilitySettings();
              await Future.delayed(const Duration(seconds: 1));
              _checkAccessibility();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              side: const BorderSide(color: AppColors.amber),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
