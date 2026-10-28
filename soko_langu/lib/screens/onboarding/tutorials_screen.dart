import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/routes.dart';
import '../../widgets/animations/soko_animated_illustration.dart';

/// A safe, restartable guide to existing marketplace features.
///
/// The guide only navigates to real screens. It never creates a listing,
/// submits a payment, or changes account state on a user's behalf.
class TutorialsScreen extends StatefulWidget {
  const TutorialsScreen({super.key});

  @override
  State<TutorialsScreen> createState() => _TutorialsScreenState();
}

class _TutorialsScreenState extends State<TutorialsScreen> {
  static const _progressKey = 'learning_center_tutorial_progress';
  static const _completedKey = 'learning_center_tutorial_completed';

  int _page = 0;
  bool _loading = true;

  final List<_TutorialStep> _steps = const [
    _TutorialStep(
      title: 'Tafuta bidhaa',
      description: 'Tumia utafutaji kupata bidhaa, kategoria na wauzaji. '
          'Hakuna bidhaa itanunuliwa kwenye hatua hii.',
      actionLabel: 'Fungua utafutaji',
      route: AppRoutes.search,
      illustration: SokoIllustration.search,
    ),
    _TutorialStep(
      title: 'Weka bidhaa yako',
      description: 'Tengeneza draft ya bidhaa yako, kagua taarifa na uchague '
          'kuchapisha mwenyewe baadaye.',
      actionLabel: 'Fungua kuongeza bidhaa',
      route: AppRoutes.addProduct,
      illustration: SokoIllustration.selling,
    ),
    _TutorialStep(
      title: 'Linda akaunti yako',
      description: 'Angalia hatua za uthibitishaji wa akaunti na KYC. '
          'Kutuma nyaraka kunahitaji uthibitisho wako wa kawaida.',
      actionLabel: 'Fungua uthibitishaji',
      route: AppRoutes.kyc,
      illustration: SokoIllustration.security,
    ),
    _TutorialStep(
      title: 'Pata msaada wa Soko Vibe',
      description: 'Muulize msaidizi kuhusu bidhaa na akaunti. Vitendo vyenye '
          'athari kubwa vitaomba idhini yako kabla havijatekelezwa.',
      actionLabel: 'Fungua msaidizi',
      route: AppRoutes.agent,
      illustration: SokoIllustration.support,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _restoreProgress();
  }

  Future<void> _restoreProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_progressKey) ?? 0;
    if (!mounted) return;
    setState(() {
      _page = saved.clamp(0, _steps.length - 1);
      _loading = false;
    });
  }

  Future<void> _saveProgress(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_progressKey, page);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
    if (mounted) context.pop();
  }

  Future<void> _moveTo(int page) async {
    final safePage = page.clamp(0, _steps.length - 1);
    setState(() => _page = safePage);
    await _saveProgress(safePage);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final step = _steps[_page];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mafunzo ya Soko Vibe'),
        actions: [
          TextButton(onPressed: _finish, child: const Text('Ruka')),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              LinearProgressIndicator(value: (_page + 1) / _steps.length),
              const SizedBox(height: 32),
              SokoAnimatedIllustration(step.illustration, size: 152),
              const SizedBox(height: 28),
              Text(step.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(step.description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  _saveProgress(_page);
                  context.push(step.route);
                },
                icon: const Icon(Icons.open_in_new),
                label: Text(step.actionLabel),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _page == 0 ? null : () => _moveTo(_page - 1),
                    child: const Text('Nyuma'),
                  ),
                  const Spacer(),
                  Text('${_page + 1} / ${_steps.length}',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  const Spacer(),
                  FilledButton(
                    onPressed: _page == _steps.length - 1
                        ? _finish
                        : () => _moveTo(_page + 1),
                    child: Text(_page == _steps.length - 1 ? 'Maliza' : 'Endelea'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TutorialStep {
  const _TutorialStep({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.route,
    required this.illustration,
  });

  final String title;
  final String description;
  final String actionLabel;
  final String route;
  final SokoIllustration illustration;
}
