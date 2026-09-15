import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../services/api_config.dart';
import '../services/cloudinary_service.dart';
import '../extensions/context_tr.dart';

/// Preset dispute reasons; the buyer can also type a custom one.
const List<String> kDisputePresetReasons = [
  'not_received',
  'damaged',
  'not_as_described',
  'other',
];

String _presetLabel(BuildContext context, String key) {
  switch (key) {
    case 'not_received':
      return context.tr('dispute_reason_not_received', 'Sijapokea mzigo');
    case 'damaged':
      return context.tr('dispute_reason_damaged', 'Mzigo umefika umeharibika');
    case 'not_as_described':
      return context.tr('dispute_reason_not_as_described', 'Bidhaa si kama ilivyotangazwa');
    default:
      return context.tr('dispute_reason_other', 'Nyingine');
  }
}

/// Shows the raise-dispute flow: pick a reason, attach up to 3 photos, then
/// submit to the Firestore escrow engine. Returns true when submitted.
Future<bool> showRaiseDisputeDialog(
  BuildContext context, {
  required String txId,
  required String userId,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RaiseDisputeDialog(txId: txId, userId: userId),
  );
  return result == true;
}

class _RaiseDisputeDialog extends StatefulWidget {
  final String txId;
  final String userId;

  const _RaiseDisputeDialog({required this.txId, required this.userId});

  @override
  State<_RaiseDisputeDialog> createState() => _RaiseDisputeDialogState();
}

class _RaiseDisputeDialogState extends State<_RaiseDisputeDialog> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _otherCtrl = TextEditingController();
  final List<XFile> _photos = [];
  String _selectedReason = 'not_received';
  bool _submitting = false;
  String? _error;
  bool _uploading = false;

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_photos.length >= 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kiatharisho 3 pekee')),
        );
      }
      return;
    }
    try {
      final xf = await _picker.pickImage(source: source, imageQuality: 80);
      if (xf != null) setState(() => _photos.add(xf));
    } catch (_) {}
  }

  String get _effectiveReason {
    final base = _presetLabel(context, _selectedReason);
    final extra = _selectedReason == 'other' ? _otherCtrl.text.trim() : '';
    return extra.isEmpty ? base : '$base — $extra';
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      setState(() => _uploading = true);
      final urls = _photos.isEmpty
          ? <String>[]
          : await CloudinaryService.uploadMultiple(_photos, folder: 'disputes');
      if (mounted) setState(() => _error = null);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _error = 'Not authenticated');
        return;
      }
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/dispute'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await user.getIdToken()}',
        },
        body: jsonEncode({
          'orderId': widget.txId,
          'userId': widget.userId,
          'reason': _effectiveReason,
          'evidenceUrls': urls,
        }),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (mounted) {
        setState(() => _error = result['error']?.toString() ?? 'Mgogoro haukufunguka');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.gavel, color: cs.error, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('dispute_title'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('dispute_why', 'Ni kwa nini unafungua mgogoro?'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kDisputePresetReasons.map((r) {
                  final selected = _selectedReason == r;
                  return ChoiceChip(
                    label: Text(_presetLabel(context, r)),
                    selected: selected,
                    selectedColor: cs.primary.withValues(alpha: 0.15),
                    onSelected: (_) => setState(() => _selectedReason = r),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      color: selected ? cs.primary : cs.onSurface,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: selected ? cs.primary : cs.outlineVariant,
                    ),
                  );
                }).toList(),
              ),
              if (_selectedReason == 'other') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _otherCtrl,
                  maxLines: 2,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: context.tr('dispute_other_hint', 'Andika kilichotokea...'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                context.tr('dispute_evidence', 'Ushahidi (kwa hiari, picha 3 max)'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ..._photos.map((p) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(p.path),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )),
                  if (_photos.length < 3) ...[
                    _photoButton(Icons.photo_library_outlined, () => _pickImage(ImageSource.gallery)),
                    const SizedBox(width: 8),
                    _photoButton(Icons.photo_camera_outlined, () => _pickImage(ImageSource.camera)),
                  ],
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: cs.error, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: Text(context.tr('cancel')),
        ),
        FilledButton.icon(
          onPressed: _submitting || _uploading ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.gavel, size: 16),
          label: Text(
            _uploading
                ? context.tr('uploading_evidence', 'Inapakia ushahidi...')
                : context.tr('dispute_submit', 'Fungua Mgogoro'),
          ),
          style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.surface),
        ),
      ],
    );
  }

  Widget _photoButton(IconData icon, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Icon(icon, color: cs.primary, size: 24),
      ),
    );
  }
}