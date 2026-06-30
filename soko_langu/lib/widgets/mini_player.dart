import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/music_state_notifier.dart';
import '../app/routes.dart';

/// Spotify-style persistent mini-player bar at the bottom of the screen.
/// Appears when audio is actively playing or paused with content.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer<MusicStateNotifier>(
      builder: (context, state, _) {
        if (!state.hasActivePlayback && state.queue.isEmpty) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () => context.push(AppRoutes.audioPlayer),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 0.5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // Album art
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: cs.primaryContainer,
                    child: state.artUri != null
                        ? Image.network(
                            state.artUri.toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(Icons.music_note),
                          )
                        : const Icon(Icons.music_note),
                  ),
                ),
                const SizedBox(width: 12),
                // Title + artist
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
                  height: 32,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: 32 * state.progress,
                      width: 3,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                // Play/Pause button
                IconButton(
                  icon: Icon(
                    state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: cs.onSurface,
                  ),
                  iconSize: 28,
                  onPressed: () => state.togglePlayPause(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
