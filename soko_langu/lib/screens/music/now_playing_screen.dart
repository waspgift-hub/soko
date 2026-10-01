import 'package:flutter/material.dart';

import '../../extensions/context_tr.dart';
import '../../widgets/profile_media_section.dart';

/// Full now-playing screen. Renders whatever the shared session is playing
/// (on-device songs, YouTube results, or a seller queue) through the same
/// inline player, so playback never restarts on navigation.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('now_playing'))),
      body: const SafeArea(
        child: SingleChildScrollView(
          child: SessionMediaPlayer(items: null, sellerId: ''),
        ),
      ),
    );
  }
}
