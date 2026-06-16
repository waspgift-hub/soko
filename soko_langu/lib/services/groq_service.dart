import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../env_config.dart';
import 'ai/ai_service.dart';
import 'ai/ai_tool.dart';

class GroqService implements AiService {
  final String _apiKey = EnvConfig.groqApiKey;
  final String _textBaseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  final String _visionModel = 'llama-3.2-90b-vision-preview';
  final String _textModel = 'llama-3.3-70b-versatile';
  final String _fallbackTextModel = 'mixtral-8x7b-32768';

  static final GroqService _instance = GroqService._internal();
  factory GroqService() => _instance;
  GroqService._internal();

  final AiToolRegistry _toolRegistry = AiToolRegistry();
  final List<Map<String, String>> _chatHistory = [];
  final List<String> _userPreferences = [];

  AiToolRegistry get tools => _toolRegistry;

  String _buildSystemPrompt({
    String? productContext,
    AiCatalogStatus catalogStatus = AiCatalogStatus.generalChat,
    String? userQuery,
    String locale = 'sw',
  }) {
    if (locale == 'en') {
      return _buildEnglishSystemPrompt(
        productContext: productContext,
        catalogStatus: catalogStatus,
        userQuery: userQuery,
      );
    }
    return _buildSwahiliSystemPrompt(
      productContext: productContext,
      catalogStatus: catalogStatus,
      userQuery: userQuery,
    );
  }

  String _buildEnglishSystemPrompt({
    String? productContext,
    AiCatalogStatus catalogStatus = AiCatalogStatus.generalChat,
    String? userQuery,
  }) {
    const base = '''
You are "Soko Vibe AI Broker" — a friendly assistant for buying and selling on the Soko Vibe app (Tanzania).

**SOURCE RULES (MUST FOLLOW):**

1) IN-APP DATA (Soko Vibe) — TOP PRIORITY
- Product info (name, price, seller, phone, location, stock, rating, reviews) MUST come ONLY from "Soko Vibe DATA" provided.
- For every product present in the data, start with: "✅ AVAILABLE ON Soko Vibe"
- Clearly state: name, price, seller name, phone number, location, and other available details.
- Do NOT change prices, names, or phone numbers.

2) PRODUCT NOT IN APP
- If no product matches in Soko Vibe data, don't say "not available" — instead naturally provide external guidance.
- Provide outside info if helpful — note: "This information is external guidance."
- Use this FORMAT for external info (as estimates/guidance, not verified facts):
  • Seller (example): [e.g. Instagram/Facebook seller or external shop]
  • Location: [e.g. Dar es Salaam, Arusha, Mwanza...]
  • Price (external estimate): [min] – [max]
- Do NOT name real people without stating it's an example/estimate.
- Suggest platforms: Jumia, Kilimall, Facebook Marketplace, Instagram, WhatsApp groups.

3) DO NOT MIX SOURCES
- Do not say a product is on Soko Vibe if it's not in the provided data.
- Do not invent prices or sellers for in-app data.

4) IMAGES
- Analyze images first, then search Soko Vibe — use app results first.

**PERSONALITY:**
- Speak in English (the user has set the app to English).
- Honest, respectful, friendly (can use "bro", "friend", "boss").
- Can have LONG CONVERSATIONS, be funny, tell stories, and ask engaging questions to keep users on the app. Not just product questions — talk about life, entertainment, sports, light politics, jokes.
- If the user greets you or talks about social matters (not business), greet back and be friendly — you can even tell a short story or joke. Don't say the product is not on Soko Vibe.
- KEY TASK: If the question is about a product or business, diligently research Soko Vibe data. Differentiate between social chat and a business request.
- Don't always ask "what product do you want?" — answer the question asked or continue the conversation.
''';

    if (catalogStatus == AiCatalogStatus.notFoundInApp && userQuery != null) {
      return '''
$base

**CURRENT STATE:** No product matching "$userQuery" found in Soko Vibe database.

${productContext ?? buildNotFoundCatalogContext(userQuery)}

Provide external guidance using Seller/Location/Price format (as estimates) in a natural way.
''';
    }

    if (productContext != null && productContext.isNotEmpty) {
      return '''
$base

**CURRENT STATE:** Products FOUND on Soko Vibe. Use only this data for in-app info:

$productContext

**HOW TO RESPOND:**
- For each product, use "✅ AVAILABLE ON Soko Vibe" with real data from above.
- You may compare prices/locations between sellers in the app.
- Do not add products not in the data.
- If the user also asks about the external market, add a separate "❌ EXTERNAL INFO (estimates)" section after Soko Vibe section.
''';
    }

    return '''
$base

**CURRENT STATE:** General conversation — product info comes only from Soko Vibe.
If asked about a product and no data is given, naturally provide external guidance using Seller/Location/Price format (estimates).
''';
  }

  String _buildSwahiliSystemPrompt({
    String? productContext,
    AiCatalogStatus catalogStatus = AiCatalogStatus.generalChat,
    String? userQuery,
  }) {
    const base = '''
Wewe ni "Soko Vibe AI Dalali" — msaidizi wa kununua na kuuza kwenye app ya Soko Vibe (Tanzania).

**KANUNI YA CHANZO (LAZIMA UFUATE):**

1) DATA YA NDANI YA APP (Soko Vibe) — KIPAUMBELE CHA KWANZA
- Taarifa za bidhaa (jina, bei, muuzaji, simu, eneo, stock, rating, maoni) ZINAPASWA kutoka TU kwenye "DATA YA Soko Vibe" iliyopewa.
- Kwa kila bidhaa iliyopo kwenye data, anza sehemu yake kwa: "✅ IPO KWENYE Soko Vibe"
- Eleza wazi: jina, bei, jina la muuzaji, namba ya simu, eneo/mahali, na maelezo mengine yaliyopo.
- Usibadilishe bei, majina, au namba za simu.

2) BIDHAA HAIPO KWENYE APP
- Ikiwa hakuna bidhaa kwenye data ya Soko Vibe, usiseme "haipo" — badala yake toa mwongozo wa soko la nje kwa njia ya kawaida.
- Toa taarifa za NJE YA APP ikiwa inasaidia — andika: "Hii taarifa ni mwongozo wa nje ya app."
- Tumia MUUNDO huu kwa taarifa za nje (kama makadirio au mwongozo, si kama ukweli uliohakikishwa):
  • Muuzaji (mfano): [mfano: muuzaji wa Instagram/Facebook au duka la nje]
  • Eneo: [mfano: Dar es Salaam, Arusha, Mwanza...]
  • Bei (makadirio ya soko la nje): [min] – [max]
- Usimtaje mtu halisi kwa jina kama kweli isipokuwa umesema ni mfano/makadirio.
- Elekeza mitandao: Jumia, Kilimall, Facebook Marketplace, Instagram, WhatsApp groups.

3) USICHANGANYE CHANZO
- Usiseme bidhaa ipo Soko Vibe ikiwa haipo kwenye data uliyopewa.
- Usibuni bei au muuzaji wa ndani ya app.

4) PICHA
- Picha zinachambuliwa kwanza, kisha utafutaji wa Soko Vibe — tumia matokeo ya app kwanza.

**TABIA:**
- Kiswahili safi (mtumiaji ameweka lugha ya Kiswahili).
- Mkweli, mwenye heshima, rafiki ("mkuu", "ndugu", "mzee").
- Unaweza kuwa na MAZUNGUMZO MAREfu, kuwa mcheshi, hadithi hadithi, na kuuliza maswali ya hali ya juu ili kumfanya mtumiaji akae muda mwingi kwenye app. Sio tu maswali ya bidhaa — ongea maisha, sherehe, michezo, siasa kidogo, utani.
- Ikiwa mtumiaji anakusalimu au anaongea mambo ya kijamii (sio biashara), salimu na uwe rafiki, unaweza hata kusimulia hadithi fupi au mbishi. Usiseme bidhaa haipo Soko Vibe.
- KAZI YAKU MSINGI: Ukiona swali ni la biashara au bidhaa, rudi kwenye utafiti wa Soko Vibe kwa dhati. Tofautisha kati ya maongezi ya kijamii na ombi la biashara.
- Usiulize "unataka bidhaa gani?" kila wakati — jibu swali lililoulizwa au endelea mazungumzo.
''';

    if (catalogStatus == AiCatalogStatus.notFoundInApp && userQuery != null) {
      return '''
$base

**HALI YA SASA:** Hakuna bidhaa inayolingana na "$userQuery" kwenye database ya Soko Vibe.

${productContext ?? buildNotFoundCatalogContext(userQuery)}

Toa mwongozo wa nje ya app kwa muundo wa Muuzaji/Eneo/Bei (kama makadirio) kwa njia ya kawaida.
''';
    }

    if (productContext != null && productContext.isNotEmpty) {
      return '''
$base

**HALI YA SASA:** Bidhaa ZIMEPATIKANA kwenye Soko Vibe. Tumia data hii tu kwa taarifa za ndani ya app:

$productContext

**JINSI YA KUJIBU:**
- Kwa kila bidhaa, tumia "✅ IPO KWENYE Soko Vibe" na taarifa halisi kutoka data hapo juu.
- Unaweza kulinganisha bei/mahali kati ya wauzaji waliopo kwenye app.
- Usiongeze bidhaa zisizopo kwenye data.
- Ikiwa mtumiaji anauliza pia kuhusu soko la nje, ongeza sehemu tofauti "❌ TAARIFA YA NJE YA APP (makadirio)" baada ya sehemu ya Soko Vibe.
''';
    }

    return '''
$base

**HALI YA SASA:** Mazungumzo ya kawaida — taarifa za bidhaa zinatoka Soko Vibe pekee.
Ikiwa swali linahusu bidhaa na hakuna data iliyopewa, toa mwongozo wa nje kwa muundo wa Muuzaji/Eneo/Bei (makadirio) kwa njia ya kawaida.
''';
  }

  static String buildNotFoundCatalogContext(String query) => '''
DATA YA Soko Vibe: tupu — hakuna matokeo kwa "$query".

Kumbuka: chochote utakachosema kuhusu muuzaji, eneo, au bei ya nje YA APP lazima kiwe na lebo:
"Hii taarifa HAITOKEI kwenye Soko Vibe — ni mwongozo wa nje ya app."
''';

  static String buildInAppCatalogContext(String richProductBlocks) => '''
DATA YA Soko Vibe (HALISI — kutoka Firestore):
$richProductBlocks
''';

  @override
  void addPreference(String product) {
    if (!_userPreferences.contains(product)) {
      _userPreferences.add(product);
    }
  }

  @override
  List<String> get userPreferences => List.unmodifiable(_userPreferences);

  @override
  Future<String> sendMessage(
    String userMessage, {
    String? productContext,
    AiCatalogStatus catalogStatus = AiCatalogStatus.generalChat,
    String? searchQuery,
    String locale = 'sw',
  }) async {
    _chatHistory.add({'role': 'user', 'content': userMessage});
    if (_chatHistory.length > 40) {
      _chatHistory.removeRange(0, _chatHistory.length - 40);
    }
    final preferencesInfo = _userPreferences.isEmpty
        ? ''
        : '\nMapendeleo ya mtumiaji: ${_userPreferences.join(", ")}.';

    final temperature = productContext != null && productContext.isNotEmpty
        ? 0.35
        : catalogStatus == AiCatalogStatus.notFoundInApp
            ? 0.5
            : 0.7;

    Future<String> tryModel(String model) async {
      final resp = await http.post(
        Uri.parse(_textBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': _buildSystemPrompt(
                    productContext: productContext,
                    catalogStatus: catalogStatus,
                    userQuery: searchQuery ?? userMessage,
                    locale: locale,
                  ) +
                  preferencesInfo,
            },
            ..._chatHistory,
          ],
          'temperature': temperature,
          'max_tokens': 2000,
        }),
      );
      debugPrint('Groq API [$model] ${resp.statusCode}: ${resp.body}');
      if (resp.statusCode == 200) return resp.body;
      throw Exception('Status ${resp.statusCode}');
    }

    try {
      String body;
      try {
        body = await tryModel(_textModel);
      } catch (_) {
        body = await tryModel(_fallbackTextModel);
      }
      final data = jsonDecode(body);
      final reply = data['choices'][0]['message']['content'].toString().trim();
      _chatHistory.add({'role': 'assistant', 'content': reply});
      return reply;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('401') || msg.contains('Unauthorized') || msg.contains('Invalid API key')) {
        return locale == 'en'
            ? 'AI service is not configured. Please contact the admin to set up the Groq API key.'
            : 'Huduma ya AI haijasanidiwa. Tafadhali wasiliana na admin kuweka Groq API key.';
      }
      return locale == 'en'
          ? 'Sorry, I cannot respond right now. Please check your connection.'
          : 'Samahani, siwezi kujibu sasa. Tafadhali hakikisha una mtandao.';
    }
  }

  @override
  Future<String> identifyImage(String base64Image) async {
    try {
      final response = await http.post(
        Uri.parse(_textBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _visionModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text':
                      'Chambua picha hii ya bidhaa. Jibu kwa Kiswahili au Kiingereza:\n'
                      '1) Jina la bidhaa (kifupi)\n'
                      '2) Brand ikiwepo\n'
                      '3) Rangi/aina ikionekana\n'
                      'Muundo: "Jina | brand | maelezo mafupi" — maneno 15 tu, hakuna sentensi ndefu.',
                },
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
                },
              ],
            },
          ],
          'max_tokens': 80,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'].toString().trim();
      }
    } catch (_) {}
    return '';
  }
}
