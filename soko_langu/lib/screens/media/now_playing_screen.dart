import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../extensions/context_tr.dart';
import '../../models/soko_media_item.dart';
import '../../services/media_player_service.dart';
import '../../theme/app_themes.dart';
import '../../widgets/media/soko_artwork.dart';

/// Full-screen music player: rotating album-art disc, scrolling title,
/// equalizer bars while playing, drag-to-seek slider and transport controls.
///
/// Animations (disc rotation, track crossfade, playing-state springs) are
/// driven purely by [MediaPlayerService] state, so this screen stays in sync
/// with the notification/lock-screen controls automatically.
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 24));
    MediaPlayerService.instance.addListener(_onPlayer);
    // Disc starts spinning immediately if something is already playing.
    if (MediaPlayerService.instance.playing) _spin.repeat();
  }

  void _onPlayer() {
    if (!mounted) return;
    final player = MediaPlayerService.instance;
    if (player.playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!player.playing && _spin.isAnimating) {
      _spin.stop();
    }
    setState(() {});
  }

  @override
  void dispose() {
    MediaPlayerService.instance.removeListener(_onPlayer);
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brand = SokoColors.of(context);
    final player = MediaPlayerService.instance;
    final item = player.current;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.tr('now_playing'),
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          if (player.queue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${(player.currentIndex ?? 0) + 1}/${player.queue.length}',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Spacer(flex: 1),
                  // Track-aware crossfading disc + info.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.92, end: 1.0).animate(
                          CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                    child: _TrackBlock(
                      key: ValueKey(item?.id ?? 'empty'),
                      item: item,
                      spin: _spin,
                      cs: cs,
                    ),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
            _buildProgress(player, brand, cs),
            const SizedBox(height: 8),
            _buildControls(player, brand, cs),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(
    MediaPlayerService player,
    SokoColors brand,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: StreamBuilder<Duration>(
        stream: player.positionStream,
        initialData: player.safePosition,
        builder: (context, snap) {
          final pos = snap.data ?? player.safePosition;
          final dur = player.duration ?? Duration.zero;
          final frac = dur > Duration.zero
              ? pos.inMilliseconds / dur.inMilliseconds
              : 0.0;
          return Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: brand.commerce,
                  inactiveTrackColor: cs.outlineVariant.withValues(alpha: 0.25),
                  thumbColor: brand.commerce,
                ),
                child: Slider(
                  value: frac.clamp(0.0, 1.0),
                  onChanged: dur > Duration.zero
                      ? (v) => player.seek(
                            Duration(milliseconds: (v * dur.inMilliseconds).round()),
                          )
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmt(pos),
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _fmt(dur),
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControls(
    MediaPlayerService player,
    SokoColors brand,
    ColorScheme cs,
  ) {
    final disabled = cs.onSurfaceVariant.withValues(alpha: 0.3);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            iconSize: 22,
            icon: Icon(
              Icons.shuffle_rounded,
              color: player.shuffle ? brand.commerce : disabled,
            ),
            onPressed: () => player.setShuffleEnabled(!player.shuffle),
          ),
          IconButton(
            iconSize: 34,
            icon: Icon(Icons.skip_previous_rounded, color: cs.onSurface),
            onPressed: player.previous,
          ),
          // Heart of the screen — large green play/pause with a springy pulse.
          GestureDetector(
            onTap: player.toggle,
            child: AnimatedScale(
              // Scale keyed to playing state gives a subtle "breath" effect.
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              scale: player.playing ? 1.0 : 0.96,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: brand.commerce,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: brand.commerce.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: player.playing
                      ? const Icon(
                          Icons.pause_rounded,
                          key: ValueKey('pause'),
                          color: Colors.black,
                          size: 32,
                        )
                      : const Icon(
                          Icons.play_arrow_rounded,
                          key: ValueKey('play'),
                          color: Colors.black,
                          size: 36,
                        ),
                ),
              ),
            ),
          ),
          IconButton(
            iconSize: 34,
            icon: Icon(Icons.skip_next_rounded, color: cs.onSurface),
            onPressed: player.next,
          ),
          IconButton(
            iconSize: 22,
            icon: Icon(
              player.loop == LoopMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: player.loop == LoopMode.off ? disabled : brand.commerce,
            ),
            onPressed: player.cycleLoop,
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Disc + info; keyed by track id so [AnimatedSwitcher] crossfades tracks.
class _TrackBlock extends StatelessWidget {
  const _TrackBlock({
    super.key,
    required this.item,
    required this.spin,
    required this.cs,
  });

  final SokoMediaItem? item;
  final AnimationController spin;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final playing = MediaPlayerService.instance.playing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Disc(spin: spin, item: item),
        const SizedBox(height: 26),
        _Equalizer(playing: playing && item != null),
        const SizedBox(height: 6),
        MarqueeText(
          text: item?.title ?? context.tr('no_media'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item?.subtitle ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Rotating album-art disc with a static gloss sheen and center spindle.
class _Disc extends StatelessWidget {
  const _Disc({required this.spin, required this.item});
  final AnimationController spin;
  final SokoMediaItem? item;

  @override
  Widget build(BuildContext context) {
    final size = 250.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: spin,
            builder: (context, child) => Transform.rotate(
              angle: spin.value * 2 * math.pi,
              child: child,
            ),
            child: SokoArtwork(item: item, size: size, radius: size / 2),
          ),
          // Static gloss so the disc reads as glossy while it spins.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.12),
                ],
              ),
            ),
          ),
          // Center spindle (rotates with the disc for realism).
          AnimatedBuilder(
            animation: spin,
            builder: (context, child) => Transform.rotate(
              angle: spin.value * 2 * math.pi,
              child: child,
            ),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three small bars that bounce while a track is playing.
class _Equalizer extends StatefulWidget {
  const _Equalizer({required this.playing});
  final bool playing;
  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.playing) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _Equalizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.playing && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const phases = [0.0, 0.65, 0.3];
    return AnimatedOpacity(
      opacity: widget.playing ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = (_ctrl.value * 4).floor();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              3,
              (i) {
                final p = phases[(i + t) % phases.length];
                final h = 8.0 + 16.0 * p;
                return Container(
                  width: 4,
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: SokoColors.of(context).commerce,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Auto-scrolls [text] horizontally (bounce marquee) when it overflows.
class MarqueeText extends StatefulWidget {
  const MarqueeText({super.key, required this.text, this.style});
  final String text;
  final TextStyle? style;
  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _overflowing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..addStatusListener((status) {
        // After scrolling out, glide back in; then repeat.
        if (status == AnimationStatus.completed) {
          _ctrl.reverse();
        } else if (status == AnimationStatus.dismissed) {
          _ctrl.forward();
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _ctrl.stop();
      _ctrl.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final width = _availableWidth();
    _overflowing = _textWidth() > width;
    if (_overflowing && !_ctrl.isAnimating) _ctrl.forward();
  }

  double _availableWidth() => MediaQuery.of(context).size.width - 72;

  double _textWidth() {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    if (!_overflowing) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: widget.style,
      );
    }
    final width = _availableWidth();
    return ClipRect(
      child: SizedBox(
        width: width,
        height: _textHeight(),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            // value goes 0→1 (scroll out) then 1→0 (scroll back in).
            final range = _textWidth() - width;
            return Transform.translate(
              offset: Offset(-range * _ctrl.value, 0),
              child: Text(widget.text, style: widget.style),
            );
          },
        ),
      ),
    );
  }

  double _textHeight() {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.height + 2;
  }
}