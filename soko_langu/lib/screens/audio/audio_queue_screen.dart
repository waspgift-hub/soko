import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:go_router/go_router.dart';
import '../../services/audio_handler.dart';

class AudioQueueScreen extends StatefulWidget {
  const AudioQueueScreen({super.key});

  @override
  State<AudioQueueScreen> createState() => _AudioQueueScreenState();
}

class _AudioQueueScreenState extends State<AudioQueueScreen> {
  final _handler = SokoAudioHandler();
  List<MediaItem> _queue = [];
  StreamSubscription? _queueSub;

  @override
  void initState() {
    super.initState();
    _queue = _handler.queue.value;
    _queueSub = _handler.queue.stream.listen((items) {
      if (mounted) setState(() => _queue = items);
    });
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentIndex = _handler.playbackState.value.queueIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text('Play Queue (${_queue.length})'),
        centerTitle: true,
      ),
      body: _queue.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music, size: 64, color: cs.outline),
                  const SizedBox(height: 16),
                  Text(
                    'Queue is empty',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _queue.length,
              itemBuilder: (context, index) {
                final item = _queue[index];
                final isCurrent = index == currentIndex;
                return Card(
                  color: isCurrent ? cs.primary.withValues(alpha: 0.1) : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isCurrent
                          ? cs.primary
                          : cs.surfaceContainerHighest,
                      child: Icon(
                        isCurrent ? Icons.play_arrow : Icons.music_note,
                        color: isCurrent ? cs.onPrimary : cs.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrent ? cs.primary : cs.onSurface,
                      ),
                    ),
                    subtitle: item.artist != null && item.artist!.isNotEmpty
                        ? Text(
                            item.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: isCurrent
                        ? Icon(Icons.equalizer, color: cs.primary, size: 20)
                        : null,
                    onTap: () {
                      context.pop();
                      _handler.load(_queue, initialIndex: index);
                    },
                  ),
                );
              },
            ),
    );
  }
}
