import 'package:flutter/material.dart';
import '../../services/whatsapp_service.dart';

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
      backgroundColor: Colors.black,
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
                  color: const Color(0xFF25D366).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 50,
                  color: Color(0xFF25D366),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Tazama status kwenye WhatsApp',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
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
                },
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Rudi Nyuma',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
