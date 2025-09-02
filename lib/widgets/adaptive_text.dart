import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';

class AdaptiveText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final bool autoSize;
  final double? minFontSize;
  final double? maxFontSize;
  final TextOverflow? overflow;

  const AdaptiveText(
      this.text, {
        super.key,
        this.style,
        this.textAlign,
        this.maxLines,
        this.autoSize = false,
        this.minFontSize,
        this.maxFontSize,
        this.overflow,
      });

  // For dynamic content (emails, usernames, etc.) - needs ellipsis protection
  const AdaptiveText.dynamic(
      this.text, {
        super.key,
        this.style,
        this.textAlign,
        this.maxLines = 1,
      }) : autoSize = true,
        minFontSize = 12,
        maxFontSize = null,
        overflow = TextOverflow.ellipsis; // ✅ Keep ellipsis for dynamic content

  // For static UI text (labels, titles, etc.) - should not truncate
  const AdaptiveText.static(
      this.text, {
        super.key,
        this.style,
        this.textAlign,
        this.maxLines,
      }) : autoSize = false,
        minFontSize = null,
        maxFontSize = null,
        overflow = null; // ✅ No forced ellipsis for static text

  @override
  Widget build(BuildContext context) {
    if (autoSize) {
      return AutoSizeText(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        minFontSize: minFontSize ?? 12,
        maxFontSize: maxFontSize ?? (style?.fontSize ?? 18),
        overflow: overflow ?? TextOverflow.ellipsis, // Default to ellipsis for AutoSizeText
      );
    } else {
      return Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow, // ✅ No default overflow for static text
      );
    }
  }
}
