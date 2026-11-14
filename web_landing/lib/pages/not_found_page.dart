import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../router/app_router.dart';
import '../widgets/layout/site_shell.dart';
import '../widgets/responsive_container.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});
  @override
  Widget build(BuildContext context) {
    return SiteShell(
      currentPath: '/404',
      child: ResponsiveContainer(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '404',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: const Color(0xFF008069),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.str('page_404_title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(context.str('page_404_body'), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
                  child: Text(context.str('page_404_home')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
