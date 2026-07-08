import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/music_state_notifier.dart';
import '../app/routes.dart';
import '../theme/app_animations.dart';
import 'package:flutter/services.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.medium,
    );
    _slideAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Consumer<MusicStateNotifier>(
      builder: (context, state, _) {
        final hasPlayback = state.hasActivePlayback || state.queue.isNotEmpty;
        final currentRoute = GoRouterState.of(context).uri.toString();

        if (currentRoute == AppRoutes.audioPlayer) {
          return const SizedBox.shrink();
        }

        if (hasPlayback && !_wasActive) {
          _animCtrl.forward();
        } else if (!hasPlayback && _wasActive) {
          _animCtrl.reverse();
        }
        _wasActive = hasPlayback;

        if (!hasPlayback && _animCtrl.isDismissed) {
          return const SizedBox.shrink();
        }

        return AnimatedBuilder(
          animation: _animCtrl,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, 100 * _slideAnim.value),
              child: Opacity(
                opacity: _fadeAnim.value,
                child: Transform.scale(
                  scale: _scaleAnim.value,
                  child: child,
                ),
              ),
            );
          },
          child: _buildPlayerBar(cs, state, bottom),
        );
      },
    );
  }

  Widget _buildPlayerBar(ColorScheme cs, MusicStateNotifier state, double bottom) {
    return GestureDetector(
      onTap: () {
        if (GoRouterState.of(context).uri.toString() != AppRoutes.audioPlayer) {
          context.push(AppRoutes.audioPlayer);
        }
      },
      onVerticalDragEnd: (d) {
        if (d.primaryVelocity != null && d.primaryVelocity! > 500 &&
            GoRouterState.of(context).uri.toString() != AppRoutes.audioPlayer) {
          context.push(AppRoutes.audioPlayer);
        }
      },
      child: Container(
        margin: EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? bottom : 8),
        height: 68,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.surface.withValues(alpha: 0.92),
              cs.surfaceContainerLow.withValues(alpha: 0.95),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            // Artwork
            Hero(
              tag: 'album_art',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: AppAnimations.medium,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                  ),
                  child: state.artUri != null
                      ? Image.network(
                          state.artUri.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.music_note_rounded, size: 24),
                        )
                      : const Icon(Icons.music_note_rounded, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Title & Artist
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.title.isNotEmpty ? state.title : 'No track',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (state.artist.isNotEmpty)
                    Text(
                      state.artist,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Progress indicator
            Container(
              width: 3,
              height: 36,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: cs.surfaceContainerHighest,
              ),
              child: Column(
                children: [
                  if (state.progress > 0)
                    Container(
                      height: 36 * state.progress.clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [cs.primary, cs.tertiary],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // YouTube badge
            if (state.youtubeVideoId != null)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  Icons.videocam_rounded,
                  size: 14,
                  color: cs.primary.withValues(alpha: 0.6),
                ),
              ),
            const SizedBox(width: 4),
            // Play/Pause
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withValues(alpha: 0.15),
                    cs.primary.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: AnimatedSwitcher(
                  duration: AppAnimations.fast,
                  child: Icon(
                    state.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    key: ValueKey(state.isPlaying),
                    color: cs.primary,
                  ),
                ),
                iconSize: 28,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  state.togglePlayPause();
                },
              ),
            ),
            const SizedBox(width: 4),
            // Next
            IconButton(
              icon: Icon(Icons.skip_next_rounded,
                  color: cs.onSurfaceVariant),
              iconSize: 24,
              onPressed: () {
                HapticFeedback.lightImpact();
                state.skipToNext();
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
