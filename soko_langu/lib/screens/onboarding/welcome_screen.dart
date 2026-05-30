import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/routes.dart';
import '../../app/app_state.dart' as app_state;
import '../../extensions/context_tr.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<_WelcomePage> _pages = [
    _WelcomePage(
      icon: Icons.storefront_rounded,
      title: 'Soko Langu',
      subtitle: 'Your Marketplace, Your Language',
      description:
          'The best place to buy and sell new and second-hand goods. Safe, fast, and in your language.',
      color: const Color(0xFF2D6A4F),
    ),
    _WelcomePage(
      icon: Icons.diamond_outlined,
      title: 'Premium Marketplace',
      subtitle: 'Buy & Sell with Confidence',
      description:
          'Real people, real products. Connect directly with buyers and sellers in your community.',
      color: const Color(0xFF6C63FF),
    ),
    _WelcomePage(
      icon: Icons.rocket_launch_rounded,
      title: 'AI Dalali',
      subtitle: 'Smart AI Assistant',
      description:
          'Get help finding products, checking prices, and growing your business — 24/7 with AI Dalali.',
      color: const Color(0xFF0088CC),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    app_state.onboardingSeen = true;
    if (mounted) context.replace(AppRoutes.accountSelection);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _complete,
                  child: Text(
                  context.tr('skip'),
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
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
                          width: 140,
                          height: 140,
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
                          child: Icon(p.icon, size: 60, color: p.color),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          p.title,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          p.subtitle,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: p.color,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p.description,
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                            height: 1.6,
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
                final isActive = _currentPage == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: isActive ? 28 : 9,
                  height: 9,
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? LinearGradient(
                            colors: [
                              _pages[_currentPage].color,
                              _pages[_currentPage].color.withValues(alpha: 0.6),
                            ],
                          )
                        : null,
                    color: isActive ? null : Colors.grey[300],
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
                        _pages[_currentPage].color,
                        _pages[_currentPage].color.withValues(alpha: 0.8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _pages[_currentPage].color.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
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
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage {
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final Color color;

  const _WelcomePage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.color,
  });
}
