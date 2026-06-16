import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../services/localization_service.dart';
import '../../app/routes.dart';
import '../../app/app_state.dart' as app_state;
import '../../main.dart' show AppConfig;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  final _phoneCtrl = TextEditingController();
  int _currentPage = 0;
  String _selectedLang = 'sw';
  String _phoneError = '';

  List<_OnboardingPage> _pages(ThemeData theme) {
    final cs = theme.colorScheme;
    return [
      _OnboardingPage(
        icon: Icons.storefront_outlined,
        titleKey: 'onboarding_welcome_title',
        descKey: 'onboarding_welcome_desc',
        color: cs.primary,
      ),
      _OnboardingPage(
        icon: Icons.auto_awesome_outlined,
        titleKey: 'onboarding_ai_title',
        descKey: 'onboarding_ai_desc',
        color: cs.secondary,
      ),
      _OnboardingPage(
        icon: Icons.forum_outlined,
        titleKey: 'onboarding_chat_title',
        descKey: 'onboarding_chat_desc',
        color: cs.tertiary,
      ),
      _OnboardingPage(
        icon: Icons.language,
        titleKey: 'onboarding_language_title',
        descKey: 'onboarding_language_desc',
        color: cs.primary,
      ),
      _OnboardingPage(
        icon: Icons.phone_android,
        titleKey: 'onboarding_phone_title',
        descKey: 'onboarding_phone_desc',
        color: cs.secondary,
      ),
    ];
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    await prefs.setString('language_code', _selectedLang);
    await LocalizationService().setLanguage(_selectedLang);
    AppConfig.of(context).onSetLanguage(_selectedLang);
    if (_phoneCtrl.text.trim().isNotEmpty) {
      await prefs.setString('phone_number', _phoneCtrl.text.trim());
    }
    app_state.onboardingSeen = true;
    if (mounted) context.replace(AppRoutes.accountSelection);
  }

  bool _canProceed() {
    if (_currentPage == 3) return _selectedLang.isNotEmpty;
    if (_currentPage == 4) return _phoneCtrl.text.trim().length >= 10;
    return true;
  }

  void _onNext() {
    if (_currentPage == 4) {
      final phone = _phoneCtrl.text.trim();
      if (phone.length < 10) {
        setState(() => _phoneError = 'Ingiza namba sahihi (angalau tarakimu 10)');
        return;
      }
    }
    if (_currentPage == _pages(Theme.of(context)).length - 1) {
      _complete();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pg = _pages(theme);
    final isLast = _currentPage == pg.length - 1;

    

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: _currentPage < pg.length - 1
                  ? TextButton(
                      onPressed: _complete,
                      child: Text(
                        context.tr('skip'),
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pg.length,
                onPageChanged: (i) => setState(() {
                  _currentPage = i;
                  _phoneError = '';
                }),
                itemBuilder: (_, i) {
                  if (i == 3) return _buildLanguagePage(cs);
                  if (i == 4) return _buildPhonePage(cs);
                  final p = pg[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                p.color.withValues(alpha: 0.15),
                                p.color.withValues(alpha: 0.05),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: p.color.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(p.icon, size: 56, color: p.color),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          context.tr(p.titleKey),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          context.tr(p.descKey),
                          style: TextStyle(
                            fontSize: 15,
                            color: cs.onSurface.withValues(alpha: 0.6),
                            height: 1.6,
                          ),
                          textAlign: TextAlign.center,
                          softWrap: true,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Page indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pg.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: _currentPage == i ? 28 : 9,
                  height: 9,
                  decoration: BoxDecoration(
                    gradient: _currentPage == i
                        ? LinearGradient(
                            colors: [
                              pg[_currentPage].color,
                              pg[_currentPage].color.withValues(alpha: 0.6),
                            ],
                          )
                        : null,
                    color: _currentPage == i ? null : cs.outline,
                    borderRadius: BorderRadius.circular(5),
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        pg[_currentPage].color,
                        pg[_currentPage].color.withValues(alpha: 0.8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: pg[_currentPage].color.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _canProceed()
                    ?(isLast ? _complete : _onNext)

                    : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      isLast
                          ? context.tr('onboarding_start')
                          : context.tr('next'),
                      style: TextStyle(
                        color: cs.surface,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_currentPage < 3) ...[
              const SizedBox(height: 24),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary.withValues(alpha: 0.15),
                            cs.primary.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 18,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('powered_by_ai'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            context.tr('chat_with_ai_help'),
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.55),
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguagePage(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Chagua Lugha / Choose Language',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Chagua lugha unayotaka kutumia',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 40),
          _LangButton(
            label: 'Kiswahili',
            sub: 'Swahili',
            flag: '🇹🇿',
            selected: _selectedLang == 'sw',
            onTap: () => setState(() => _selectedLang = 'sw'),
          ),
          const SizedBox(height: 16),
          _LangButton(
            label: 'English',
            sub: 'English',
            flag: '🇬🇧',
            selected: _selectedLang == 'en',
            onTap: () => setState(() => _selectedLang = 'en'),
          ),
        ],
      ),
    );
  }

  Widget _buildPhonePage(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: cs.secondary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.phone_android, size: 48, color: cs.secondary),
          ),
          const SizedBox(height: 32),
          Text(
            'Weka namba yako ya simu',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Itatumika kwa miamala na arifa',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '255xxxxxxxxx',
              labelText: 'Namba ya simu',
              prefixIcon: const Icon(Icons.phone),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              errorText: _phoneError.isNotEmpty ? _phoneError : null,
            ),
            onChanged: (_) => setState(() => _phoneError = ''),
          ),
          const SizedBox(height: 12),
          Text(
            'Bonyeza "Next" kuendelea au "Skip" kuruka hatua hii',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final String sub;
  final String flag;
  final bool selected;
  final VoidCallback onTap;

  const _LangButton({
    required this.label,
    required this.sub,
    required this.flag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.1) : cs.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : cs.outline.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: cs.primary, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String titleKey;
  final String descKey;
  final Color color;
  const _OnboardingPage({
    required this.icon,
    required this.titleKey,
    required this.descKey,
    required this.color,
  });
}