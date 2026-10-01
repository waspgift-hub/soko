import 'package:flutter/material.dart';

import '../../extensions/context_tr.dart';
import '../../services/profile_media_session.dart';
import '../../widgets/profile_media_section.dart';
import 'audio_player_screen.dart';

/// Full now-playing screen. Audio queues get the artwork/lyrics player; video
/// and YouTube queues stay on the inline player, which already owns the
/// WebView/video surface. Both read the shared session, so navigating here
/// never restarts playback.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final media = ProfileMediaSession.instance.controller;
    return StreamBuilder<int>(
      stream: media.indexStream,
      initialData: media.index,
      builder: (context, _) => StreamBuilder(
        stream: media.stateStream,
        builder: (context, _) => media.isAudioEngine
            ? const AudioPlayerScreen()
            : Scaffold(
                appBar: AppBar(title: Text(context.tr('now_playing'))),
                body: const SafeArea(
                  child: SingleChildScrollView(
                    child: SessionMediaPlayer(items: null, sellerId: ''),
                  ),
                ),
              ),
      ),
    );
  }
}