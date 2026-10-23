import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/persistent_ai_chat_service.dart';

/// Plays AI voice audio from the backend TTS endpoint.
///
/// Uses just_audio with HTTP headers for auth. The backend streams cached mp3
/// bytes, so playback starts as soon as enough data is buffered.
///
/// Only one instance plays at a time.
class AiVoicePlayer {
  AiVoicePlayer._();
  static final AiVoicePlayer instance = AiVoicePlayer._();

  final AudioPlayer _player = AudioPlayer();
  String? _currentMessageId;
  bool _isPlaying = false;

  String? get currentMessageId => _currentMessageId;
  bool get isPlaying => _isPlaying;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Future<void> play(String messageId, PersistentAiChatService service) async {
    if (_currentMessageId == messageId && _isPlaying) {
      await pause();
      return;
    }

    if (_currentMessageId != null && _currentMessageId != messageId) {
      await stop();
    }

    _currentMessageId = messageId;
    _isPlaying = true;

    try {
      final url = service.voiceUrl(messageId);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) throw Exception('No token');

      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      await _player.play();
    } catch (e) {
      debugPrint('AiVoicePlayer: play failed: $e');
      _isPlaying = false;
      _currentMessageId = null;
      rethrow;
    }
  }

  Future<void> pause() async {
    await _player.pause();
    _isPlaying = false;
  }

  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
    _currentMessageId = null;
  }

  Future<void> replay(String messageId, PersistentAiChatService service) async {
    await stop();
    await play(messageId, service);
  }

  void dispose() {
    _player.dispose();
  }
}