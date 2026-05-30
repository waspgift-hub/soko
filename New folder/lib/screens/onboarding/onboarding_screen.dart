import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../app/app_state.dart' as app_state;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.store,
      titleKey: 'onboarding_welcome_title',
      descKey: 'onboarding_welcome_desc',
      color: Colors.green,
    ),
    _OnboardingPage(
      icon: Icons.chat_bubble_outline,
      titleKey: 'onboarding_chat_title',
      descKey: 'onboarding_chat_desc',
      color: Colors.blue,
    ),
    _OnboardingPage(
      icon: Icons.call,
      titleKey: 'onboarding_calls_title',
      descKey: 'onboarding_calls_desc',
      color: Colors.purple,
    ),
  ];

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    app_state.onboardingSeen = true;
    if (mounted) context.replace(AppRoutes.home);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: p.color.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(p.icon, size: 56, color: p.color),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          context.tr(p.titleKey),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.tr(p.descKey),
                          style: TextStyle(
                            fontSize: 15,
                            color: theme.colorScheme.onSurface.withOpacity(0.65),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == i
                        ? _pages[_currentPage].color
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pages[_currentPage].color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (_currentPage == _pages.length - 1) {
                      _complete();
                    } else {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  child: Text(
                    _currentPage == _pages.length - 1
                        ? context.tr('onboarding_start')
                        : context.tr('next'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            if (_currentPage < _pages.length - 1)
              TextButton(
                onPressed: _complete,
                child: Text(
                  context.tr('skip'),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              )
            else
              const SizedBox(height: 48),
          ],
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

