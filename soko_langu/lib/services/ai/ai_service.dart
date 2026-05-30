enum AiCatalogStatus { foundInApp, notFoundInApp, generalChat }

abstract class AiService {
  static AiService? _instance;
  static AiService get instance {
    if (_instance == null) {
      throw StateError('AiService not initialized. Call AiService.initialize() first.');
    }
    return _instance!;
  }

  static void initialize(AiService service) {
    _instance = service;
  }

  static String buildInAppCatalogContext(String richProductBlocks) => '''
DATA YA SOKO LANGU (HALISI — kutoka Firestore):
$richProductBlocks
''';

  static String buildNotFoundCatalogContext(String query) => '''
DATA YA SOKO LANGU: tupu — hakuna matokeo kwa "$query".

Kumbuka: chochote utakachosema kuhusu muuzaji, eneo, au bei ya nje YA APP lazima kiwe na lebo:
"Hii taarifa HAITOKEI kwenye Soko Langu — ni mwongozo wa nje ya app."
''';

  Future<String> sendMessage(
    String userMessage, {
    String? productContext,
    AiCatalogStatus catalogStatus = AiCatalogStatus.generalChat,
    String? searchQuery,
    String locale = 'sw',
  });

  Future<String> identifyImage(String base64Image);

  void addPreference(String product);

  List<String> get userPreferences;
}
