import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../extensions/context_tr.dart';
import '../../services/persistent_ai_chat_service.dart';
import '../../services/agent/agent_service.dart';
import '../../services/agent/agent_models.dart';
import '../../models/ai_chat_models.dart';
import '../../app/routes.dart';
import '../../main.dart';
import '../../utils/responsive.dart';

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> with WidgetsBindingObserver {
  final PersistentAiChatService _chat = PersistentAiChatService();
  final AgentService _agent = AgentService();

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<AiConversation> _conversations = [];
  String? _activeConversationId;
  List<AiMessage> _messages = [];
  List<AgentPendingAction> _pendingActions = [];

  bool _loadingConversations = true;
  bool _isSending = false;
  String? _loadError;
  StreamSubscription<dynamic>? _streamSub;

  bool get _isDesktop => Responsive.isDesktop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _streamSub?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _streamSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _loadPendingActions() async {
    try {
      final actions = await _agent.listActions(status: 'AWAITING_APPROVAL');
      if (!mounted) return;
      setState(() => _pendingActions = actions);
    } catch (_) {}
  }

  Future<void> _newChat() async {
    try {
      final conv = await _chat.createConversation();
      if (!mounted) return;
      setState(() {
        _conversations = [conv, ..._conversations];
        _activeConversationId = conv.conversationId;
        _messages = [];
        _pendingActions = [];
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
      _pendingActions = [];
    });
    try {
      final page = await _chat.listMessages(conversationId: id, limit: 50);
      if (!mounted) return;
      setState(() {
        _messages = page.items;
      });
      await _loadPendingActions();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ai_load_failed'))),
        );
      }
    }
  }

  Future<void> _deleteConversation(String id) async {
    final ok = await _confirm(context.tr('agent_delete_chat_title'), context.tr('agent_delete_chat_body'));
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

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _activeConversationId == null) return;
    final convId = _activeConversationId!;
    _controller.clear();

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
      _isSending = true;
    });
    _scrollToBottom();

    try {
      String? assistantId;
      final buffer = StringBuffer();
      _streamSub = _agent.sendTurnStream(
        conversationId: convId,
        text: text,
        messages: _messages.where((m) => m.messageId != tempUser.messageId).toList(),
        locale: AppConfig.of(context).langCode,
      ).listen(
        (event) {
          if (!mounted) return;
          final type = event.event;
          final data = event.data;

          setState(() {
            if (type == 'start') {
              assistantId = data['assistantMessageId']?.toString();
              final userMsg = data['userMessage'];
              if (userMsg is Map<String, dynamic>) {
                _messages = _messages.map((m) => m.messageId == tempUser.messageId
                    ? AiMessage.fromJson(userMsg)
                    : m).toList();
              }
            } else if (type == 'delta') {
              buffer.write(data['text']?.toString() ?? '');
              _upsertAssistant(assistantId, buffer.toString(), 'generating', convId);
            } else if (type == 'action_proposal') {
              final pending = AgentPendingAction.fromJson(data);
              setState(() => _pendingActions.add(pending));
              _showActionCard(pending);
            } else if (type == 'tool_result') {
              // tool result surfaced via action lifecycle
            } else if (type == 'done') {
              final content = data['content']?.toString() ?? buffer.toString();
              _finalizeAssistant(assistantId, content, 'completed');
              setState(() => _isSending = false);
              _scrollToBottom();
            } else if (type == 'error') {
              final partial = data['partial']?.toString() ?? buffer.toString();
              _finalizeAssistant(assistantId, partial, 'failed');
              setState(() => _isSending = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(data['message']?.toString() ?? context.tr('ai_generic_error'))),
              );
            }
          });
        },
        onError: (e) {
          setState(() => _isSending = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.tr('ai_generic_error'))),
            );
          }
        },
      );
    } catch (e) {
      setState(() => _isSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ai_generic_error'))),
        );
      }
    }
    _scrollToBottom();
  }

  void _upsertAssistant(String? id, String content, String status, String convId) {
    if (id == null) return;
    setState(() {
      final idx = _messages.indexWhere((m) => m.messageId == id);
      if (idx >= 0) {
        _messages[idx] = _messages[idx].copyWith(content: content, status: status);
      } else {
        _messages = [
          ..._messages,
          AiMessage(
            messageId: id,
            conversationId: convId,
            role: 'assistant',
            content: content,
            createdAt: DateTime.now().toIso8601String(),
            status: status,
          ),
        ];
      }
    });
  }

  void _finalizeAssistant(String? id, String content, String status) {
    if (id == null) return;
    setState(() {
      final idx = _messages.indexWhere((m) => m.messageId == id);
      if (idx >= 0) {
        _messages[idx] = _messages[idx].copyWith(content: content, status: status);
      }
    });
  }

  Future<void> _retryMessage(AiMessage msg) async {
    if (msg.isUser) return;
    final idx = _messages.indexOf(msg);
    if (idx <= 0) return;
    final userMsg = _messages[idx - 1];
    if (!userMsg.isUser) return;
    setState(() => _messages.removeAt(idx));
    _sendMessage(userMsg.content);
  }

  Future<void> _approveAction(AgentPendingAction action) async {
    try {
      final updated = await _agent.approveAction(action.actionId);
      if (!mounted) return;
      setState(() {
        _pendingActions = _pendingActions.map((a) => a.actionId == action.actionId ? updated : a).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('agent_action_approved'))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('agent_action_failed'))),
        );
      }
    }
  }

  Future<void> _denyAction(AgentPendingAction action, {String? reason}) async {
    try {
      final updated = await _agent.denyAction(action.actionId, reason: reason);
      if (!mounted) return;
      setState(() {
        _pendingActions = _pendingActions.map((a) => a.actionId == action.actionId ? updated : a).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('agent_action_denied'))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('agent_action_failed'))),
        );
      }
    }
  }

  Future<void> _cancelAction(AgentPendingAction action) async {
    try {
      final updated = await _agent.cancelAction(action.actionId);
      if (!mounted) return;
      setState(() {
        _pendingActions = _pendingActions.map((a) => a.actionId == action.actionId ? updated : a).toList();
      });
    } catch (_) {}
  }

  Future<void> _executeAction(AgentPendingAction action) async {
    try {
      final updated = await _agent.executeAction(action.actionId);
      if (!mounted) return;
      setState(() {
        _pendingActions = _pendingActions.map((a) => a.actionId == action.actionId ? updated : a).toList();
      });
      if (updated.status == AgentActionStatus.succeeded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('agent_action_completed'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(updated.error ?? context.tr('agent_action_failed'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('agent_action_failed'))),
        );
      }
    }
  }

  void _showActionCard(AgentPendingAction action) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AgentActionCard(
        action: action,
        cs: Theme.of(ctx).colorScheme,
        onApprove: () => _approveAction(action),
        onDeny: ({String? reason}) => _denyAction(action, reason: reason),
        onExecute: () => _executeAction(action),
        onCancel: () => _cancelAction(action),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('agent_title'), style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600, fontSize: 18)),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => context.push(AppRoutes.aiSettings)),
          IconButton(icon: const Icon(Icons.add), onPressed: _newChat, tooltip: context.tr('ai_new_chat')),
        ],
      ),
      drawer: _isDesktop ? null : _buildDrawer(cs),
      body: _loadingConversations
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Text(_loadError!))
              : Row(
                  children: [
                    if (_isDesktop) _buildSidebar(cs),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              itemCount: _messages.length + (_isSending ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (_isSending && index == _messages.length) {
                                  return const _AgentTyping();
                                }
                                final msg = _messages[index];
                                return msg.isUser
                                    ? _UserBubble(msg: msg, cs: cs)
                                    : _AgentBubble(msg: msg, cs: cs, onRetry: () => _retryMessage(msg));
                              },
                            ),
                          ),
                          _buildInputBar(cs),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSidebar(ColorScheme cs) {
    return Container(
      width: 320,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: cs.onSurface.withValues(alpha: 0.06)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.smart_toy_outlined, color: cs.primary),
                const SizedBox(width: 8),
                Text(context.tr('agent_recent_chats'), style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600, fontSize: 16)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(context.tr('agent_new_chat')),
            onTap: _newChat,
          ),
          const Divider(height: 1),
          Expanded(
            child: _conversations.isEmpty
                ? Center(child: Text(context.tr('agent_no_chats'), style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)))
                : ListView.builder(
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
                        onTap: () => _openConversation(conv.conversationId),
                      );
                    },
                  ),
          ),
          if (_pendingActions.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(padding: const EdgeInsets.all(16), child: Text(context.tr('agent_pending_actions'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            ..._pendingActions.where((a) => !a.isTerminal).map((a) => ListTile(
              title: Text(a.actionType, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              subtitle: Text(_statusLabel(a.status), style: TextStyle(fontSize: 11, color: _statusColor(a.status, cs))),
              trailing: a.awaitingApproval
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton(onPressed: () => _denyAction(a), child: Text(context.tr('deny'), style: const TextStyle(fontSize: 11))),
                      FilledButton(onPressed: () => _approveAction(a), child: Text(context.tr('approve'), style: const TextStyle(fontSize: 11))),
                    ])
                  : const SizedBox.shrink(),
            )),
          ],
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
                  Text(context.tr('agent_recent_chats'), style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600, fontSize: 16)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(context.tr('agent_new_chat')),
              onTap: () { Navigator.pop(context); _newChat(); },
            ),
            const Divider(height: 1),
            Expanded(
              child: _conversations.isEmpty
                  ? Center(child: Text(context.tr('agent_no_chats')))
                  : ListView.builder(
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
                          onTap: () { Navigator.pop(context); _openConversation(conv.conversationId); },
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.05)))),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: context.tr('agent_chat_hint'),
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
              decoration: BoxDecoration(color: _controller.text.isNotEmpty ? cs.primary : cs.onSurface.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: IconButton(
                icon: Icon(Icons.send_rounded, color: _controller.text.isNotEmpty ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.4), size: 18),
                onPressed: _controller.text.isNotEmpty ? () => _sendMessage(_controller.text) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(AgentActionStatus s) {
    switch (s) {
      case AgentActionStatus.awaitingApproval: return context.tr('agent_awaiting_approval');
      case AgentActionStatus.approved: return context.tr('agent_approved');
      case AgentActionStatus.executing: return context.tr('agent_executing');
      case AgentActionStatus.succeeded: return context.tr('agent_succeeded');
      case AgentActionStatus.failed: return context.tr('agent_failed');
      case AgentActionStatus.denied: return context.tr('agent_denied');
      case AgentActionStatus.cancelled: return context.tr('agent_cancelled');
      case AgentActionStatus.expired: return context.tr('agent_expired');
      default: return context.tr('agent_draft');
    }
  }

  Color _statusColor(AgentActionStatus s, ColorScheme cs) {
    switch (s) {
      case AgentActionStatus.succeeded: return Colors.green;
      case AgentActionStatus.failed: return cs.error;
      case AgentActionStatus.denied: return Colors.orange;
      case AgentActionStatus.cancelled: return cs.onSurface.withValues(alpha: 0.5);
      case AgentActionStatus.expired: return cs.onSurface.withValues(alpha: 0.5);
      case AgentActionStatus.awaitingApproval: return Colors.amber;
      case AgentActionStatus.approved: return Colors.blue;
      case AgentActionStatus.executing: return cs.primary;
      default: return cs.onSurface.withValues(alpha: 0.4);
    }
  }
}

class _AgentTyping extends StatelessWidget {
  const _AgentTyping();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 20, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
  }
}

class _UserBubble extends StatelessWidget {
  final AiMessage msg;
  final ColorScheme cs;
  const _UserBubble({required this.msg, required this.cs});

  @override
  Widget build(BuildContext context) {
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
}

class _AgentBubble extends StatelessWidget {
  final AiMessage msg;
  final ColorScheme cs;
  final VoidCallback onRetry;
  const _AgentBubble({required this.msg, required this.cs, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
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
                  IconButton(icon: const Icon(Icons.copy, size: 16), onPressed: () {}, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
                ],
                if (msg.isFailed)
                  IconButton(icon: const Icon(Icons.refresh, size: 16), onPressed: onRetry, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
              ],
            ),
            const SizedBox(height: 8),
            if (msg.isGenerating && msg.content.isEmpty) const _AgentTyping() else Text(msg.content, style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class AgentActionCard extends StatelessWidget {
  final AgentPendingAction action;
  final ColorScheme cs;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onExecute;
  final VoidCallback onCancel;

  const AgentActionCard({
    super.key,
    required this.action,
    required this.cs,
    required this.onApprove,
    required this.onDeny,
    required this.onExecute,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.35,
      builder: (ctx, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Icon(Icons.event_busy, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(context.tr('agent_action_preview'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18))),
              ],
            ),
            const SizedBox(height: 16),
            Text(action.actionType, style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            ..._buildParameterRows(context),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: cs.primary.withValues(alpha: 0.7), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      action.requiredMfa
                          ? context.tr('agent_action_requires_mfa')
                          : context.tr('agent_action_confirm_note'),
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: action.isTerminal ? null : onDeny,
                    child: Text(context.tr('deny')),
                  ),
                ),
                const SizedBox(width: 12),
                if (action.approved && !action.isTerminal)
                  Expanded(
                    child: FilledButton(
                      onPressed: onExecute,
                      child: Text(action.requiredMfa ? context.tr('agent_execute_mfa') : context.tr('agent_execute')),
                    ),
                  )
                else if (action.awaitingApproval)
                  Expanded(
                    child: FilledButton(
                      onPressed: onApprove,
                      child: Text(context.tr('approve')),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildParameterRows(BuildContext context) {
    final params = action.parameters;
    if (params.isEmpty) {
      return [Text(context.tr('agent_no_parameters'), style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12))];
    }
    return params.entries.map((e) {
      final label = _humanLabel(e.key, context);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(8)),
              child: Text(_formatValue(e.value), style: const TextStyle(fontSize: 13, fontFamily: 'JetBrains Mono')),
            ),
          ],
        ),
      );
    }).toList();
  }

  String _humanLabel(String key, BuildContext context) {
    switch (key) {
      case 'title': return context.tr('agent_field_title');
      case 'description': return context.tr('agent_field_description');
      case 'price': return context.tr('agent_field_price');
      case 'amount': return context.tr('agent_field_amount');
      case 'orderId': return context.tr('agent_field_order');
      case 'id': return context.tr('agent_field_id');
      case 'phoneNumber': return context.tr('agent_field_phone');
      case 'subject': return context.tr('agent_field_subject');
      default: return key;
    }
  }

  String _formatValue(dynamic v) {
    if (v == null) return '—';
    if (v is num) return v.toString();
    return v.toString();
  }
}
