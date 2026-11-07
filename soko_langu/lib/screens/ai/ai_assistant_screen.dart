import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../extensions/context_tr.dart';
import '../../services/persistent_ai_chat_service.dart';
import '../../services/ai_voice_player.dart';
import '../../models/ai_chat_models.dart';
import '../../app/routes.dart';
import '../../main.dart';
import '../../services/product_search_service.dart';
import '../../services/voice_search_service.dart';
import '../../widgets/staggered_fade_in.dart';
import '../../design_system/tokens/one_ui_tokens.dart';
import 'package:just_audio/just_audio.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final PersistentAiChatService _chat = PersistentAiChatService();
  final ProductSearchService _searcher = ProductSearchService();
  final VoiceSearchService _voice = VoiceSearchService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<AiConversation> _conversations = [];
  String? _activeConversationId;
  List<AiMessage> _messages = [];
  bool _isLoading = false;
  bool _isRecording = false;
  bool _loadingConversations = true;
  bool _hasText = false;
  final FocusNode _inputFocus = FocusNode();
  String? _loadError;
  final Set<String> _playingVoice = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inputFocus.addListener(_refreshInputDecor);
    _controller.addListener(_refreshInputDecor);
    _bootstrap();
  }

  void _refreshInputDecor() {
    if (!mounted) return;
    setState(() => _hasText = _controller.text.trim().isNotEmpty);
  }

  Future<void> _bootstrap() async {
    try {
      final convs = await _chat.listConversations();
      if (!mounted) return;
      setState(() {
        _conversations = convs.items;
        _loadingConversations = false;
      });
      if (convs.items.isNotEmpty) {
        await _openConversation(convs.items.first.conversationId);
      } else {
        await _newChat();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingConversations = false;
          _loadError = e.toString();
        });
      }
    }
  }

  Future<void> _newChat() async {
    try {
      final conv = await _chat.createConversation();
      if (!mounted) return;
      setState(() {
        _conversations = [conv, ..._conversations];
        _activeConversationId = conv.conversationId;
        _messages = [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr("ai_new_chat_failed"))),
        );
      }
    }
  }

  Future<void> _openConversation(String id) async {
    if (id == _activeConversationId && _messages.isNotEmpty) return;
    setState(() {
      _activeConversationId = id;
      _messages = [];
      _isLoading = true;
    });
    try {
      final page = await _chat.listMessages(conversationId: id, limit: 50);
      if (!mounted) return;
      setState(() {
        _messages = page.items;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr("ai_load_failed"))),
        );
      }
    }
  }

  Future<void> _deleteConversation(String id) async {
    final ok = await _confirm(context.tr("ai_delete_chat_title"), context.tr("ai_delete_chat_body"));
    if (ok != true) return;
    try {
      await _chat.deleteConversation(id);
      if (!mounted) return;
      setState(() {
        _conversations.removeWhere((c) => c.conversationId == id);
        if (_activeConversationId == id) {
          _activeConversationId = null;
          _messages = [];
        }
      });
      if (_activeConversationId == null && _conversations.isNotEmpty) {
        await _openConversation(_conversations.first.conversationId);
      } else if (_activeConversationId == null) {
        await _newChat();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr("ai_delete_failed"))),
        );
      }
    }
  }

  Future<bool?> _confirm(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr("cancel"))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr("delete"))),
        ],
      ),
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final started = await _voice.startRecording();
    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr("ai_mic_permission_denied"))),
        );
      }
      return;
    }
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    final locale = AppConfig.of(context).langCode;
    setState(() => _isRecording = false);
    final path = await _voice.stopRecording();
    if (path == null || path.isEmpty) return;
    setState(() => _isLoading = true);
    final transcribed = await _voice.transcribeAudio(path, locale: locale);
    if (transcribed.isEmpty) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr("ai_hear_error"))),
        );
      }
      return;
    }
    await _sendMessage(transcribed);
  }

  bool _isProductQuery(String text) {
    final normalized = text.toLowerCase().trim();
    final greetingTokens = ["hello", "hi", "hujambo", "habari", "mambo", "salamu", "jambo", "hey", "asante", "shukran", "karibu"];
    final trimmed = normalized.replaceAll(RegExp(r"[?!.,\s]+$"), "");
    return !greetingTokens.any((g) => trimmed == g || trimmed.endsWith(" $g"));
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _activeConversationId == null) return;
    final convId = _activeConversationId!;
    _controller.clear();

    final tempUser = AiMessage(
      messageId: "temp-${DateTime.now().millisecondsSinceEpoch}",
      conversationId: convId,
      role: "user",
      content: text,
      createdAt: DateTime.now().toIso8601String(),
      status: "completed",
    );
    setState(() {
      _messages = [..._messages, tempUser];
      _isLoading = true;
    });
    _scrollToBottom();

    String? productContext;
    String catalogStatus = "general";
    if (_isProductQuery(text)) {
      try {
        final products = await _searcher.searchProducts(text);
        if (products.isNotEmpty) {
          productContext = products.map((p) => p.productName).join(", ");
          catalogStatus = "found";
        } else {
          catalogStatus = "notFound";
        }
      } catch (_) {}
    }

    try {
      String? assistantId;
      final buffer = StringBuffer();
      await for (final event in _chat.sendMessageStream(
        conversationId: convId,
        text: text,
        productContext: productContext,
        catalogStatus: catalogStatus,
        locale: AppConfig.of(context).langCode,
      )) {
        final type = event["event"]?.toString();
        final data = event["data"] as Map<String, dynamic>? ?? {};
        if (type == "start") {
          assistantId = data["assistantMessageId"]?.toString();
          final userMsg = data["userMessage"];
          if (userMsg is Map<String, dynamic>) {
            final serverUser = AiMessage.fromJson(userMsg);
            setState(() {
              _messages = _messages.map((m) => m.messageId == tempUser.messageId ? serverUser : m).toList();
            });
          }
        } else if (type == "delta") {
          buffer.write(data["text"]?.toString() ?? "");
          setState(() {
            final idx = _messages.indexWhere((m) => m.messageId == assistantId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(content: buffer.toString(), status: "generating");
            } else if (assistantId != null) {
              _messages = [
                ..._messages,
                AiMessage(
                  messageId: assistantId,
                  conversationId: convId,
                  role: "assistant",
                  content: buffer.toString(),
                  createdAt: DateTime.now().toIso8601String(),
                  status: "generating",
                ),
              ];
            }
          });
          _scrollToBottom();
        } else if (type == "done") {
          final content = data["content"]?.toString() ?? buffer.toString();
          setState(() {
            final idx = _messages.indexWhere((m) => m.messageId == assistantId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(content: content, status: "completed");
            }
            _isLoading = false;
          });
          _scrollToBottom();
        } else if (type == "error") {
          final partial = data["partial"]?.toString() ?? buffer.toString();
          setState(() {
            final idx = _messages.indexWhere((m) => m.messageId == assistantId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(content: partial, status: "failed");
            }
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr("ai_generic_error"))),
        );
      }
    }
    _scrollToBottom();
  }

  Future<void> _retryMessage(AiMessage msg) async {
    if (msg.isUser) return;
    final idx = _messages.indexOf(msg);
    if (idx <= 0) return;
    final userMsg = _messages[idx - 1];
    if (!userMsg.isUser) return;
    setState(() {
      _messages.removeAt(idx);
    });
    await _sendMessage(userMsg.content);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isRecording) {
      _stopRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 900;
    
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        centerTitle: !isWide,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.auto_awesome, color: cs.onPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            Text(context.tr("ai_dalali"), style: const TextStyle(fontFamily: "Space Grotesk", fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.tr("settings"),
            onPressed: () => context.push(AppRoutes.aiSettings),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: context.tr("ai_new_chat"),
            onPressed: _newChat,
          ),
          const SizedBox(width: 8),
        ],
        elevation: 0,
        backgroundColor: cs.surface,
      ),
      drawer: isWide ? null : _buildDrawer(cs),
      body: _loadingConversations
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : _loadError != null
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: cs.error),
                    const SizedBox(height: 16),
                    Text(_loadError!, style: TextStyle(color: cs.onSurface)),
                  ],
                ))
              : Row(
                  children: [
                    if (isWide) _buildSidebar(cs),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: _messages.isEmpty && !_isLoading
                                ? _buildWelcomeScreen(cs)
                                : ListView.builder(
                                    controller: _scrollController,
                                    padding: EdgeInsets.symmetric(horizontal: isWide ? 120 : 16, vertical: 20),
                                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (_isLoading && index == _messages.length) {
                                        return Padding(
                                          padding: const EdgeInsets.only(left: 8, bottom: 16),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(Icons.auto_awesome, color: cs.onPrimary, size: 16),
                                              ),
                                              const SizedBox(width: 12),
                                              const _TypingIndicator(),
                                            ],
                                          ),
                                        );
                                      }
                                      final msg = _messages[index];
                                      return StaggeredFadeIn(
                                        index: index,
                                        child: msg.isUser
                                            ? _buildUserBubble(msg, cs)
                                            : _buildAiBubble(msg, cs),
                                      );
                                    },
                                  ),
                          ),
                          _buildInputBar(cs, isWide),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildWelcomeScreen(ColorScheme cs) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary.withValues(alpha: 0.2), cs.secondary.withValues(alpha: 0.2)]),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_awesome, color: cs.onPrimary, size: 40),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.tr("ai_dalali"),
              style: TextStyle(fontFamily: "Space Grotesk", fontSize: isWide ? 32 : 28, fontWeight: FontWeight.w800, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "Msaidizi wako wa AI kwa Soko Vibe",
              style: TextStyle(fontSize: isWide ? 16 : 14, color: cs.onSurface.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip(cs, "Nipe bidhaa za bei nafuu", Icons.search),
                _buildSuggestionChip(cs, "Nisaidie kupata muuzaji mzuri", Icons.storefront),
                _buildSuggestionChip(cs, "Nieleze kuhusu manunuzi", Icons.shopping_bag_outlined),
                _buildSuggestionChip(cs, "Nisaidie kuandika bidhaa", Icons.edit_outlined),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(ColorScheme cs, String text, IconData icon) {
    return InkWell(
      onTap: () => _sendMessage(text),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: cs.onSurface, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(ColorScheme cs) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(right: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _newChat,
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.tr("ai_new_chat")),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.history, size: 18, color: cs.onSurface.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Text(context.tr("ai_recent_chats"), style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.9))),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _conversations.length,
                itemBuilder: (context, index) {
                  final conv = _conversations[index];
                  final isActive = conv.conversationId == _activeConversationId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: isActive ? cs.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => _openConversation(conv.conversationId),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 16, color: isActive ? cs.primary : cs.onSurface.withValues(alpha: 0.6)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      conv.title.isEmpty ? context.tr("ai_untitled") : conv.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, color: cs.onSurface),
                                    ),
                                    if (conv.lastMessagePreview.isNotEmpty)
                                      Text(
                                        conv.lastMessagePreview,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6)),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
                                onPressed: () => _deleteConversation(conv.conversationId),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(ColorScheme cs) {
    return Drawer(
      child: _buildSidebar(cs),
    );
  }

  Widget _buildInputBar(ColorScheme cs, bool isWide) {
    return Container(
      padding: EdgeInsets.fromLTRB(isWide ? 120 : 16, 12, isWide ? 120 : 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _toggleRecording,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? cs.error.withValues(alpha: 0.1) : Colors.transparent,
                  ),
                  child: Icon(_isRecording ? Icons.mic_rounded : Icons.mic_none_rounded, color: _isRecording ? cs.error : cs.onSurface.withValues(alpha: 0.7), size: 22),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _sendMessage,
                  style: TextStyle(color: cs.onSurface, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Uliza chochote...",
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.send_rounded, color: cs.onPrimary, size: 18),
                  onPressed: () => _sendMessage(_controller.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserBubble(AiMessage msg, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Text(msg.content, style: TextStyle(color: cs.onPrimary, fontSize: 14, height: 1.6)),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 16,
            backgroundColor: cs.primaryContainer,
            child: Icon(Icons.person, size: 18, color: cs.onPrimaryContainer),
          ),
        ],
      ),
    );
  }

  Widget _buildAiBubble(AiMessage msg, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome, color: cs.onPrimary, size: 16),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                  ),
                  child: msg.isGenerating && msg.content.isEmpty
                      ? const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: _TypingIndicator())
                      : Text(msg.content, style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.7)),
                ),
                if (msg.isFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionButton(cs, Icons.refresh, () => _retryMessage(msg), tooltip: "Jaribu tena"),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(ColorScheme cs, IconData icon, VoidCallback onPressed, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? "",
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: cs.onSurface.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDot(cs, 0),
        const SizedBox(width: 4),
        _buildDot(cs, 1),
        const SizedBox(width: 4),
        _buildDot(cs, 2),
      ],
    );
  }

  Widget _buildDot(ColorScheme cs, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: Duration(milliseconds: 600 + index * 200),
      builder: (context, value, child) {
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: value),
            shape: BoxShape.circle,
          ),
        );
      },
      onEnd: () {},
    );
  }
}
