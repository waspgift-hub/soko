import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/whatsapp_service.dart';
import '../../extensions/context_tr.dart';

class CreateGroupScreen extends StatelessWidget {
  const CreateGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('create_group'))),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
                  Icons.group_add,
                  size: 50,
                  color: Theme.of(context).colorScheme.whatsappGreen,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('create_group'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('create_group_description'),
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
                    context.tr('open_whatsapp'),
                    style: const TextStyle(fontSize: 16),
                  ),
                  onPressed: () {
                    WhatsAppService().openWhatsApp(
                      phoneNumber: '',
                      message: context.tr('group_whatsapp_message'),
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
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('after_create_group_share'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}