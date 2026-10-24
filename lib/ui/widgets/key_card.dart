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
            const Icon(Icons.check_circle, color: AppColors.emerald, size: 18),
            const SizedBox(width: 8),
            Text(
              'Connection key copied: ${widget.connectionKey}',
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ],
        ),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMac = Platform.isMacOS;

    return GlassCard(
      borderRadius: 4,
      borderColor: AppColors.borderStrong,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    DeviceAvatar(
                      size: 32,
                      isMac: isMac,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CONNECT TO SYSTEM',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'This Device (${widget.deviceName})',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Copy Button
              OutlinedButton.icon(
                onPressed: _copyKey,
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 15,
                  color: _copied ? AppColors.emerald : AppColors.textPrimary,
                ),
                label: Text(
                  _copied ? 'Copied' : 'Copy Key',
                  style: TextStyle(
                    color: _copied ? AppColors.emerald : AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  side: BorderSide(
                    color: _copied ? AppColors.emerald : AppColors.borderStrong,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Key Display Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CONNECTION KEY',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      widget.connectionKey,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ],
                ),
                Text(
                  'Share to allow control',
                  style: TextStyle(
                    color: AppColors.textMuted.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Metadata row
          Row(
            children: [
              const Icon(Icons.wifi_rounded, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                'Local IP: ${widget.localIp}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontFamily: 'Courier',
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                '•',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(width: 16),
              const Text(
                'Ready for incoming connection',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
