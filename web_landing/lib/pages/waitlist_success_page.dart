import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../router/app_router.dart';
import '../widgets/layout/site_shell.dart';
import '../widgets/responsive_container.dart';

class WaitlistSuccessPage extends StatelessWidget {
  const WaitlistSuccessPage({super.key});
  @override
  Widget build(BuildContext context) {
    return SiteShell(
      currentPath: AppRoutes.waitlistSuccess,
      showFooter: false,
      child: ResponsiveContainer(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF008069),
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.str('waitlist_success_title'),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.str('waitlist_success_body'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
                      child: Text(context.str('waitlist_success_cta')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
