import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/live_stream_service.dart';
import '../../widgets/live_badge.dart';
import '../../widgets/verified_badge.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final service = LiveStreamService();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.tr('live_feed'),
          style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<LiveStream>>(
          key: ValueKey('feed_$_refreshKey'),
          stream: service.getActiveStreams(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const GoogleLoadingPage();
            }
            final streams = snap.data ?? [];
            if (streams.isEmpty) {
              return RefreshIndicator(
                onRefresh: _handleRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: _buildEmpty(context, cs),
                  ),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  MediaQuery.of(context).padding.bottom + 12,
                ),
                itemCount: streams.length,
                itemBuilder: (context, index) =>
                    _buildStreamCard(context, streams[index], cs),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    setState(() => _refreshKey++);
  }

  Widget _buildEmpty(BuildContext context, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.videocam_off_rounded,
              size: 64,
              color: cs.onErrorContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr('no_live_now'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('no_live_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamCard(BuildContext context, LiveStream stream, ColorScheme cs) {
    final dur = DateTime.now().difference(stream.startedAt);
    final durStr = dur.inMinutes < 60
        ? '${dur.inMinutes}m'
        : '${dur.inHours}h ${dur.inMinutes % 60}m';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.push(AppRoutes.live, extra: stream);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.surfaceContainerHighest, cs.surfaceContainerLow],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child:
                      stream.productImage != null &&
                          stream.productImage!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: stream.productImage!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 200,
                          errorWidget: (_, _, _) => _buildPlaceholder(cs),
                        )
                      : _buildPlaceholder(cs),
                ),
                Positioned(top: 12, left: 12, child: LiveBadge(size: 28)),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          durStr,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      stream.productName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      stream.userName.isNotEmpty
                          ? stream.userName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              stream.userName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: cs.onSurface,
                              ),
                            ),
                            VerifiedBadge(tier: stream.userTier, size: 14),
                          ],
                        ),
                        Text(
                          "${context.tr('selling')} ${stream.productName}",
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.tr('watch'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
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

  Widget _buildPlaceholder(ColorScheme cs) {
    return Center(
      child: Icon(
        Icons.image,
        size: 48,
        color: cs.onSurface.withValues(alpha: 0.4),
      ),
    );
  }
}
