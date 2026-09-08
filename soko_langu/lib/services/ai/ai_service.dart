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
DATA YA SOKO VIBE (HALISI — kutoka Firestore):
$richProductBlocks
''';

  static String buildNotFoundCatalogContext(String query) => '''
DATA YA SOKO VIBE: tupu — hakuna matokeo kwa "$query".

Kumbuka: chochote utakachosema kuhusu muuzaji, eneo, au bei ya nje YA APP lazima kiwe na lebo:
"Hii taarifa HAITOKEI kwenye Soko Vibe — ni mwongozo wa nje ya app."
''';

  Future<String> sendMessage(
    String userMessage, {
    String? productContext,
    AiCatalogStatus catalogStatus = AiCatalogStatus.generalChat,
    String? searchQuery,
    String locale = 'sw',
  });

  /// Generates a COMPACT, DB-grounded summary of a search result set so the
  /// search screen can show "AI found N relevant products · Best matches…"
  /// above the results (spec §8/§9/§62). [groundedContext] is the raw catalog
  /// data the model may use; it must never invent facts beyond it.
  Future<String> generateSearchSummary({
    required String query,
    required String groundedContext,
    required int total,
    String locale = 'sw',
  });

  Future<String> identifyImage(String base64Image);

  void addPreference(String product);

  List<String> get userPreferences;
}
