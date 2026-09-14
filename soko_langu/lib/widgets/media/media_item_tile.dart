import 'package:flutter/material.dart';
import '../../models/soko_media_item.dart';
import '../../theme/app_themes.dart';
import 'soko_artwork.dart';

/// Standard list tile for a [SokoMediaItem] with artwork, title, artist,
/// optional duration and an [active] highlight when the track is playing.
class MediaItemTile extends StatelessWidget {
  const MediaItemTile({
    super.key,
    required this.item,
    this.onTap,
    this.active = false,
  });

  final SokoMediaItem item;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brand = SokoColors.of(context);
    return ListTile(
      onTap: onTap,
      leading: SokoArtwork(item: item, size: 44, radius: 8),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: active ? brand.commerce : cs.onSurface,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: item.subtitle.isNotEmpty
          ? Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            )
          : null,
      trailing: item.duration > Duration.zero
          ? Text(
              _fmt(item.duration),
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            )
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      dense: true,
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}