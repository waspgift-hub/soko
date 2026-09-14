import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/soko_media_item.dart';
import '../../services/media_library_service.dart';

/// Displays the artwork for a [SokoMediaItem] — real album art when available,
/// or a green placeholder disc with the item's title initials and a music note.
class SokoArtwork extends StatefulWidget {
  const SokoArtwork({
    super.key,
    required this.item,
    this.size = 56,
    this.radius,
  });

  final SokoMediaItem? item;
  final double size;
  final double? radius;

  @override
  State<SokoArtwork> createState() => _SokoArtworkState();
}

class _SokoArtworkState extends State<SokoArtwork> {
  String? _artUri;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _tryResolve();
  }

  @override
  void didUpdateWidget(covariant SokoArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item?.id != oldWidget.item?.id) _tryResolve();
  }

  Future<void> _tryResolve() async {
    final item = widget.item;
    if (item == null) {
      if (mounted) setState(() { _resolved = true; });
      return;
    }
    // Explicit artUri on the item (loaded earlier) — use it directly.
    if (item.artUri != null && item.artUri!.isNotEmpty) {
      if (mounted) setState(() { _artUri = item.artUri; _resolved = true; });
      return;
    }
    // Resolve lazily from the library service (downloads & caches on disk).
    try {
      final uri = await MediaLibraryService.instance.artworkUri(item);
      if (mounted && uri != _artUri) {
        setState(() { _artUri = uri; _resolved = true; });
      }
    } catch (_) {
      if (mounted && !_resolved) setState(() => _resolved = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius ?? widget.size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_artUri != null && _artUri!.isNotEmpty) {
      try {
        final path = Uri.parse(_artUri!).path;
        final file = File(path);
        return Image.file(
          file,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _placeholder(),
        );
      } catch (_) {
        return _placeholder();
      }
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final item = widget.item;
    final title = item?.title ?? '';
    final initials = _initials(title);
    return Container(
      decoration: BoxDecoration(
        // Solid brand-green disc — keeps brand identity even without art.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF009624), Color(0xFF00C853)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C853).withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            initials,
            style: TextStyle(
              color: Colors.black,
              fontSize: widget.size * 0.32,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          Positioned(
            bottom: widget.size * 0.1,
            child: Icon(
              Icons.music_note_rounded,
              color: Colors.black.withValues(alpha: 0.15),
              size: widget.size * 0.4,
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || text.isEmpty) return '♪';
    if (words.length == 1) return words[0][0].toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}