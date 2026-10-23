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
  String? _loadError;
  final Set<String> _playingVoice = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
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
          SnackBar(content: Text(context.tr('ai_new_chat_failed'))),
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
          SnackBar(content: Text(context.tr('ai_load_failed'))),
        );
      }
    }
  }

  Future<void> _deleteConversation(String id) async {
    final ok = await _confirm(context.tr('ai_delete_chat_title'), context.tr('ai_delete_chat_body'));
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
          SnackBar(content: Text(context.tr('ai_delete_failed'))),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('delete'))),
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
          SnackBar(content: Text(context.tr('ai_mic_permission_denied'))),
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
          SnackBar(content: Text(context.tr('ai_hear_error'))),
        );
      }
      return;
    }
    await _sendMessage(transcribed);
  }

  bool _isProductQuery(String text) {
    final normalized = text.toLowerCase().trim();
    final greetingTokens = ['hello', 'hi', 'hujambo', 'habari', 'mambo', 'salamu', 'jambo', 'hey', 'asante', 'shukran', 'karibu'];
    final trimmed = normalized.replaceAll(RegExp(r'[?!.,\s]+$'), '');
    return !greetingTokens.any((g) => trimmed == g || trimmed.endsWith(' $g'));
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _activeConversationId == null) return;
    final convId = _activeConversationId!;
    _controller.clear();

    // Optimistic user message
    final tempUser = AiMessage(
      messageId: 'temp-${DateTime.now().millisecondsSinceEpoch}',
      conversationId: convId,
      role: 'user',
      content: text,
      createdAt: DateTime.now().toIso8601String(),
      status: 'completed',
    );
    setState(() {
      _messages = [..._messages, tempUser];
      _isLoading = true;
    });
    _scrollToBottom();

    // Product search context (best-effort, non-blocking for the chat)
    String? productContext;
    String catalogStatus = 'general';
    if (_isProductQuery(text)) {
      try {
        final products = await _searcher.searchProducts(text);
        if (products.isNotEmpty) {
          productContext = products.map((p) => p.productName).join(', ');
          catalogStatus = 'found';
        } else {
          catalogStatus = 'notFound';
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
        final type = event['event']?.toString();
        final data = event['data'] as Map<String, dynamic>? ?? {};
        if (type == 'start') {
          assistantId = data['assistantMessageId']?.toString();
          // Replace temp user message with server's version
          final userMsg = data['userMessage'];
          if (userMsg is Map<String, dynamic>) {
            final serverUser = AiMessage.fromJson(userMsg);
            setState(() {
              _messages = _messages.map((m) => m.messageId == tempUser.messageId ? serverUser : m).toList();
            });
          }
        } else if (type == 'delta') {
          buffer.write(data['text']?.toString() ?? '');
          // Update or create assistant message in list
          setState(() {
            final idx = _messages.indexWhere((m) => m.messageId == assistantId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(content: buffer.toString(), status: 'generating');
            } else if (assistantId != null) {
              _messages = [
                ..._messages,
                AiMessage(
                  messageId: assistantId,
                  conversationId: convId,
                  role: 'assistant',
                  content: buffer.toString(),
                  createdAt: DateTime.now().toIso8601String(),
                  status: 'generating',
                ),
              ];
            }
          });
          _scrollToBottom();
        } else if (type == 'done') {
          final content = data['content']?.toString() ?? buffer.toString();
          setState(() {
            final idx = _messages.indexWhere((m) => m.messageId == assistantId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(content: content, status: 'completed');
            }
            _isLoading = false;
          });
          _scrollToBottom();
        } else if (type == 'error') {
          final partial = data['partial']?.toString() ?? buffer.toString();
          setState(() {
            final idx = _messages.indexWhere((m) => m.messageId == assistantId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(content: partial, status: 'failed');
            }
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ai_generic_error'))),
        );
      }
    }
    _scrollToBottom();
  }

  Future<void> _retryMessage(AiMessage msg) async {
    if (msg.isUser) return;
    // Find the user message that preceded this assistant message
    final idx = _messages.indexOf(msg);
    if (idx <= 0) return;
    final userMsg = _messages[idx - 1];
    if (!userMsg.isUser) return;
    // Remove the failed assistant message
    setState(() {
      _messages.removeAt(idx);
    });
    await _sendMessage(userMsg.content);
  }

  Future<void> _playVoice(AiMessage msg) async {
    if (_playingVoice.contains(msg.messageId)) {
      await AiVoicePlayer.instance.stop();
      setState(() => _playingVoice.remove(msg.messageId));
      return;
    }
    // Request voice generation (cached if exists)
    try {
      await _chat.requestVoice(msg.messageId);
    } catch (_) {}
    setState(() => _playingVoice.add(msg.messageId));
    try {
      await AiVoicePlayer.instance.play(msg.messageId, _chat);
      // Listen for completion
      AiVoicePlayer.instance.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _playingVoice.remove(msg.messageId));
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _playingVoice.remove(msg.messageId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ai_voice_unavailable'))),
        );
      }
    }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ai_dalali'), style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.aiSettings),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _newChat,
            tooltip: context.tr('ai_new_chat'),
          ),
        ],
      ),
      drawer: _buildDrawer(cs),
      body: _loadingConversations
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Text(_loadError!))
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: _messages.length + (_isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isLoading && index == _messages.length) {
                            return const _TypingIndicator();
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
                    _buildInputBar(cs),
                  ],
                ),
    );
  }

  Widget _buildDrawer(ColorScheme cs) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.smart_toy_outlined, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(context.tr('ai_recent_chats'), style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600, fontSize: 16)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(context.tr('ai_new_chat')),
              onTap: () {
                Navigator.pop(context);
                _newChat();
              },
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _conversations.length,
                itemBuilder: (context, index) {
                  final conv = _conversations[index];
                  final isActive = conv.conversationId == _activeConversationId;
                  return ListTile(
                    selected: isActive,
                    title: Text(conv.title.isEmpty ? context.tr('ai_untitled') : conv.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(conv.lastMessagePreview, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => _deleteConversation(conv.conversationId),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openConversation(conv.conversationId);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.05)))),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              onTap: _toggleRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording ? cs.error : cs.onSurface.withValues(alpha: 0.06),
                ),
                child: Icon(_isRecording ? Icons.mic_rounded : Icons.mic_none_rounded, color: _isRecording ? cs.onError : cs.onSurface.withValues(alpha: 0.6), size: 20),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: context.tr('ai_chat_hint'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.05))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.05))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.3))),
                  filled: true,
                  fillColor: cs.onSurface.withValues(alpha: 0.04),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              child: IconButton(
                icon: Icon(Icons.send_rounded, color: cs.onPrimary, size: 18),
                onPressed: () => _sendMessage(_controller.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserBubble(AiMessage msg, ColorScheme cs) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(4)),
          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
        ),
        child: Text(msg.content, style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.4)),
      ),
    );
  }

  Widget _buildAiBubble(AiMessage msg, ColorScheme cs) {
    final isPlaying = _playingVoice.contains(msg.messageId);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.04),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(4), bottomRight: Radius.circular(20)),
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 12, color: cs.primary),
                const SizedBox(width: 4),
                Text(context.tr('ai_label'), style: TextStyle(fontFamily: 'JetBrains Mono', color: cs.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (msg.isCompleted) ...[
                  IconButton(
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 16),
                    onPressed: () => _playVoice(msg),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () {
                      // Clipboard copy
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
                if (msg.isFailed)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16),
                    onPressed: () => _retryMessage(msg),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (msg.isGenerating && msg.content.isEmpty)
              const _TypingIndicator()
            else
              Text(msg.content, style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 20, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
  }
}