import 'package:flutter/material.dart';
import '../../models/control_events.dart';
import '../theme/app_colors.dart';
import 'glass_card.dart';

class ConnectionRequestDialog extends StatelessWidget {
  final ConnectionRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const ConnectionRequestDialog({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isMac = request.platform.toLowerCase().contains('mac');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassCard(
          borderColor: AppColors.cyan.withOpacity(0.5),
          backgroundColor: AppColors.surfaceElevated.withOpacity(0.96),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                    ),
                    child: const Icon(
                      Icons.settings_remote_rounded,
                      color: AppColors.cyan,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'INCOMING CONTROL REQUEST',
                          style: TextStyle(
                            color: AppColors.cyan,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Device Wants Control',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              // Device Details Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      icon: isMac ? Icons.laptop_mac_rounded : Icons.laptop_windows_rounded,
                      label: 'Device Name',
                      value: request.deviceName,
                    ),
                    const Divider(color: AppColors.border, height: 18),
                    _buildInfoRow(
                      icon: Icons.vpn_key_rounded,
                      label: 'Connection Key',
                      value: request.fromKey,
                      isMonospace: true,
                    ),
                    if (request.ip.isNotEmpty) ...[
                      const Divider(color: AppColors.border, height: 18),
                      _buildInfoRow(
                        icon: Icons.wifi_rounded,
                        label: 'IP Address',
                        value: request.ip,
                        isMonospace: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Security note
              const Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Approving this request allows this remote laptop to move your mouse cursor and type keystrokes.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.coral.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Decline',
                        style: TextStyle(
                          color: AppColors.coral,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppColors.emerald,
                        elevation: 4,
                        shadowColor: AppColors.emerald.withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_rounded, color: Colors.black, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Accept & Allow Control',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isMonospace = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: isMonospace ? 'Courier' : null,
          ),
        ),
      ],
    );
  }
}
