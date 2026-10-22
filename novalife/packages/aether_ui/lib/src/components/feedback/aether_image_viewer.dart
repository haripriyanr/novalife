import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../../theme/aether_radii.dart';
import '../../utils/extensions.dart';

/// High-fidelity interactive pan & zoom viewer built strictly on pure Flutter SDK
/// [InteractiveViewer] with programmatic zoom, double-tap focal zoom, and overlay controls.
class AetherImageViewer extends StatefulWidget {
  /// Arbitrary widget content to display inside the interactive viewer.
  final Widget? child;

  /// Optional image provider (e.g. [MemoryImage], [NetworkImage]).
  final ImageProvider? imageProvider;

  /// Optional memory bytes for local raw images.
  final Uint8List? imageBytes;

  /// Optional remote image URL.
  final String? imageUrl;

  /// Controller managing the transformation matrix.
  final TransformationController? controller;

  /// Minimum zoom scale factor. Defaults to 0.5.
  final double minScale;

  /// Maximum zoom scale factor. Defaults to 8.0.
  final double maxScale;

  /// Target zoom scale when double-tapping. Defaults to 2.5.
  final double doubleTapScale;

  /// Whether to display floating zoom-in, zoom-out, and reset control buttons. Defaults to true.
  final bool showControls;

  /// Optional custom action buttons overlaid on top of the viewer.
  final List<Widget>? overlayActions;

  /// Placeholder widget displayed while an image loads.
  final Widget? placeholder;

  /// Widget displayed if an image fails to load.
  final Widget? errorWidget;

  /// Image box fit. Defaults to [BoxFit.contain].
  final BoxFit fit;

  /// Background color behind the image. Defaults to ambient surface.
  final Color? backgroundColor;

  const AetherImageViewer({
    super.key,
    this.child,
    this.imageProvider,
    this.imageBytes,
    this.imageUrl,
    this.controller,
    this.minScale = 0.5,
    this.maxScale = 8.0,
    this.doubleTapScale = 2.5,
    this.showControls = true,
    this.overlayActions,
    this.placeholder,
    this.errorWidget,
    this.fit = BoxFit.contain,
    this.backgroundColor,
  });

  @override
  State<AetherImageViewer> createState() => AetherImageViewerState();
}

class AetherImageViewerState extends State<AetherImageViewer> {
  late TransformationController _controller;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TransformationController();
  }

  @override
  void didUpdateWidget(AetherImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && widget.controller != _controller) {
      _controller = widget.controller!;
    }
  }

  /// Programmatically zooms in by [factor] (defaults to 1.25x).
  void zoomIn([double factor = 1.25]) {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    if (currentScale * factor <= widget.maxScale) {
      _controller.value = _controller.value.clone()..scaleByDouble(factor, factor, 1.0, 1.0);
      setState(() {});
    }
  }

  /// Programmatically zooms out by [factor] (defaults to 0.8x).
  void zoomOut([double factor = 0.8]) {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    if (currentScale * factor >= widget.minScale) {
      _controller.value = _controller.value.clone()..scaleByDouble(factor, factor, 1.0, 1.0);
      setState(() {});
    }
  }

  /// Resets the zoom matrix to the identity matrix (1.0x).
  void resetZoom() {
    _controller.value = Matrix4.identity();
    setState(() {});
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    if ((currentScale - 1.0).abs() < 0.1) {
      // Zoom into focal point
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      final targetScale = widget.doubleTapScale;
      final x = -position.dx * (targetScale - 1);
      final y = -position.dy * (targetScale - 1);

      _controller.value = Matrix4.identity()
        ..translateByDouble(x, y, 0.0, 1.0)
        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
    } else {
      // Reset zoom
      resetZoom();
    }
    setState(() {});
  }

  Widget _buildContent(BuildContext context) {
    final colors = context.aetherColors;

    if (widget.child != null) {
      return Center(child: widget.child);
    }

    if (widget.imageBytes != null) {
      return Image.memory(
        widget.imageBytes!,
        fit: widget.fit,
        errorBuilder: (ctx, err, stack) =>
            widget.errorWidget ?? Center(child: Icon(Icons.broken_image, size: 48, color: colors.textMuted)),
      );
    }

    if (widget.imageProvider != null) {
      return Image(
        image: widget.imageProvider!,
        fit: widget.fit,
        errorBuilder: (ctx, err, stack) =>
            widget.errorWidget ?? Center(child: Icon(Icons.broken_image, size: 48, color: colors.textMuted)),
      );
    }

    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      return Image.network(
        widget.imageUrl!,
        fit: widget.fit,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return widget.placeholder ??
              Center(child: CircularProgressIndicator(strokeWidth: 2.0, color: colors.primary));
        },
        errorBuilder: (ctx, err, stack) =>
            widget.errorWidget ?? Center(child: Icon(Icons.broken_image, size: 48, color: colors.textMuted)),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;

    return Container(
      color: widget.backgroundColor ?? colors.background,
      child: Stack(
        children: [
          GestureDetector(
            onDoubleTapDown: _handleDoubleTapDown,
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: widget.minScale,
              maxScale: widget.maxScale,
              clipBehavior: Clip.hardEdge,
              child: SizedBox.expand(
                child: Center(child: _buildContent(context)),
              ),
            ),
          ),

          // Custom Overlay Actions (e.g., top-right tool buttons)
          if (widget.overlayActions != null && widget.overlayActions!.isNotEmpty)
            Positioned(
              top: 16.0,
              right: 16.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: colors.surface.withAlpha(220),
                  borderRadius: AetherRadii.md,
                  border: Border.all(color: colors.border),
                  boxShadow: context.aetherShadows.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.overlayActions!,
                ),
              ),
            ),

          // Floating Zoom Controls (bottom-right)
          if (widget.showControls)
            Positioned(
              bottom: 16.0,
              right: 16.0,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface.withAlpha(220),
                  borderRadius: AetherRadii.md,
                  border: Border.all(color: colors.border),
                  boxShadow: context.aetherShadows.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key('zoom_out_btn'),
                      icon: const Icon(Icons.zoom_out),
                      tooltip: 'Zoom Out',
                      color: colors.textPrimary,
                      onPressed: () => zoomOut(),
                    ),
                    IconButton(
                      key: const Key('zoom_reset_btn'),
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Reset Zoom',
                      color: colors.textPrimary,
                      onPressed: resetZoom,
                    ),
                    IconButton(
                      key: const Key('zoom_in_btn'),
                      icon: const Icon(Icons.zoom_in),
                      tooltip: 'Zoom In',
                      color: colors.textPrimary,
                      onPressed: () => zoomIn(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
