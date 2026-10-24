import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class DeviceAvatar extends StatelessWidget {
  final double size;
  final bool? isMac;
  final bool showBadge;
  final BoxBorder? border;

  const DeviceAvatar({
    super.key,
    this.size = 36,
    this.isMac,
    bool? showBadge,
    bool? showPlatformBadge,
    this.border,
  }) : showBadge = showPlatformBadge ?? showBadge ?? true;

  static const String imagePath = 'lib/images/Display.png';
  static const String fallbackImagePath = 'assets/images/Display.png';

  @override
  Widget build(BuildContext context) {
    final Widget avatarImage = ClipOval(
      child: Image.asset(
        imagePath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            fallbackImagePath,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              color: AppColors.cyan.withOpacity(0.2),
              child: Icon(
                isMac == true ? Icons.laptop_mac_rounded : Icons.laptop_windows_rounded,
                color: AppColors.cyan,
                size: size * 0.55,
              ),
            ),
          );
        },
      ),
    );

    if (!showBadge || isMac == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: border ?? Border.all(color: AppColors.cyan.withOpacity(0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.cyan.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: avatarImage,
      );
    }

    final badgeSize = (size * 0.44).clamp(12.0, 20.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: border ?? Border.all(color: AppColors.cyan.withOpacity(0.35), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: avatarImage,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  isMac == true ? Icons.apple_rounded : Icons.window_rounded,
                  size: badgeSize * 0.65,
                  color: isMac == true ? Colors.white : const Color(0xFF00A4EF),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
