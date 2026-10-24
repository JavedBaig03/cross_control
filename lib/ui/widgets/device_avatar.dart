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
    final borderRadius = BorderRadius.circular(4);

    final Widget avatarImage = ClipRRect(
      borderRadius: borderRadius,
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
              color: AppColors.surfaceElevated,
              child: Icon(
                isMac == true ? Icons.apple_rounded : Icons.laptop_windows_rounded,
                color: AppColors.textSecondary,
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
          borderRadius: borderRadius,
          border: border ?? Border.all(color: AppColors.border, width: 1.0),
        ),
        child: avatarImage,
      );
    }

    final badgeSize = (size * 0.44).clamp(12.0, 18.0);

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
              borderRadius: borderRadius,
              border: border ?? Border.all(color: AppColors.border, width: 1.0),
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
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: AppColors.borderStrong, width: 1.0),
              ),
              child: Center(
                child: Icon(
                  isMac == true ? Icons.apple_rounded : Icons.window_rounded,
                  size: badgeSize * 0.7,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
