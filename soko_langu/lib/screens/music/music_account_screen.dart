import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MusicAccountScreen extends StatefulWidget {
  const MusicAccountScreen({super.key});

  @override
  State<MusicAccountScreen> createState() => _MusicAccountScreenState();
}

class _MusicAccountScreenState extends State<MusicAccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  late final SupabaseClient _supabase;
  StreamSubscription<AuthState>? _authSubscription;

  bool _registerMode = false;
  bool _busy = false;
  bool _loadingSettings = false;
  String? _message;
  String _language = 'sw-TZ';
  String _theme = 'system';
  String _quality = 'standard';
  bool _autoplay = false;
  bool _explicitContent = false;

  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    _authSubscription = _supabase.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (_user != null) _loadAccount();
    });
    if (_user != null) _loadAccount();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _runAuth() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 6) {
      setState(() => _message = 'Weka email na nenosiri lenye angalau herufi 6.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      if (_registerMode) {
        final result = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {'display_name': _name.text.trim()},
        );
        if (result.session == null) {
          setState(() => _message =
              'Akaunti imeombwa. Angalia email kuthibitisha akaunti, kisha ingia.');
        } else {
          setState(() => _message = 'Akaunti imeundwa.');
          await _loadAccount();
        }
      } else {
        await _supabase.auth.signInWithPassword(email: email, password: password);
        await _loadAccount();
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e) {
      if (mounted) setState(() => _message = 'Imeshindikana kuunganisha: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadAccount() async {
    final user = _user;
    if (user == null) return;
    setState(() => _loadingSettings = true);
    try {
      final profile = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('id', user.id)
          .maybeSingle();
      _name.text = (profile?['display_name'] as String?) ?? '';
      final settings = await _supabase
          .from('user_settings')
          .select('language, theme, autoplay, audio_quality, explicit_content')
          .eq('user_id', user.id)
          .maybeSingle();
      if (settings != null) {
        _language = settings['language'] as String? ?? 'sw-TZ';
        _theme = settings['theme'] as String? ?? 'system';
        _autoplay = settings['autoplay'] as bool? ?? false;
        _quality = settings['audio_quality'] as String? ?? 'standard';
        _explicitContent = settings['explicit_content'] as bool? ?? false;
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Imeshindikana kupakia profile/settings: $e');
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  Future<void> _saveProfile() async {
    final user = _user;
    if (user == null) return;
    setState(() { _busy = true; _message = null; });
    try {
      await _supabase.from('profiles').update({
        'display_name': _name.text.trim().isEmpty ? null : _name.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);
      if (mounted) setState(() => _message = 'Profile imehifadhiwa.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Profile haijahifadhiwa: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSettings() async {
    final user = _user;
    if (user == null) return;
    setState(() { _busy = true; _message = null; });
    try {
      await _supabase.from('user_settings').update({
        'language': _language,
        'theme': _theme,
        'autoplay': _autoplay,
        'audio_quality': _quality,
        'explicit_content': _explicitContent,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', user.id);
      if (mounted) setState(() => _message = 'Mipangilio imehifadhiwa kwenye akaunti yako.');
    } catch (e) {
      if (mounted) setState(() => _message = 'Mipangilio haijahifadhiwa: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() { _busy = true; _message = null; });
    try {
      await _supabase.auth.signOut();
      if (mounted) {
        setState(() {
          _message = 'Umetoka kwenye akaunti ya SokoVibe Music.';
          _language = 'sw-TZ';
          _theme = 'system';
          _quality = 'standard';
          _autoplay = false;
          _explicitContent = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Imeshindikana kutoka: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Akaunti ya Music')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_message != null) ...[
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_message!),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (user == null) ...[
            Text(_registerMode ? 'Tengeneza akaunti ya Music' : 'Ingia SokoVibe Music',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_registerMode)
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Jina la kuonyesha'),
              ),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Nenosiri (angalau herufi 6)'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _runAuth,
              child: Text(_busy ? 'Subiri...' : (_registerMode ? 'Sajili' : 'Ingia')),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() {
                _registerMode = !_registerMode;
                _message = null;
              }),
              child: Text(_registerMode
                  ? 'Tayari una akaunti? Ingia'
                  : 'Huna akaunti? Jisajili'),
            ),
            const SizedBox(height: 8),
            const Text('Hii ni akaunti ya SokoVibe Music pekee; haiibadilishi Firebase login ya marketplace.'),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(_name.text.isEmpty ? (user.email ?? 'Mtumiaji') : _name.text),
              subtitle: Text(user.email ?? ''),
              trailing: IconButton(
                tooltip: 'Toka',
                onPressed: _busy ? null : _signOut,
                icon: const Icon(Icons.logout),
              ),
            ),
            const Divider(),
            Text('Profile', style: Theme.of(context).textTheme.titleMedium),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Jina la kuonyesha'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _saveProfile,
              child: const Text('Hifadhi profile'),
            ),
            const Divider(height: 32),
            Text('Mipangilio ya muziki', style: Theme.of(context).textTheme.titleMedium),
            if (_loadingSettings) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
              value: _language,
              decoration: const InputDecoration(labelText: 'Lugha'),
              items: const [
                DropdownMenuItem(value: 'sw-TZ', child: Text('Kiswahili')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: _busy ? null : (v) { if (v != null) setState(() => _language = v); },
            ),
            DropdownButtonFormField<String>(
              value: _theme,
              decoration: const InputDecoration(labelText: 'Muonekano'),
              items: const [
                DropdownMenuItem(value: 'system', child: Text('Kulingana na kifaa')),
                DropdownMenuItem(value: 'light', child: Text('Mwanga')),
                DropdownMenuItem(value: 'dark', child: Text('Giza')),
              ],
              onChanged: _busy ? null : (v) { if (v != null) setState(() => _theme = v); },
            ),
            DropdownButtonFormField<String>(
              value: _quality,
              decoration: const InputDecoration(labelText: 'Ubora wa sauti'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Data kidogo')),
                DropdownMenuItem(value: 'standard', child: Text('Kawaida')),
                DropdownMenuItem(value: 'high', child: Text('Juu')),
              ],
              onChanged: _busy ? null : (v) { if (v != null) setState(() => _quality = v); },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cheza muziki unaofuata kiotomatiki'),
              value: _autoplay,
              onChanged: _busy ? null : (v) => setState(() => _autoplay = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ruhusu maudhui ya wazi'),
              value: _explicitContent,
              onChanged: _busy ? null : (v) => setState(() => _explicitContent = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy || _loadingSettings ? null : _saveSettings,
              child: Text(_busy ? 'Inahifadhi...' : 'Hifadhi mipangilio'),
            ),
          ],
        ],
      ),
    );
  }
}
