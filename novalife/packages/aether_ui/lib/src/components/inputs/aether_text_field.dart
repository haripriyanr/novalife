import 'package:flutter/material.dart';

import '../../theme/aether_radii.dart';
import '../../utils/extensions.dart';

/// Standardized input field with floating label, error state, prefix/suffix icons,
/// and built-in password visibility toggle button.
class AetherTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool isPassword;
  final bool enabled;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final FocusNode? focusNode;
  final bool autofocus;

  const AetherTextField({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffixIcon,
    this.isPassword = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.validator,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<AetherTextField> createState() => _AetherTextFieldState();
}

class _AetherTextFieldState extends State<AetherTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    Widget? effectiveSuffix = widget.suffixIcon;
    if (widget.isPassword) {
      effectiveSuffix = IconButton(
        key: const Key('aether_password_visibility_btn'),
        icon: Icon(
          _obscured ? Icons.visibility_off : Icons.visibility,
          color: colors.textSecondary,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Text(
              widget.label!,
              style: typography.labelMedium.copyWith(color: colors.textPrimary),
            ),
          ),
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          obscureText: widget.isPassword ? _obscured : false,
          maxLines: widget.isPassword ? 1 : widget.maxLines,
          minLines: widget.minLines,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onEditingComplete: widget.onEditingComplete,
          onSubmitted: widget.onSubmitted,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(color: colors.textMuted),
            errorText: widget.errorText,
            errorStyle: TextStyle(color: colors.danger.base),
            helperText: widget.helperText,
            helperStyle: TextStyle(color: colors.textSecondary),
            prefixIcon: widget.prefixIcon,
            suffixIcon: effectiveSuffix,
            filled: true,
            fillColor: widget.enabled ? colors.surface : colors.surfaceSubtle,
            enabledBorder: OutlineInputBorder(
              borderRadius: AetherRadii.sm,
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AetherRadii.sm,
              borderSide: BorderSide(color: colors.primary, width: 2.0),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: AetherRadii.sm,
              borderSide: BorderSide(color: colors.danger.base),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: AetherRadii.sm,
              borderSide: BorderSide(color: colors.danger.base, width: 2.0),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: AetherRadii.sm,
              borderSide: BorderSide(color: colors.borderSubtle),
            ),
          ),
        ),
      ],
    );
  }
}
