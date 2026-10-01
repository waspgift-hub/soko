import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/lyrics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import 'ds_empty_state.dart';
import 'ds_loading_dots.dart';

/// Scrolling lyrics panel for the full-screen audio player.
///
/// Two modes, picked from the data: when [lyrics] carries timestamps the view
/// highlights the active line and auto-scrolls to it; otherwise it renders the
/// plain text as one scrollable block, because there is nothing to sync to.
///
/// Auto-scroll yields to the user: dragging the list parks it until the user
/// taps a line (which seeks) or playback is restarted, so a manual scroll is
/// never yanked back mid-gesture.
class DsLyricsView extends StatefulWidget {
  final Lyrics lyrics;

  /// Current playback position, used to resolve the active line.
  final Duration position;
  final bool isPlaying;

  /// Fired when a timed line is tapped. Unsynced lyrics do not seek.
  final ValueChanged<Duration>? onSeek;

  /// Shows the loading dots instead of lyrics while a fetch is in flight.
  final bool loading;

  final String emptyTitle;
  final String emptyBody;
  final String instrumentalTitle;
  final String noSyncedHint;

  /// Overrides for callers rendering over a dark artwork backdrop.
  final Color? activeColor;
  final Color? inactiveColor;

  const DsLyricsView({
    super.key,
    required this.lyrics,
    this.position = Duration.zero,
    this.isPlaying = false,
    this.onSeek,
    this.loading = false,
    this.emptyTitle = 'No lyrics found',
    this.emptyBody = 'We could not find lyrics for this track.',
    this.instrumentalTitle = 'Instrumental',
    this.noSyncedHint = 'Tap and hold the artwork for a bigger view.',
    this.activeColor,
    this.inactiveColor,
  });

  @override
  State<DsLyricsView> createState() => _DsLyricsViewState();
}

class _DsLyricsViewState extends State<DsLyricsView> {
  final ScrollController _controller = ScrollController();

  int _activeIndex = -1;
  bool _userScrolling = false;

  /// Matches the ListView's default extent so a line can be scrolled to the
  /// vertical centre regardless of text length or width.
  static const double _lineExtent = 56;

  @override
  void didUpdateWidget(covariant DsLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isPlaying && oldWidget.isPlaying) {
      // Resuming playback re-centres, which is what the user expects after
      // they wandered off into a chorus that is no longer playing.
      _userScrolling = false;
    }
    _syncActive(force: true);
  }

  @override
  void initState() {
    super.initState();
    _activeIndex = widget.lyrics.activeIndexAt(widget.position);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnActive(jump: true));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncActive({bool force = false}) {
    if (!widget.lyrics.hasSynced) return;
    final next = widget.lyrics.activeIndexAt(widget.position);
    if (next == _activeIndex && !force) return;
    // Position ticks fire several times a second; only rebuild when the
    // highlighted line actually changes.
    setState(() => _activeIndex = next);
    if (!_userScrolling) _centerOnActive();
  }

  void _centerOnActive({bool jump = false}) {
    if (!_controller.hasClients) return;
    final index = _activeIndex;
    if (index < 0 || index >= widget.lyrics.synced.length) return;
    final viewport = _controller.position.viewportDimension;
    final target =
        (index * _lineExtent) - (viewport / 2) + (_lineExtent / 2);
    final max = _controller.position.maxScrollExtent;
    final clamped = target.clamp(0.0, max > 0 ? max : 0.0);
    if (jump) {
      _controller.jumpTo(clamped);
      return;
    }
    _controller.animateTo(
      clamped,
      duration: Motion.cardPress,
      curve: Motion.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: DsLoadingDots(size: 10));
    }
    if (widget.lyrics.instrumental) {
      return DsEmptyState(
        icon: Icons.music_note_outlined,
        title: widget.instrumentalTitle,
        centered: true,
      );
    }
    if (widget.lyrics.isEmpty) {
      return DsEmptyState(
        icon: Icons.lyrics_outlined,
        title: widget.emptyTitle,
        body: widget.emptyBody,
        centered: true,
      );
    }
    if (!widget.lyrics.hasSynced) {
      return _buildPlain();
    }
    return _buildSynced();
  }

  Widget _buildPlain() {
    final theme = Theme.of(context);
    final inactive =
        widget.inactiveColor ?? theme.colorScheme.brandTextSecondary;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) => n is UserScrollNotification
          ? _userScrolling = n.direction != ScrollDirection.idle
          : false,
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s6,
          vertical: AppSpacing.s8,
        ),
        itemCount: widget.lyrics.plain.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s4),
          child: Text(
            widget.lyrics.plain[i],
            style: theme.textTheme.titleMedium?.copyWith(
              color: inactive,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSynced() {
    final theme = Theme.of(context);
    final activeColor = widget.activeColor ?? theme.colorScheme.primary;
    final inactiveColor =
        widget.inactiveColor ?? theme.colorScheme.brandTextSecondary;
    final lines = widget.lyrics.synced;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification) {
          _userScrolling = n.direction != ScrollDirection.idle;
        }
        return false;
      },
      child: Semantics(
        label: widget.emptyTitle,
        liveRegion: true,
        child: ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6,
            vertical: AppSpacing.s7,
          ),
          // The list only reaches this length on the first frame; jump to the
          // active line afterwards so maxScrollExtent settles.
          itemCount: lines.length,
          itemExtent: _lineExtent,
          itemBuilder: (context, i) {
            final line = lines[i];
            final isActive = i == _activeIndex;
            // Past lines sit slightly brighter than upcoming ones, which is
            // what makes a synced lyric readable as it advances.
            final isPast = _activeIndex >= 0 && i < _activeIndex;
            final color = isActive
                ? activeColor
                : inactiveColor.withValues(alpha: isPast ? 0.75 : 0.4);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: line.text.isEmpty || widget.onSeek == null
                  ? null
                  : () {
                      widget.onSeek!(line.timestamp);
                      setState(() => _userScrolling = false);
                      _centerOnActive(jump: true);
                    },
              child: AnimatedScale(
                scale: isActive ? 1.04 : 1.0,
                duration: Motion.cardPress,
                curve: Motion.easeOutCubic,
                child: Center(
                  child: Text(
                    // A bare timestamp is the instrumental break; render a
                    // spacer so the layout height does not jump.
                    line.text.isEmpty ? '\u200B' : line.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: color,
                      height: 1.2,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      shadows: widget.activeColor != null
                          ? const [Shadow(blurRadius: 8, color: Colors.black54)]
                          : null,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
