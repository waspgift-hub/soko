import 'dart:math' as math;
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';

class SoundIdentity {
  SoundIdentity._();
  static final SoundIdentity instance = SoundIdentity._();
  final AudioPlayer _player = AudioPlayer();
  bool _playedThisProcess = false;

  Future<void> playStartupOnce({required bool enabled}) async {
    if (!enabled || _playedThisProcess) return;
    _playedThisProcess = true;
    try {
      await _player.setAudioSource(_SonicLogoSource(_makeWave()));
      await _player.setVolume(0.22);
      await _player.play();
    } catch (_) { /* Branding audio must never prevent app startup. */ }
  }
  Future<void> dispose() => _player.dispose();

  Uint8List _makeWave() {
    const sampleRate = 22050;
    const seconds = 1.25;
    const samples = (sampleRate * seconds).round();
    final dataBytes = samples * 2;
    final bytes = ByteData(44 + dataBytes);
    void ascii(int offset, String value) { for (var i = 0; i < value.length; i++) { bytes.setUint8(offset + i, value.codeUnitAt(i)); } }
    ascii(0, 'RIFF'); bytes.setUint32(4, 36 + dataBytes, Endian.little); ascii(8, 'WAVE');
    ascii(12, 'fmt '); bytes.setUint32(16, 16, Endian.little); bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little); bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little); bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little); ascii(36, 'data'); bytes.setUint32(40, dataBytes, Endian.little);
    for (var i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final envelope = math.min((t / 0.025).clamp(0.0, 1.0), ((seconds - t) / 0.22).clamp(0.0, 1.0));
      final glide = 440 + 260 * math.sin(math.pi * t / seconds);
      final tone = math.sin(2 * math.pi * glide * t) + 0.34 * math.sin(2 * math.pi * glide * 1.5 * t) + 0.12 * math.sin(2 * math.pi * 110 * t);
      final sample = (tone * envelope * 0.42 * 32767).round().clamp(-32768, 32767);
      bytes.setInt16(44 + i * 2, sample, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}

class _SonicLogoSource extends StreamAudioSource {
  _SonicLogoSource(this._bytes);
  final Uint8List _bytes;
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0; final to = end ?? _bytes.length;
    return StreamAudioResponse(sourceLength: _bytes.length, contentLength: to - from, offset: from, stream: Stream.value(_bytes.sublist(from, to)), contentType: 'audio/wav');
  }
}