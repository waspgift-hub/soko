import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../extensions/context_tr.dart';
import '../services/profile_media_controller.dart';
import '../services/profile_media_session.dart';

/// Persistent mini player pinned above the bottom nav (Namida miniplayer
/// equivalent). Drives the same shared session controller as the seller
/// profile's inline player, so playback survives navigation. Hidden while the
/// inline player is on screen or when the queue is empty.
class ProfileMiniPlayer extends StatelessWidget {
  const ProfileMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final session = ProfileMediaSession.instance;
    final media = session.controller;
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<ProfileMediaState>(
      stream: media.stateStream,
      builder: (context, stateSnap) {
        return StreamBuilder<int>(
          stream: media.indexStream,
          builder: (context, _) {
            final item = media.current;
            final state = stateSnap.data;
            final active = item != null &&
                (state == ProfileMediaState.playing ||
                    state == ProfileMediaState.paused ||
                    state == ProfileMediaState.loading);
            if (!active || session.hasInlinePlayer) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Material(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                elevation: 4,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: session.returnRoute == null
                      ? null
                      : () => context.push(session.returnRoute!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: item.thumbnailUrl != null
                                    ? Image.network(
                                        item.thumbnailUrl!,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        color: Colors.black87,
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if ((session.sellerName ?? '').isNotEmpty)
                                    Text(
                                      session.sellerName!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            StreamBuilder<ProfileMediaState>(
                              stream: media.stateStream,
                              builder: (context, playSnap) {
                                final playing = media.isPlaying ||
                                    playSnap.data == ProfileMediaState.playing;
                                return IconButton(
                                  iconSize: 28,
                                  tooltip: playing ? context.tr('pause') : context.tr('play'),
                                  icon: Icon(
                                    playing
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_fill,
                                    color: scheme.primary,
                                  ),
                                  onPressed: media.toggle,
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next),
                              tooltip: context.tr('skip_next'),
                              onPressed: media.queue.length > 1
                                  ? media.next
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              tooltip: context.tr('close'),
                              onPressed: session.stop,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        StreamBuilder<Duration>(
                          stream: media.positionStream,
                          initialData: Duration.zero,
                          builder: (context, posSnap) {
                            return StreamBuilder<Duration>(
                              stream: media.durationStream,
                              initialData: Duration.zero,
                              builder: (context, durSnap) {
                                final pos = posSnap.data ?? Duration.zero;
                                final dur = durSnap.data ?? Duration.zero;
                                if (dur <= Duration.zero) {
                                  return const SizedBox(height: 2);
                                }
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    minHeight: 2,
                                    value: (pos.inMilliseconds / dur.inMilliseconds)
                                        .clamp(0.0, 1.0),
                                    backgroundColor: scheme.surfaceContainerHighest,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      scheme.primary,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
