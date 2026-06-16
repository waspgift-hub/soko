import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/whatsapp_service.dart';
import '../../extensions/context_tr.dart';

class StatusViewerScreen extends StatelessWidget {
  final List<dynamic> updates;
  final int initialIndex;

  const StatusViewerScreen({
    super.key,
    required this.updates,
    this.initialIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.onSurface,
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
                  color: Theme.of(context).colorScheme.whatsappGreen.withValues(alpha: 0.2),
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
                context.tr('view_status_on_whatsapp'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.surface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.whatsappGreen,
                  foregroundColor: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  context.tr('open_whatsapp'),
                  style: const TextStyle(fontSize: 16),
                ),
                onPressed: () {
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
                  );
                },
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  context.tr('go_back'),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}