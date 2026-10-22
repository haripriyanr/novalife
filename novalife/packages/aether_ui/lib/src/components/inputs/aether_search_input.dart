import 'dart:async';
import 'package:flutter/material.dart';

import '../../theme/aether_radii.dart';
import '../../utils/extensions.dart';

/// Dedicated search field with debounced onChanged timing, clear button,
/// and optional filter action button.
class AetherSearchInput extends StatefulWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final VoidCallback? onFilterTap;
  final Duration debounceDuration;
  final bool autofocus;
  final FocusNode? focusNode;
  final double height;
  final bool enabled;

  const AetherSearchInput({
    super.key,
    this.controller,
    this.hintText = 'Search…',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.onFilterTap,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.autofocus = false,
    this.focusNode,
    this.height = 44.0,
    this.enabled = true,
  });

  @override
  State<AetherSearchInput> createState() => _AetherSearchInputState();
}

class _AetherSearchInputState extends State<AetherSearchInput> {
  late final TextEditingController _ctrl;
  bool _isInternalController = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _isInternalController = widget.controller == null;
    _ctrl = widget.controller ?? TextEditingController();
  }

  void _onTextChange(String text) {
    _timer?.cancel();
    _timer = Timer(widget.debounceDuration, () {
      widget.onChanged?.call(text);
    });
    setState(() {});
  }

  void _clear() {
    _timer?.cancel();
    _ctrl.clear();
    widget.onClear?.call();
    widget.onChanged?.call('');
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isInternalController) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;

    return TextField(
      controller: _ctrl,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      onChanged: _onTextChange,
      onSubmitted: widget.onSubmitted,
      style: TextStyle(color: colors.textPrimary),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(color: colors.textMuted),
        prefixIcon: Icon(Icons.search, color: colors.textSecondary),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_ctrl.text.isNotEmpty)
              IconButton(
                key: const Key('aether_search_clear_btn'),
                icon: Icon(Icons.clear, size: 18, color: colors.textSecondary),
                onPressed: _clear,
              ),
            if (widget.onFilterTap != null)
              IconButton(
                key: const Key('aether_search_filter_btn'),
                icon: Icon(Icons.filter_list, size: 18, color: colors.textSecondary),
                onPressed: widget.onFilterTap,
              ),
          ],
        ),
        filled: true,
        fillColor: widget.enabled ? colors.surface : colors.surfaceSubtle,
        border: const OutlineInputBorder(borderRadius: AetherRadii.sm),
        enabledBorder: OutlineInputBorder(
          borderRadius: AetherRadii.sm,
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AetherRadii.sm,
          borderSide: BorderSide(color: colors.primary, width: 2.0),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AetherRadii.sm,
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
      ),
    );
  }
}
