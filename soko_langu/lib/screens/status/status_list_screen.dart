import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../extensions/context_tr.dart';
import '../../services/whatsapp_service.dart';

class StatusListScreen extends StatelessWidget {
  const StatusListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.tr('status'),
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Theme.of(context).colorScheme.tertiaryContainer, Theme.of(context).colorScheme.surfaceContainerLow],
            ),
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.whatsappGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 50,
                  color: Theme.of(context).colorScheme.whatsappGreen,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('status'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('view_share_status_whatsapp'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.whatsappGreen,
                    foregroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(
                    context.tr('open_whatsapp_status'),
                    style: const TextStyle(fontSize: 16),
                  ),
                  onPressed: () => _openWhatsAppStatus(context),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.whatsappGreen,
                    side: BorderSide(color: Theme.of(context).colorScheme.whatsappGreen),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(
                    context.tr('add_status'),
                    style: const TextStyle(fontSize: 16),
                  ),
                  onPressed: () => _openWhatsAppStatus(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openWhatsAppStatus(BuildContext context) {
    WhatsAppService().openWhatsApp(
      phoneNumber: '',
      message: '',
      onError: () {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('whatsapp_open_failed')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      onFallback: () {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('whatsapp_not_installed')),
            ),
          );
        }
      },
    );
  }
}