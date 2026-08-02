import 'package:flutter/material.dart';
import '../extensions/context_tr.dart';
import '../services/call_service.dart';

/// "Mpigie Muuzaji" — opens the phone dialer with the seller's number
/// prefilled via the tel: scheme (normal cellular minutes, no internet).
class CallSellerButton extends StatelessWidget {
  const CallSellerButton({
    super.key,
    required this.phone,
    this.iconOnly = false,
    this.label,
    this.height,
    this.fontSize,
  });

  final String phone;
  final bool iconOnly;
  final String? label;
  final double? height;
  final double? fontSize;

  Future<void> _dial(BuildContext context) async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('phone_not_found'))),
      );
      return;
    }
    final ok = await CallService.dial(phone);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('no_dialer_app'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (iconOnly) {
      return IconButton(
        tooltip: context.tr('call_seller'),
        icon: Icon(Icons.phone, color: cs.primary),
        onPressed: phone.isEmpty ? null : () => _dial(context),
      );
    }
    return SizedBox(
      height: height ?? 44,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.primary.withValues(alpha: 0.4), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.phone, size: 18),
        onPressed: phone.isEmpty ? null : () => _dial(context),
        label: Text(
          label ?? context.tr('call_seller'),
          style: TextStyle(fontSize: fontSize ?? 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
