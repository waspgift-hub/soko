import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/music_state_notifier.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';

/// Full-screen music player with Spotify-style dark design.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _artAnimCtrl;
  late Animation<double> _artScale;

  @override
  void initState() {
    super.initState();
    _artAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _artScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _artAnimCtrl, curve: Curves.easeOutBack),
    );
    _artAnimCtrl.forward();
  }

  @override
  void dispose() {
    _artAnimCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer<MusicStateNotifier>(
      builder: (context, state, _) {
        final isPlaying = state.isPlaying;
        final hasQueue = state.queueLength > 1;
        final isShuffled = state.currentIndex != null;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurface),
              onPressed: () => context.pop(),
            ),
            title: Text(
              context.tr('now_playing'),
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: Icon(Icons.queue_music_rounded, color: cs.onSurfaceVariant),
                onPressed: () => context.push(AppRoutes.audioQueue),
              ),
            ],
          ),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.surface,
                  cs.surfaceContainerLow,
                  cs.surface,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 1),
                  // Album Art
                  ScaleTransition(
                    scale: _artScale,
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.surfaceContainerHighest,
                        image: state.artUri != null
                            ? DecorationImage(
                                image: NetworkImage(state.artUri.toString()),
                                fit: BoxFit.cover,
                              )
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: 0.15),
                            blurRadius: 40,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: state.artUri == null
                          ? Icon(Icons.music_note_rounded,
                              size: 100, color: cs.onSurface.withValues(alpha: 0.3))
                          : null,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Song Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      state.title.isNotEmpty ? state.title : context.tr('no_track'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Artist
                  Text(
                    state.artist.isNotEmpty ? state.artist : ' ',
                    style: TextStyle(
                      fontSize: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 24),
                  // Progress Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            activeTrackColor: cs.onSurface,
                            inactiveTrackColor: cs.surfaceContainerHighest,
                            thumbColor: cs.onSurface,
                            overlayColor: cs.onSurface.withValues(alpha: 0.1),
                          ),
                          child: Slider(
                            value: state.progress.clamp(0.0, 1.0),
                            onChanged: (v) {
                              final pos = Duration(
                                milliseconds:
                                    (state.duration.inMilliseconds * v).round(),
                              );
                              state.seek(pos);
                              _artAnimCtrl.reset();
                              _artAnimCtrl.forward();
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                state.formatDuration(state.position),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                state.formatDuration(state.duration),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Playback Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Shuffle
                      IconButton(
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: state.isPlaying && isShuffled
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.4),
                        ),
                        iconSize: 24,
                        onPressed: state.toggleShuffle,
                      ),
                      const SizedBox(width: 8),
                      // Previous
                      _ControlButton(
                        icon: Icons.skip_previous_rounded,
                        size: 32,
                        onPressed: hasQueue ? state.skipToPrevious : null,
                        cs: cs,
                      ),
                      const SizedBox(width: 16),
                      // Play/Pause (large)
                      GestureDetector(
                        onTap: () {
                          state.togglePlayPause();
                          _artAnimCtrl.reset();
                          _artAnimCtrl.forward();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.primary,
                            boxShadow: [
                              BoxShadow(
                                color: cs.shadow.withValues(alpha: 0.2),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: cs.onPrimary,
                            size: 40,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Next
                      _ControlButton(
                        icon: Icons.skip_next_rounded,
                        size: 32,
                        onPressed: hasQueue ? state.skipToNext : null,
                        cs: cs,
                      ),
                      const SizedBox(width: 8),
                      // Repeat
                      IconButton(
                        icon: _repeatIcon(state),
                        iconSize: 24,
                        color: state.isPlaying
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.4),
                        onPressed: state.cycleRepeat,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Queue indicator
                  if (hasQueue)
                    TextButton(
                      onPressed: () => context.push(AppRoutes.audioQueue),
                      child: Text(
                        '${context.tr('up_next')}: ${state.queueLength} ${context.tr('songs')}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (state.hasError)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, color: cs.error, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              context.tr('playback_error'),
                              style: TextStyle(color: cs.error, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _repeatIcon(MusicStateNotifier state) {
    // Access the handler's repeat mode via state
    return const Icon(Icons.repeat_rounded);
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onPressed;
  final ColorScheme cs;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.onPressed,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: onPressed != null
              ? cs.onSurface.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
      ),
      child: IconButton(
        icon: Icon(icon),
        iconSize: size,
        color: onPressed != null ? cs.onSurface : cs.onSurface.withValues(alpha: 0.2),
        onPressed: onPressed,
      ),
    );
  }
}
