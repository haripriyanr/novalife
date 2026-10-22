import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../../theme/aether_colors.dart';
import '../../utils/extensions.dart';
import 'aether_status_badge.dart';

/// User or entity avatar with automatic 2-letter uppercase initials computation,
/// image loader, and status dot indicator ring.
class AetherAvatarBadge extends StatelessWidget {
  /// Full name used to compute fallback initials (e.g. 'Anjali Mehta' -> 'AM').
  final String? name;

  /// Network URL to load avatar image from.
  final String? imageUrl;

  /// Memory bytes to load avatar image from.
  final Uint8List? imageBytes;

  /// Diameter of the avatar. Defaults to 40.0.
  final double size;

  /// Semantic state to display as a small status dot anchored at bottom-right.
  final AetherStatusVariant? statusDot;

  /// Custom background color for initials fallback. Defaults to [AetherColors.primaryContainer].
  final Color? customBackgroundColor;

  /// Custom foreground color for initials text. Defaults to [AetherColors.primary].
  final Color? customForegroundColor;

  const AetherAvatarBadge({
    super.key,
    this.name,
    this.imageUrl,
    this.imageBytes,
    this.size = 40.0,
    this.statusDot,
    this.customBackgroundColor,
    this.customForegroundColor,
  });

  /// Computes a clean 2-letter uppercase initial string from a name.
  static String computeInitials(String? name) {
    if (name == null || name.trim().isEmpty) return '??';
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final first = parts[0];
      final second = parts[1];
      return '${first[0]}${second[0]}'.toUpperCase();
    }
    final single = parts[0];
    return single.substring(0, math.min(2, single.length)).toUpperCase();
  }

  Color _resolveDotColor(AetherColors colors) {
    switch (statusDot!) {
      case AetherStatusVariant.success:
        return colors.success.base;
      case AetherStatusVariant.danger:
        return colors.danger.base;
      case AetherStatusVariant.warning:
        return colors.warning.base;
      case AetherStatusVariant.info:
        return colors.info.base;
      case AetherStatusVariant.neutral:
        return colors.neutral.base;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;

    ImageProvider? imageProvider;
    if (imageBytes != null) {
      imageProvider = MemoryImage(imageBytes!);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      imageProvider = NetworkImage(imageUrl!);
    }

    final double dotSize = (size * 0.28).clamp(8.0, 16.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundColor: customBackgroundColor ?? colors.primaryContainer,
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? Text(
                    computeInitials(name),
                    style: TextStyle(
                      color: customForegroundColor ?? colors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: size * 0.38,
                    ),
                  )
                : null,
          ),
          if (statusDot != null)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: _resolveDotColor(colors),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.surface,
                    width: 2.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
