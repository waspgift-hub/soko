import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import 'ds/ds.dart';

/// Collects the buyer's transport choice (bus/bodaboda/pikipiki) plus a short
/// note, then saves it via `/api/escrow/buyer-transport`. Returns true on
/// success. Step 7 of the escrow flow: buyer fills transport after payment is
/// held, so the seller knows exactly how to send the goods.
Future<bool> showBuyerTransportSheet({
  required BuildContext context,
  required String orderId,
}) async {
  final cs = Theme.of(context).colorScheme;
  final companyCtrl = TextEditingController();
  final plateCtrl = TextEditingController();
  final driverCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  String? method;
  bool submitting = false;
  var result = false;

  await DsSheet.show<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    content: StatefulBuilder(
      builder: (ctx, setState) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.local_shipping_outlined, color: cs.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('transport_details'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('transport_fill'),
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('transport_method'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _methodChip(
                    context,
                    Icons.directions_bus_filled,
                    context.tr('transport_bus'),
                    method == 'bus',
                    () => setState(() => method = 'bus'),
                  ),
                  const SizedBox(width: 8),
                  _methodChip(
                    context,
                    Icons.two_wheeler,
                    context.tr('transport_bodaboda'),
                    method == 'bodaboda',
                    () => setState(() => method = 'bodaboda'),
                  ),
                  const SizedBox(width: 8),
                  _methodChip(
                    context,
                    Icons.sports_motorsports,
                    context.tr('transport_pikipiki'),
                    method == 'pikipiki',
                    () => setState(() => method = 'pikipiki'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DsTextField(
                controller: companyCtrl,
                label: context.tr('transport_company'),
                prefixIcon: Icons.business_outlined,
              ),
              const SizedBox(height: 12),
              DsTextField(
                controller: plateCtrl,
                label: context.tr('transport_plate'),
                prefixIcon: Icons.pin_outlined,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DsTextField(
                      controller: driverCtrl,
                      label: context.tr('transport_driver_name'),
                      prefixIcon: Icons.person_outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DsTextField(
                      controller: phoneCtrl,
                      label: context.tr('driver_phone'),
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DsTextField(
                controller: noteCtrl,
                label: context.tr('transport_note'),
                prefixIcon: Icons.notes,
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              DsButton(
                label: context.tr('transport_submit'),
                icon: Icons.check_circle_outline,
                loading: submitting,
                onPressed: submitting || method == null
                    ? null
                    : () async {
                        setState(() => submitting = true);
                        result = await _submit(
                          context,
                          orderId,
                          method!,
                          companyCtrl.text,
                          plateCtrl.text,
                          driverCtrl.text,
                          phoneCtrl.text,
                          noteCtrl.text,
                        );
                        if (result && context.mounted) {
                          Navigator.pop(ctx);
                        } else {
                          setState(() => submitting = false);
                        }
                      },
              ),
            ],
          ),
        );
      },
    ),
  );

  return result;
}

Widget _methodChip(
  BuildContext context,
  IconData icon,
  String label,
  bool selected,
  VoidCallback onTap,
) {
  final cs = Theme.of(context).colorScheme;
  return Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.1) : cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> _submit(
  BuildContext context,
  String orderId,
  String method,
  String company,
  String plate,
  String driver,
  String phone,
  String note,
) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/escrow/buyer-transport'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await user.getIdToken()}',
      },
      body: jsonEncode({
        'orderId': orderId,
        'userId': user.uid,
        'transportMethod': method,
        'companyName': company,
        'plateNumber': plate,
        'driverName': driver,
        'driverPhone': phone,
        'note': note,
      }),
    );
    final result = jsonDecode(resp.body);
    return resp.statusCode == 200 && result['success'] == true;
  } catch (_) {
    return false;
  }
}
