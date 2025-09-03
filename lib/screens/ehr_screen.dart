// lib/screens/ehr_screen.dart
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import '../services/ehr_service.dart';
import 'ehr_report_view.dart';
import 'ehr_upload_screen.dart';

class EHRScreen extends StatefulWidget {
  final bool isBucketPublic;
  const EHRScreen({super.key, this.isBucketPublic = false});

  @override
  State<EHRScreen> createState() => _EHRScreenState();
}

class _EHRScreenState extends State<EHRScreen> {
  late Future<List<String>> _future;

  @override
  void initState() {
    super.initState();
    _future = EHRService.listUserReportPaths();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = EHRService.listUserReportPaths();
    });
    await _future.catchError((_) => {});
  }

  Future<String> _resolveUrl(String fullPath) {
    if (widget.isBucketPublic) {
      return Future.value(EHRService.getPublicUrlForPath(fullPath));
    } else {
      return EHRService.getSignedUrlForPath(fullPath, expiresInSeconds: 900);
    }
  }

  String _fileName(String fullPath) {
    try {
      return fullPath.split('/').last;
    } catch (_) {
      return fullPath;
    }
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 60,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          const SizedBox(height: 16),
          const Text(
            'No Reports Found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Your uploaded medical reports will appear here.',
            style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageTile(String fullPath) {
    final heroTag = 'ehr:${fullPath.hashCode}';
    return FutureBuilder<String>(
      future: _resolveUrl(fullPath),
      builder: (context, snap) {
        final hasData = snap.hasData && !snap.hasError;
        final url = hasData ? snap.data : null;
        return Material(
          elevation: 3,
          shadowColor: Colors.black.withOpacity(0.2),
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
                  fit: StackFit.expand,
                  children: [
                    if (url != null)
                      Hero(
                        tag: heroTag,
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          loadingBuilder: (c, w, p) {
                            if (p == null) return w;
                            return Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: p.expectedTotalBytes != null
                                    ? p.cumulativeBytesLoaded / p.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          errorBuilder: (c, e, s) => const Center(
                              child: Icon(Icons.broken_image, color: Colors.red, size: 32)),
                        ),
                      )
                    else
                      Container(
                        color: Theme.of(context).dividerColor.withOpacity(0.05),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _fileName(fullPath),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.visibility_rounded,
                              color: Colors.white.withOpacity(0.9),
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
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0B0B) : const Color(0xFFF6F7FB),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<String>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Failed to load reports: ${snapshot.error}', textAlign: TextAlign.center),
                ),
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return Stack(
                children: [
                  ListView(),
                  _buildEmptyState(),
                ],
              );
            }
            final crossAxisCount = MediaQuery.of(context).size.width > 680 ? 3 : 2;
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (context, index) => _buildImageTile(items[index]),
            );
          },
        ),
      ),
      // NEW: Floating Action Button
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_ehr_fab',
        onPressed: () async {
          final changed = await Navigator.of(context).push<bool?>(
            MaterialPageRoute(builder: (_) => const EHRUploadScreen()),
          );
          if (changed == true) {
            await _refresh();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
