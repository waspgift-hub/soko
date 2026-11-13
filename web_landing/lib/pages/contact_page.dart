import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../router/app_router.dart';
import '../services/launch_api.dart';
import '../widgets/layout/site_shell.dart';
import '../widgets/responsive_container.dart';
import '../widgets/turnstile_widget.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});
  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _api = LaunchApi();
  final _turnstile = TurnstileController();
  static const _turnstileSiteKey = '0x4AAAAAAF7BcGI4YHafDh77';
  late final int _startedAt;
  bool _loading = false;
  bool _ok = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _ok = false;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final turnstileToken = _turnstile.token;
    if (turnstileToken.isEmpty) {
      setState(() => _error = 'Please complete the security check.');
      return;
    }
    setState(() => _loading = true);
    final res = await _api.contact(
      email: _email.text,
      subject: _subject.text,
      message: _message.text,
      name: _name.text,
      lang: AppStrings.of(context).code,
      formStartedAt: _startedAt,
      turnstileToken: turnstileToken,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _ok = res.ok;
      _error = res.ok
          ? null
          : (res.message == 'RATE_LIMITED'
                ? context.str('form_rate_limited')
                : (res.message == 'NETWORK_ERROR'
                      ? context.str('form_network_error')
                      : context.str('contact_error')));
      if (res.ok) {
        _subject.clear();
        _message.clear();
      }
    });
    _turnstile.reset();
  }

  @override
  Widget build(BuildContext context) {
    return SiteShell(
      currentPath: AppRoutes.contact,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0B141A), Color(0xFF008069)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: ResponsiveContainer(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.str('contact_title'),
                    style: Theme.of(
                      context,
                    ).textTheme.displaySmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.str('contact_sub'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ResponsiveContainer(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_ok)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                context.str('contact_success'),
                                style: const TextStyle(
                                  color: Color(0xFF1DA855),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          TextFormField(
                            controller: _name,
                            decoration: InputDecoration(
                              labelText: context.str('contact_name'),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _email,
                            decoration: InputDecoration(
                              labelText: context.str('contact_email'),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) =>
                                (v == null ||
                                    !RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$',
                                    ).hasMatch(v.trim()))
                                ? context.str('form_invalid')
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _subject,
                            decoration: InputDecoration(
                              labelText: context.str('contact_subject'),
                            ),
                            validator: (v) => (v == null || v.trim().length < 3)
                                ? context.str('contact_invalid')
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _message,
                            decoration: InputDecoration(
                              labelText: context.str('contact_message'),
                            ),
                            minLines: 4,
                            maxLines: 8,
                            validator: (v) =>
                                (v == null || v.trim().length < 10)
                                ? context.str('contact_invalid')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TurnstileWidget(
                            siteKey: _turnstileSiteKey,
                            action: 'contact',
                            controller: _turnstile,
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _loading ? null : _submit,
                            icon: _loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded, size: 18),
                            label: Text(
                              _loading
                                  ? context.str('contact_loading')
                                  : context.str('contact_submit'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            context.str('contact_privacy'),
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
