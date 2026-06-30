import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../env_config.dart';

class VoiceSearchService {
  static final VoiceSearchService _instance = VoiceSearchService._internal();
  factory VoiceSearchService() => _instance;
  VoiceSearchService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> startRecording() async {
    final hasPerm = await requestPermission();
    if (!hasPerm) return false;

    final dir = Directory.systemTemp;
    final path = '${dir.path}/voice_search_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    _isRecording = true;
    return true;
  }

  Future<String?> stopRecording() async {
    _isRecording = false;
    final path = await _recorder.stop();
    return path;
  }

  Future<String> transcribeAudio(String audioPath, {String locale = 'sw'}) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) return '';

      final uri = Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] =
            'Bearer ${EnvConfig.groqApiKey}'
        ..files.add(await http.MultipartFile.fromPath('file', audioPath))
        ..fields['model'] = 'whisper-large-v3-turbo'
        ..fields['language'] = locale == 'en' ? 'en' : 'sw'
        ..fields['response_format'] = 'json';

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['text'] as String? ?? '';
      }
    } catch (_) {}
    return '';
  }

  Future<void> dispose() async {
    if (_isRecording) {
      await _recorder.stop();
    }
    await _recorder.dispose();
  }
}
