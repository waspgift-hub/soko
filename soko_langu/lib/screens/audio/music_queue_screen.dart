import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/music_state_notifier.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_animations.dart';

class MusicQueueScreen extends StatefulWidget {
  const MusicQueueScreen({super.key});

  @override
  State<MusicQueueScreen> createState() => _MusicQueueScreenState();
}

class _MusicQueueScreenState extends State<MusicQueueScreen> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer<MusicStateNotifier>(
      builder: (context, state, _) {
        final queue = state.queue;
        final currentIdx = state.currentIndex ?? 0;

        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('play_queue'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${queue.length} ${queue.length == 1 ? 'song' : 'songs'}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              if (queue.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    state.load(queue, index: currentIdx, autoPlay: true);
                  },
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('Shuffle'),
                ),
            ],
          ),
          body: queue.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.queue_music_rounded,
                            size: 36, color: cs.onSurface.withValues(alpha: 0.3)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.tr('queue_is_empty'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add songs from the library',
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  physics: const BouncingScrollPhysics(),
                  itemCount: queue.length,
                  onReorder: (oldIdx, newIdx) {
                    final items = [...queue];
                    final item = items.removeAt(oldIdx);
                    items.insert(newIdx > oldIdx ? newIdx - 1 : newIdx, item);
                    state.load(items, index: currentIdx == oldIdx ? newIdx : currentIdx);
                  },
                  itemBuilder: (_, i) {
                    final item = queue[i];
                    final isCurrent = i == currentIdx;
                    final isEven = i.isEven;

                    return Dismissible(
                      key: ValueKey('queue_${item.id}_$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: cs.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.remove_circle_outline_rounded, color: cs.error, size: 24),
                      ),
                      onDismissed: (_) {
                        HapticFeedback.lightImpact();
                        final items = [...queue]..removeAt(i);
                        state.load(items,
                            index: i < currentIdx ? currentIdx - 1 : currentIdx,
                            autoPlay: state.isPlaying);
                      },
                      child: AnimatedScaleIn(
                        delay: Duration(milliseconds: 30 * i),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color: isCurrent
                                ? cs.primary.withValues(alpha: 0.08)
                                : isEven
                                    ? cs.surfaceContainerLow.withValues(alpha: 0.3)
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              leading: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      color: isCurrent ? cs.primary : cs.surfaceContainerHighest,
                                      child: item.artUri != null
                                          ? Image.network(item.artUri.toString(), fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) => Icon(
                                                Icons.music_note_rounded,
                                                color: isCurrent ? cs.onPrimary : cs.onSurfaceVariant,
                                              ))
                                          : Icon(
                                              Icons.music_note_rounded,
                                              color: isCurrent ? cs.onPrimary : cs.onSurfaceVariant,
                                            ),
                                    ),
                                  ),
                                  if (isCurrent)
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: cs.primary.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.play_arrow_rounded, size: 20),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 14,
                                  color: isCurrent ? cs.primary : cs.onSurface,
                                ),
                              ),
                              subtitle: item.artist != null && item.artist!.isNotEmpty
                                  ? Text(
                                      item.artist!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                    )
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isCurrent)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(Icons.equalizer_rounded,
                                          color: cs.primary, size: 18),
                                    ),
                                  Icon(Icons.drag_handle_rounded,
                                      color: cs.onSurface.withValues(alpha: 0.3), size: 20),
                                ],
                              ),
                              onTap: () {
                                context.pop();
                                state.load(queue, index: i);
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
