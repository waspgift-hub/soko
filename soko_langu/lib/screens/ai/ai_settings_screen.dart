import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../extensions/context_tr.dart';
import '../../services/persistent_ai_chat_service.dart';
import '../../widgets/soko_vibe_states.dart';
import '../../widgets/soko_dialog.dart';
import '../../models/ai_chat_models.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _service = PersistentAiChatService();
  AiPreferences? _prefs;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final prefs = await _service.getPreferences();
      if (mounted) setState(() { _prefs = prefs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggle(String key, bool value) async {
    final current = _prefs;
    if (current == null) return;
    setState(() {
      _prefs = AiPreferences(
        memoryEnabled: key == 'memory' ? value : current.memoryEnabled,
        chatHistoryEnabled: key == 'history' ? value : current.chatHistoryEnabled,
        voiceEnabled: key == 'voice' ? value : current.voiceEnabled,
        preferredLanguage: current.preferredLanguage,
        responseStyle: current.responseStyle,
      );
    });
    try {
      await _service.updatePreferences(
        memoryEnabled: key == 'memory' ? value : null,
        chatHistoryEnabled: key == 'history' ? value : null,
        voiceEnabled: key == 'voice' ? value : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ai_settings_save_failed'))),
        );
        _load();
      }
    }
  }

  Future<void> _clearMemory() async {
    final ok = await SokoDialog.show(
      context,
      variant: SokoDialogVariant.danger,
      icon: Icons.delete_outline,
      title: context.tr('ai_clear_memory_title'),
      message: context.tr('ai_clear_memory_body'),
      confirmLabel: context.tr('clear'),
      cancelLabel: context.tr('cancel'),
    );
    if (ok != true) return;
    try {
      await _service.clearMemories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ai_memory_cleared'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ai_settings_save_failed'))),
        );
      }
    }
  }

  Future<void> _deleteAllChats() async {
    final ok = await SokoDialog.show(
      context,
      variant: SokoDialogVariant.danger,
      icon: Icons.delete_forever,
      title: context.tr('ai_delete_all_chats_title'),
      message: context.tr('ai_delete_all_chats_body'),
      confirmLabel: context.tr('delete'),
      cancelLabel: context.tr('cancel'),
    );
    if (ok != true) return;
    try {
      await _service.deleteAllConversations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ai_all_chats_deleted'))),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ai_settings_save_failed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('ai_settings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? SokoVibeErrorState(message: _error, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _section(context.tr('ai_memory_section'), [
                      SwitchListTile(
                        title: Text(context.tr('ai_memory_enabled')),
                        subtitle: Text(context.tr('ai_memory_enabled_body')),
                        value: _prefs?.memoryEnabled ?? true,
                        onChanged: (v) => _toggle('memory', v),
                      ),
                      SwitchListTile(
                        title: Text(context.tr('ai_chat_history_enabled')),
                        subtitle: Text(context.tr('ai_chat_history_enabled_body')),
                        value: _prefs?.chatHistoryEnabled ?? true,
                        onChanged: (v) => _toggle('history', v),
                      ),
                    ]),
                    _section(context.tr('ai_voice_section'), [
                      SwitchListTile(
                        title: Text(context.tr('ai_voice_enabled')),
                        value: _prefs?.voiceEnabled ?? true,
                        onChanged: (v) => _toggle('voice', v),
                      ),
                    ]),
                    _section(context.tr('ai_data_section'), [
                      ListTile(
                        leading: const Icon(Icons.psychology_outlined),
                        title: Text(context.tr('ai_clear_memory')),
                        subtitle: Text(context.tr('ai_clear_memory_body')),
                        onTap: _clearMemory,
                      ),
                      ListTile(
                        leading: Icon(Icons.delete_forever, color: cs.error),
                        title: Text(context.tr('ai_delete_all_chats'), style: TextStyle(color: cs.error)),
                        onTap: _deleteAllChats,
                      ),
                    ]),
                  ],
                ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        Card(
          child: Column(children: children),
        ),
      ],
    );
  }
}