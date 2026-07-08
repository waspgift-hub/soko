import 'package:flutter/material.dart';

class _ColorResult {
  final Color vibrant;
  final Color muted;
  final Color darkVibrant;
  _ColorResult({required this.vibrant, required this.muted, required this.darkVibrant});
}

class MusicColorService {
  Future<_ColorResult> extractColors(String imageUrl) async {
    return _ColorResult(vibrant: const Color(0xFF40916C), muted: const Color(0xFF2D6A4F), darkVibrant: const Color(0xFF1B4332));
  }

  Future<Color> extractDominantColor(String imageUrl) async {
    return const Color(0xFF40916C);
  }

  Future<Map<int, Color>> extractPalette(String imageUrl) async {
    return {};
  }
}
