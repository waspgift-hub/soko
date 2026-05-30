import 'ai_service.dart';

class GeminiAiService implements AiService {
  static final GeminiAiService _instance = GeminiAiService._internal();
  factory GeminiAiService() => _instance;
  GeminiAiService._internal();

  final List<String> _userPreferences = [];

  @override
  void addPreference(String product) {
    if (!_userPreferences.contains(product)) {
      _userPreferences.add(product);
    }
  }

  @override
  List<String> get userPreferences => List.unmodifiable(_userPreferences);

  @override
  Future<String> identifyImage(String base64Image) async {
    // TODO: Implement Gemini Vision API
    return '';
  }

  @override
  Future<String> sendMessage(
    String userMessage, {
    String? productContext,
    AiCatalogStatus catalogStatus = AiCatalogStatus.generalChat,
    String? searchQuery,
    String locale = 'sw',
  }) async {
    // TODO: Implement Gemini Generative API
    return 'Gemini haijasanidiwa bado. Tumia Groq kwa sasa.';
  }
}
