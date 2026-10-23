import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/control_events.dart';
import '../../services/native_input_service.dart';
import '../../services/network_service.dart';
import '../theme/app_colors.dart';
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.neonPurple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isMac ? Icons.laptop_mac_rounded : Icons.laptop_windows_rounded,
                    color: AppColors.neonPurple,
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
                          'Controlled by ${widget.request.deviceName}',
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
                            widget.request.fromKey,
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
                      'This laptop\'s display remains local. Keyboard & pointer inputs are being shared.',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),

                // Status pill
                StatusPill(
                  label: _isRemotePaused ? 'PAUSED BY CONTROLLER' : 'RECEIVING INPUT',
                  color: _isRemotePaused ? AppColors.amber : AppColors.emerald,
                  isPulsing: !_isRemotePaused,
                ),
                const SizedBox(width: 14),

                // Disconnect / Revoke button
                ElevatedButton.icon(
                  onPressed: () {
                    NetworkService().disconnect();
                    widget.onDisconnect();
                  },
                  icon: const Icon(Icons.stop_circle_rounded, size: 16, color: Colors.white),
                  label: const Text(
                    'Revoke Control',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.coral,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    children: [
                      // Accessibility Warning Banner if needed on macOS
                      if (Platform.isMacOS && !_hasAccessibility) ...[
                        _buildAccessibilityAlert(),
                        const SizedBox(height: 24),
                      ],

                      // Session Overview Card
                      GlassCard(
                        borderColor: AppColors.neonPurple.withOpacity(0.4),
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.neonPurple.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.cast_connected_rounded,
                                    color: AppColors.neonPurple,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ACTIVE CONTROL SESSION',
                                      style: TextStyle(
                                        color: AppColors.neonPurple,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${widget.request.deviceName} is sharing keyboard and mouse control',
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // 4 Stats Cards Grid
                            Row(
                              children: [
                                Expanded(child: _buildStatCard('Mouse Moves', '$_mouseMoveCount', Icons.mouse_rounded, AppColors.cyan)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildStatCard('Clicks', '$_clickCount', Icons.touch_app_rounded, AppColors.emerald)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildStatCard('Keystrokes', '$_keyCount', Icons.keyboard_rounded, AppColors.neonPurple)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildStatCard('Scrolls', '$_scrollCount', Icons.swap_vert_rounded, AppColors.amber)),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Real-time Event Feed
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.background.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.flash_on_rounded, size: 16, color: AppColors.cyan),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Live Event Stream:',
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
                                        fontSize: 13,
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
                      const SizedBox(height: 24),

                      // Information Card
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: AppColors.textSecondary, size: 20),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'You can take back mouse/keyboard control locally at any moment by moving your mouse or clicking "Revoke Control". The controller can also pause and resume using Command + Control + Q.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
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

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessibilityAlert() {
    return GlassCard(
      borderColor: AppColors.amber.withOpacity(0.6),
      backgroundColor: AppColors.amber.withOpacity(0.08),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 28),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'macOS Accessibility Permission Required',
                  style: TextStyle(
                    color: AppColors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'To allow CrossControl to simulate mouse and keyboard inputs globally on this Mac, enable CrossControl under System Settings > Privacy & Security > Accessibility.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: () async {
              await NativeInputService().requestAccessibilityPermission();
              await NativeInputService().openAccessibilitySettings();
              await Future.delayed(const Duration(seconds: 1));
              _checkAccessibility();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.amber,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Enable Permission',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
