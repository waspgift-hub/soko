import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/music_state_notifier.dart';
import '../../extensions/context_tr.dart';

class MusicQueueScreen extends StatelessWidget {
  const MusicQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer<MusicStateNotifier>(
      builder: (context, state, _) {
        final queue = state.queue;
        final currentIdx = state.currentIndex ?? 0;

        return Scaffold(
          appBar: AppBar(
            title: Text('${context.tr('play_queue')} (${queue.length})'),
            centerTitle: true,
          ),
          body: queue.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.queue_music_rounded, size: 64, color: cs.outline),
                      const SizedBox(height: 16),
                      Text(
                        context.tr('queue_is_empty'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: queue.length,
                  itemBuilder: (_, i) {
                    final item = queue[i];
                    final isCurrent = i == currentIdx;
                    return Card(
                      color: isCurrent
                          ? cs.primary.withValues(alpha: 0.1)
                          : cs.surfaceContainerLow,
                      elevation: 0,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        leading: CircleAvatar(
                          backgroundColor: isCurrent ? cs.primary : cs.surfaceContainerHighest,
                          radius: 18,
                          child: Icon(
                            isCurrent ? Icons.play_arrow_rounded : Icons.music_note_rounded,
                            color: isCurrent ? cs.onPrimary : cs.onSurfaceVariant,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
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
                            IconButton(
                              icon: Icon(Icons.close_rounded,
                                  size: 18, color: cs.onSurfaceVariant),
                              onPressed: () {
                                final handler = context
                                    .read<MusicStateNotifier>();
                                handler.load(
                                  [...queue]..removeAt(i),
                                  index: i < currentIdx ? currentIdx - 1 : currentIdx,
                                  autoPlay: true,
                                );
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          context.pop();
                          state.load(queue, index: i);
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
