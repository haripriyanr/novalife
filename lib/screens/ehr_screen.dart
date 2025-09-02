import 'ehr_report_view.dart';
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../services/ehr_service.dart';

class EHRScreen extends StatefulWidget {
  final bool isBucketPublic; // true if medical-reports is public
  const EHRScreen({super.key, this.isBucketPublic = false});

  @override
  State<EHRScreen> createState() => _EHRScreenState();
}

class _EHRScreenState extends State<EHRScreen> {
  late Future<List<String>> _future; // full object paths like '<uuid>/file.png'

  @override
  void initState() {
    super.initState();
    _future = EHRService.listUserReportPaths();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = EHRService.listUserReportPaths();
    });
    await _future;
  }

  Future<String> _resolveUrl(String fullPath) {
    if (widget.isBucketPublic) {
      return Future.value(EHRService.getPublicUrlForPath(fullPath));
    } else {
      return EHRService.getSignedUrlForPath(fullPath, expiresInSeconds: 900);
    }
  } // Uses public or signed URL depending on bucket visibility [12][13]

  void _openFullImage(String url, String heroTag) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(0),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: Center(
                  child: Hero(
                    tag: heroTag,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (c, w, p) {
                        if (p == null) return w;
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      },
                      errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.red, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 28,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  } // Hero preview for a smoother image transition [7]

  String _fileName(String fullPath) {
    final parts = fullPath.split('/');
    return parts.isNotEmpty ? parts.last : fullPath;
  }

  Widget _tile(String fullPath) {
    final heroTag = 'ehr:${fullPath.hashCode}';
    return FutureBuilder<String>(
      future: _resolveUrl(fullPath),
      builder: (context, snap) {
        final isDone = snap.connectionState == ConnectionState.done;
        final hasData = snap.hasData && !snap.hasError;
        final url = hasData ? snap.data! : null;

        return Material(
          elevation: 2,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EHRReportView(
                    fullPath: fullPath,
                    isBucketPublic: widget.isBucketPublic,
                  ),
                ),
              );
            },
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Theme.of(context).colorScheme.surface,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    // Image or placeholder
                    Positioned.fill(
                      child: url != null
                          ? Hero(
                        tag: heroTag,
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          loadingBuilder: (c, w, p) {
                            if (p == null) return w;
                            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                          },
                          errorBuilder: (c, e, s) => const Center(
                            child: Icon(Icons.broken_image, color: Colors.red),
                          ),
                        ),
                      )
                          : Container(
                        color: Theme.of(context).dividerColor.withOpacity(0.1),
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                    // Gradient overlay footer with filename and view icon
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.55),
                              Colors.black.withOpacity(0.0),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _fileName(fullPath),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.visibility_rounded,
                              color: Colors.white.withOpacity(isDone && hasData ? 0.95 : 0.3),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  } // Card-like grid tiles with overlay info [6]

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Gradient header with SliverAppBar
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFF7C3AED),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 16, bottom: 12),
              title: const AutoSizeText('EHR', maxLines: 1),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E1B4B), const Color(0xFF7C3AED)]
                        : [const Color(0xFF7C3AED), const Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ), // Gradient via flexible background [1]

          SliverToBoxAdapter(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<String>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 36),
                          const SizedBox(height: 12),
                          Text(
                            'Failed to load reports: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final items = snapshot.data ?? const <String>[];
                  if (items.isEmpty) {
                    return SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.medical_information_outlined,
                                size: 40, color: isDark ? Colors.white54 : Colors.black38),
                            const SizedBox(height: 10),
                            Text(
                              'No medical reports found',
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Responsive padding and grid
                  final crossAxisCount = MediaQuery.of(context).size.width > 680 ? 3 : 2;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    child: GridView.builder(
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                      itemCount: items.length,
                      shrinkWrap: true,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.0,
                      ),
                      itemBuilder: (context, index) => _tile(items[index]),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
