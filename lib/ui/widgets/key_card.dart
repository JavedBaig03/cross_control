import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import 'device_avatar.dart';
import 'glass_card.dart';

class KeyCard extends StatefulWidget {
  final String connectionKey;
  final String deviceName;
  final String localIp;

  const KeyCard({
    super.key,
    required this.connectionKey,
    required this.deviceName,
    required this.localIp,
  });

  @override
  State<KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<KeyCard> {
  bool _copied = false;

  void _copyKey() {
    Clipboard.setData(ClipboardData(text: widget.connectionKey));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.emerald, size: 20),
            const SizedBox(width: 8),
            Text('Connection key copied: ${widget.connectionKey}'),
          ],
        ),
        backgroundColor: AppColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: AppColors.cyan.withOpacity(0.35),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  DeviceAvatar(
                    size: 36,
                    isMac: Platform.isMacOS,
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONNECT TO SYSTEM',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'This Laptop\'s Connection Key',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Copy Button
              ElevatedButton.icon(
                onPressed: _copyKey,
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 16,
                  color: _copied ? AppColors.emerald : AppColors.cyan,
                ),
                label: Text(
                  _copied ? 'Copied!' : 'Copy Key',
                  style: TextStyle(
                    color: _copied ? AppColors.emerald : AppColors.cyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _copied
                      ? AppColors.emerald.withOpacity(0.15)
                      : AppColors.cyan.withOpacity(0.12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: _copied
                          ? AppColors.emerald.withOpacity(0.4)
                          : AppColors.cyan.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Large stylized Key Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SelectableText(
                  widget.connectionKey,
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4.0,
                    fontFamily: 'Courier',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Device info & local IP row
          Row(
            children: [
              DeviceAvatar(size: 18, isMac: Platform.isMacOS, showBadge: false),
              const SizedBox(width: 6),
              Text(
                widget.deviceName,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.wifi_rounded, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'LAN IP: ${widget.localIp}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Courier',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
