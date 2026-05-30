import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../services/whatsapp_service.dart';

class AddStatusScreen extends StatelessWidget {
  const AddStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('add_status')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_circle_outline,
                  size: 50,
                  color: Color(0xFF25D366),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('add_status'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Ongeza status yako kwenye WhatsApp',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text(
                    'Fungua WhatsApp',
                    style: TextStyle(fontSize: 16),
                  ),
                  onPressed: () {
                    WhatsAppService().openWhatsApp(
                      phoneNumber: '',
                      message: '',
                      onError: () {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Imeshindwa kufungua WhatsApp'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
