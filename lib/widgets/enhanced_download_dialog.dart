import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'dart:async';
import '../services/model_path_service.dart';

class EnhancedDownloadDialog extends StatefulWidget {
  final Function(String) onModelPathSelected;
  final Function(Function(double), Function(String), Function(int), CancelToken) onDownloadStarted;

  const EnhancedDownloadDialog({
    super.key,
    required this.onModelPathSelected,
    required this.onDownloadStarted,
  });

  @override
  State<EnhancedDownloadDialog> createState() => _EnhancedDownloadDialogState();
}

class _EnhancedDownloadDialogState extends State<EnhancedDownloadDialog>
    with TickerProviderStateMixin {
  bool _isDownloading = false;
  bool _isPaused = false;
  bool _showingOptions = true;

  double _downloadProgress = 0.0;
  String _downloadSpeed = "0.00 MB/s";
  String _downloadedSize = "0 MB";
  String _totalSize = "0 MB";
  String _eta = "Calculating...";

  Timer? _speedTimer;
  CancelToken? _cancelToken;
  late AnimationController _progressAnimationController;
  late AnimationController _pulseAnimationController;

  final ScrollController _scrollController = ScrollController();
  bool _isAtBottom = false;
  bool _showScrollIndicator = false;

  int _lastReceivedBytes = 0;
  int _totalBytes = 0;
  late int _lastTime;

  final List<double> _speedHistory = [];

  @override
  void initState() {
    super.initState();
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimationController.repeat(reverse: true);

    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScrollCapability();
    });
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    _cancelToken?.cancel();
    _progressAnimationController.dispose();
    _pulseAnimationController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkScrollCapability() {
    if (!mounted || !_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    setState(() {
      _showScrollIndicator = maxScroll > 50;
      _isAtBottom = currentScroll >= (maxScroll - 20);
    });
  }

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final isAtBottom = currentScroll >= (maxScroll - 50);
    final shouldShowIndicator = maxScroll > 50;

    if (isAtBottom != _isAtBottom || shouldShowIndicator != _showScrollIndicator) {
      setState(() {
        _isAtBottom = isAtBottom;
        _showScrollIndicator = shouldShowIndicator;
      });
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void updateTotalBytes(int totalBytes) {
    if (mounted && totalBytes > 0) {
      setState(() {
        _totalBytes = totalBytes;
        if (totalBytes < 1024 * 1024 * 1024) {
          _totalSize = "${(totalBytes / (1024 * 1024)).toStringAsFixed(0)} MB";
        } else {
          _totalSize = "${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isDownloading || _isPaused) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xFF1E1E2E), const Color(0xFF2A2A3E)]
                  : [const Color(0xFFF8F9FA), const Color(0xFFFFFFFF)],
            ),
            border: Border.all(
              color: isDark ? const Color(0xFF4B5563) : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with icon and title
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimationController,
                    builder: (context, child) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isPaused
                              ? Colors.orange.withAlpha((25 + 25 * _pulseAnimationController.value).round())
                              : Colors.blue.withAlpha((25 + 25 * _pulseAnimationController.value).round()),
                        ),
                        child: Icon(
                          _isPaused ? Icons.pause_circle_filled : Icons.download_rounded,
                          color: _isPaused ? const Color(0xFFEA580C) : const Color(0xFF2563EB),
                          size: 28,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AutoSizeText(
                          _isPaused ? 'Download Paused' : 'Downloading with Cactus',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1F2937),
                          ),
                          maxLines: 1,
                          minFontSize: 16,
                          maxFontSize: 20,
                        ),
                        AutoSizeText(
                          'MedGemma 4B Model',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                          ),
                          maxLines: 1,
                          minFontSize: 12,
                          maxFontSize: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Progress section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isDark ? const Color(0xFF374151) : const Color(0xFFF9FAFB),
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _downloadProgress,
                        backgroundColor: isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isPaused ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6),
                        ),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        _buildInfoCard(
                          icon: Icons.percent,
                          label: 'Progress',
                          value: '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                          color: Colors.blue,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildInfoCard(
                          icon: Icons.speed,
                          label: 'Speed',
                          value: _downloadSpeed,
                          color: Colors.green,
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        _buildInfoCard(
                          icon: Icons.download_done,
                          label: 'Downloaded',
                          value: '$_downloadedSize / $_totalSize',
                          color: Colors.purple,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildInfoCard(
                          icon: Icons.schedule,
                          label: 'ETA',
                          value: _eta,
                          color: Colors.orange,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Control buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isPaused ? _resumeDownload : _pauseDownload,
                      icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                      label: AutoSizeText(
                        _isPaused ? 'Resume' : 'Pause',
                        maxLines: 1,
                        minFontSize: 12,
                        maxFontSize: 16,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isPaused ? const Color(0xFF059669) : const Color(0xFFEA580C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cancelDownload,
                      icon: const Icon(Icons.cancel_rounded),
                      label: const AutoSizeText(
                        'Cancel',
                        maxLines: 1,
                        minFontSize: 12,
                        maxFontSize: 16,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_showingOptions) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xFF1E1E2E), const Color(0xFF2A2A3E)]
                  : [const Color(0xFFF8F9FA), const Color(0xFFFFFFFF)],
            ),
            border: Border.all(
              color: isDark ? const Color(0xFF4B5563) : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fixed Header
              Container(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.withAlpha(25),
                      ),
                      child: const Icon(
                        Icons.smart_toy_rounded,
                        color: Color(0xFF2563EB),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AutoSizeText(
                            'AI Model Required',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF1F2937),
                            ),
                            maxLines: 1,
                            minFontSize: 16,
                            maxFontSize: 20,
                          ),
                          AutoSizeText(
                            'Powered by Cactus Framework',
                            style: TextStyle(
                              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                            ),
                            maxLines: 1,
                            minFontSize: 12,
                            maxFontSize: 16,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable Content
              Expanded(
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          AutoSizeText(
                            'Experience faster, more reliable AI with Cactus framework. Choose your setup method:',
                            style: TextStyle(
                              color: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF374151),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            minFontSize: 14,
                            maxFontSize: 18,
                          ),
                          const SizedBox(height: 24),

                          // Download Option Card
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.blue.withAlpha(25),
                                  Colors.blue.withAlpha(13),
                                ],
                              ),
                              border: Border.all(
                                color: Colors.blue.withAlpha(77),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.blue.withAlpha(51),
                                      ),
                                      child: const Icon(
                                        Icons.cloud_download_rounded,
                                        color: Color(0xFF2563EB),
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          AutoSizeText(
                                            'Download with Cactus',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white : const Color(0xFF1F2937),
                                            ),
                                            maxLines: 1,
                                            minFontSize: 16,
                                            maxFontSize: 20,
                                          ),
                                          AutoSizeText(
                                            'Optimized MedGemma 4B with Cactus framework (~2.4 GB)',
                                            style: TextStyle(
                                              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                                            ),
                                            maxLines: 2,
                                            minFontSize: 12,
                                            maxFontSize: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    'Cactus optimized',
                                    'Faster inference',
                                    'Better stability',
                                    'Progress tracking'
                                  ].map((feature) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: Colors.blue.withAlpha(25),
                                      border: Border.all(color: Colors.blue.withAlpha(51)),
                                    ),
                                    child: AutoSizeText(
                                      feature,
                                      style: const TextStyle(
                                        color: Color(0xFF2563EB),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      minFontSize: 10,
                                      maxFontSize: 14,
                                    ),
                                  )).toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Import Option Card
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.orange.withAlpha(25),
                                  Colors.orange.withAlpha(13),
                                ],
                              ),
                              border: Border.all(
                                color: Colors.orange.withAlpha(77),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.orange.withAlpha(51),
                                      ),
                                      child: const Icon(
                                        Icons.upload_file_rounded,
                                        color: Color(0xFFEA580C),
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          AutoSizeText(
                                            'Import GGUF Model',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white : const Color(0xFF1F2937),
                                            ),
                                            maxLines: 1,
                                            minFontSize: 16,
                                            maxFontSize: 20,
                                          ),
                                          AutoSizeText(
                                            'Select an existing GGUF model file from your device',
                                            style: TextStyle(
                                              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                                            ),
                                            maxLines: 2,
                                            minFontSize: 12,
                                            maxFontSize: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    'Any GGUF model',
                                    'Instant setup',
                                    'No download needed',
                                    'Cactus compatible'
                                  ].map((feature) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: Colors.orange.withAlpha(25),
                                      border: Border.all(color: Colors.orange.withAlpha(51)),
                                    ),
                                    child: AutoSizeText(
                                      feature,
                                      style: const TextStyle(
                                        color: Color(0xFFEA580C),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      minFontSize: 10,
                                      maxFontSize: 14,
                                    ),
                                  )).toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),

                    // Fixed Scroll Indicator
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: AnimatedOpacity(
                        opacity: _showScrollIndicator ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? Colors.black.withAlpha(180)
                                : Colors.black.withAlpha(128),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _showScrollIndicator ? () {
                              if (_isAtBottom) {
                                _scrollToTop();
                              } else {
                                _scrollToBottom();
                              }
                            } : null,
                            icon: Icon(
                              _isAtBottom ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              color: _showScrollIndicator ? Colors.white : Colors.transparent,
                              size: 24,
                            ),
                            iconSize: 24,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Fixed Action Buttons
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Import File Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _selectLocalFile,
                        icon: const Icon(
                          Icons.upload_file_rounded,
                          color: Color(0xFFEA580C),
                          size: 18,
                        ),
                        label: const AutoSizeText(
                          'Import',
                          maxLines: 1,
                          minFontSize: 12,
                          maxFontSize: 16,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFEA580C),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.withAlpha(25),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.orange.withAlpha(77)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Download Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          debugPrint('Cactus download button pressed');
                          _startDownload();
                        },
                        icon: const Icon(
                          Icons.cloud_download_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const AutoSizeText(
                          'Download',
                          maxLines: 1,
                          minFontSize: 12,
                          maxFontSize: 16,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isDark ? const Color(0xFF4B5563) : Colors.white,
          border: Border.all(
            color: color.withAlpha(51),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Color.lerp(color, isDark ? Colors.white : Colors.black, 0.1),
              size: 18,
            ),
            const SizedBox(height: 3),

            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 2),

            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1F2937),
                  fontSize: 12,
                ),
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startDownload() {
    debugPrint('Starting Cactus download...');

    setState(() {
      _isDownloading = true;
      _showingOptions = false;
      _downloadProgress = 0.0;
      _isPaused = false;
      _lastReceivedBytes = 0;
      _totalBytes = 2500 * 1024 * 1024;
      _totalSize = "2500 MB";
      _lastTime = DateTime.now().millisecondsSinceEpoch;
      _eta = "Calculating...";
      _downloadedSize = "0 MB";
      _downloadSpeed = "0.00 MB/s";
      _speedHistory.clear();
    });

    _cancelToken = CancelToken();
    _startSpeedTimer();
    _progressAnimationController.forward();

    debugPrint('Calling Cactus download callback...');
    widget.onDownloadStarted(
          (progress) => updateDownloadProgress(progress),
          (speed) => updateDownloadSpeed(speed),
          (totalBytes) => updateTotalBytes(totalBytes),
      _cancelToken!,
    );
  }

  void _pauseDownload() {
    _cancelToken?.cancel();
    _speedTimer?.cancel();
    _progressAnimationController.stop();
    setState(() {
      _isPaused = true;
      _isDownloading = false;
      _downloadSpeed = "0.00 MB/s";
      _eta = "Paused";
    });
  }

  void _resumeDownload() {
    setState(() {
      _isPaused = false;
      _isDownloading = true;
      _lastTime = DateTime.now().millisecondsSinceEpoch;
    });

    _cancelToken = CancelToken();
    _startSpeedTimer();
    _progressAnimationController.forward();

    widget.onDownloadStarted(
          (progress) => updateDownloadProgress(progress),
          (speed) => updateDownloadSpeed(speed),
          (totalBytes) => updateTotalBytes(totalBytes),
      _cancelToken!,
    );
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    _speedTimer?.cancel();
    _progressAnimationController.stop();

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.cancel_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Download cancelled'),
            ],
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _startSpeedTimer() {
    _speedTimer?.cancel();
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isPaused) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final timeDiff = now - _lastTime;

      if (timeDiff > 0 && _totalBytes > 1) {
        final currentReceivedBytes = (_downloadProgress * _totalBytes).toInt();
        final bytesDiff = currentReceivedBytes - _lastReceivedBytes;

        if (bytesDiff >= 0) {
          final bytesPerSecond = bytesDiff / (timeDiff / 1000);
          final mbPerSecond = bytesPerSecond / (1024 * 1024);

          if (mbPerSecond >= 0) {
            _speedHistory.add(mbPerSecond);
            if (_speedHistory.length > 10) {
              _speedHistory.removeAt(0);
            }
          }

          setState(() {
            _downloadSpeed = "${mbPerSecond.toStringAsFixed(2)} MB/s";
            _eta = _calculateETA();
          });

          _lastReceivedBytes = currentReceivedBytes;
        }
      }

      _lastTime = now;
    });
  }

  String _calculateETA() {
    if (_isPaused || _downloadProgress >= 1.0) return "Complete";

    if (_speedHistory.isEmpty || _totalBytes <= 1 || _downloadProgress <= 0) {
      return "Calculating...";
    }

    final recentSpeeds = _speedHistory.where((speed) => speed > 0.1).toList();
    if (recentSpeeds.isEmpty) return "Calculating...";

    final averageSpeedMBs = recentSpeeds.reduce((a, b) => a + b) / recentSpeeds.length;

    if (averageSpeedMBs <= 0.1) return "Calculating...";

    final remainingBytes = _totalBytes * (1 - _downloadProgress);
    final remainingMB = remainingBytes / (1024 * 1024);
    final etaSeconds = (remainingMB / averageSpeedMBs).round();

    if (etaSeconds <= 0) return "Almost done";

    if (etaSeconds < 60) {
      return "${etaSeconds}s";
    } else if (etaSeconds < 3600) {
      final minutes = etaSeconds ~/ 60;
      final seconds = etaSeconds % 60;
      return "${minutes}m ${seconds}s";
    } else {
      final hours = etaSeconds ~/ 3600;
      final minutes = (etaSeconds % 3600) ~/ 60;
      return "${hours}h ${minutes}m";
    }
  }

  void updateDownloadProgress(double progress) {
    debugPrint('Cactus progress update: $progress');
    if (mounted && !_isPaused) {
      setState(() {
        _downloadProgress = progress;

        if (_totalBytes > 1) {
          final downloadedBytes = (_downloadProgress * _totalBytes).toInt();

          if (downloadedBytes < 1024 * 1024) {
            _downloadedSize = "${(downloadedBytes / 1024).toStringAsFixed(0)} KB";
          } else {
            _downloadedSize = "${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
          }
        }

        if (progress >= 1.0) {
          _isDownloading = false;
          _speedTimer?.cancel();
          _downloadSpeed = "Complete!";
          _eta = "Complete";
          _progressAnimationController.forward();

          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        }
      });
    }
  }

  void updateDownloadSpeed(String speed) {
    if (mounted && !_isPaused) {
      setState(() {
        _downloadSpeed = speed;
      });
    }
  }

  void _selectLocalFile() async {
    final selectedPath = await ModelPathService.pickModelFile();

    if (selectedPath != null) {
      await ModelPathService.saveModelPath(selectedPath);
      widget.onModelPathSelected(selectedPath);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Model selected: ${selectedPath.split('/').last}'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }
}
