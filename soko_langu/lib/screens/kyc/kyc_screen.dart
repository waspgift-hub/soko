import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../services/kyc_service.dart';
import '../../widgets/google_loading.dart';
import '../../theme/app_colors.dart';
import '../../extensions/context_tr.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final _fullNameController = TextEditingController();
  final _idNumberController = TextEditingController();
  String _idType = 'National ID';
  bool _submitting = false;
  String? _status;
  String? _reviewNotes;
  String? _kycIdImageUrl;
  String? _kycSelfieUrl;
  XFile? _idImageFile;
  XFile? _selfieFile;

  final _idTypes = ['National ID', 'Passport', 'Drivers License', 'Voters ID'];
  final _picker = ImagePicker();
  final _storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    Map<String, dynamic>? kyc;
    try {
      final result = await KycService.getKycStatus(user.uid);
      kyc = result?['kyc'] as Map<String, dynamic>?;
    } catch (_) {}
    if (kyc == null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      kyc = doc.data()?['kyc'] as Map<String, dynamic>?;
    }
    if (!mounted) return;
    setState(() {
      _status = kyc?['status'] as String? ?? 'none';
      _reviewNotes = kyc?['reviewNotes'] as String?;
      _kycIdImageUrl = kyc?['idImageUrl'] as String?;
      _kycSelfieUrl = kyc?['selfieUrl'] as String?;
    });
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _idNumberController.dispose();
    super.dispose();
  }

  Future<String?> _uploadImage(XFile file, String prefix) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final ext = file.path.split('.').last;
      final extSafe = ext.length > 1 && ext.length < 6 ? ext : 'jpg';
      final ref = _storage.ref().child('kyc/${user.uid}/${prefix}_${const Uuid().v4()}.$extSafe');
      final bytes = await file.readAsBytes();
      await ref.putData(bytes);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _pickImage({required bool isSelfie}) async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('choose_source')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(context.tr('take_photo')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(context.tr('choose_from_gallery')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final file = await _picker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024);
    if (file != null) {
      setState(() {
        if (isSelfie) {
          _selfieFile = file;
        } else {
          _idImageFile = file;
        }
      });
    }
  }

  Future<void> _submit() async {
    final fullName = _fullNameController.text.trim();
    final idNumber = _idNumberController.text.trim();

    if (fullName.isEmpty) {
      _showError(context.tr('enter_full_name_please'));
      return;
    }
    if (idNumber.isEmpty) {
      _showError(context.tr('enter_id_number_please'));
      return;
    }
    if (_idImageFile == null) {
      _showError(context.tr('upload_id_image_please'));
      return;
    }
    if (_selfieFile == null) {
      _showError(context.tr('take_selfie_please'));
      return;
    }

    setState(() => _submitting = true);

    try {
      final idImageUrl = await _uploadImage(_idImageFile!, 'id');
      final selfieUrl = await _uploadImage(_selfieFile!, 'selfie');

      if (idImageUrl == null) {
        _showError('Imeshindwa kupakia picha ya kitambulisho. Angalia muunganisho wako na ujaribu tena.');
        setState(() => _submitting = false);
        return;
      }
      if (selfieUrl == null) {
        _showError('Imeshindwa kupakia selfie yako. Angalia muunganisho wako na ujaribu tena.');
        setState(() => _submitting = false);
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final result = await KycService.submitKyc(
        userId: user.uid,
        fullName: fullName,
        idType: _idType,
        idNumber: idNumber,
        idImageUrl: idImageUrl,
        selfieUrl: selfieUrl,
      );

      if (result != null && result['success'] == true) {
        final approved = result['approved'] == true;
        if (approved) {
          _showSuccess(context.tr('kyc_approved_success'));
        } else {
          final reasonText = result['reason'] ?? context.tr('kyc_under_review');
          _showSuccess('${context.tr('kyc_submitted')} ${context.tr('reason')}: $reasonText');
        }
        _loadStatus();
      } else {
        _showError(result?['error'] ?? context.tr('failed_to_submit_kyc'));
      }
    } catch (e) {
      _showError('Imeshindwa: ${e.toString()}');
    }

    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('kyc_title'))),
      body: _status == null
          ? const GoogleLoadingPage()
          : _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_status == 'approved') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified, size: 80, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(context.tr('kyc_approved'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(context.tr('kyc_approved_desc'),
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 15)),
              if (_kycIdImageUrl != null) ...[
                const SizedBox(height: 16),
                Text(context.tr('identification_label'), style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(_kycIdImageUrl!, height: 150, fit: BoxFit.cover),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_status == 'pending') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top, size: 80, color: Theme.of(context).colorScheme.tertiary),
              const SizedBox(height: 16),
              Text(context.tr('kyc_pending'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(context.tr('kyc_pending_desc'),
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 15)),
            ],
          ),
        ),
      );
    }

    if (_status == 'rejected') {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.cancel, color: Theme.of(context).colorScheme.error, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _reviewNotes ?? context.tr('kyc_rejected_default'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildForm(cs),
        ],
      );
    }

    return _buildForm(cs);
  }

  Widget _buildForm(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          context.tr('fill_identity_info'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('upload_id_selfie_instruction'),
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.59), fontSize: 13),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _fullNameController,
          decoration: InputDecoration(
            labelText: context.tr('full_name'),
            hintText: context.tr('as_on_id'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _idType,
          decoration: InputDecoration(
            labelText: context.tr('id_type'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.badge),
          ),
          items: _idTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _idType = v ?? 'National ID'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _idNumberController,
          decoration: InputDecoration(
            labelText: context.tr('id_number'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.numbers),
          ),
        ),
        const SizedBox(height: 24),
        // Image upload section
        Row(
          children: [
            Expanded(
              child: _buildImagePicker(
                label: context.tr('id_image_label'),
                icon: Icons.credit_card,
                file: _idImageFile,
                imageUrl: _kycIdImageUrl,
                onPick: () => _pickImage(isSelfie: false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildImagePicker(
                label: context.tr('your_selfie'),
                icon: Icons.face,
                file: _selfieFile,
                imageUrl: _kycSelfieUrl,
                onPick: () => _pickImage(isSelfie: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const GoogleLoading(size: 20, strokeWidth: 2)
                : const Icon(Icons.send),
            label: Text(_submitting ? context.tr('submitting') : context.tr('submit_kyc')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.successGreen,
              foregroundColor: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePicker({
    required String label,
    required IconData icon,
    required XFile? file,
    required String? imageUrl,
    required VoidCallback onPick,
  }) {
    final hasImage = file != null || imageUrl != null;
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: hasImage ? Colors.transparent : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6) : Theme.of(context).colorScheme.outline,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: hasImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: file != null
                        ? Image.file(File(file.path), width: double.infinity, height: 140, fit: BoxFit.cover)
                        : Image.network(imageUrl!, width: double.infinity, height: 140, fit: BoxFit.cover),
                  ),
                  if (file != null)
                    Positioned(
                      top: 4, right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check, color: Theme.of(context).colorScheme.surface, size: 16),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 6),
                  Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                ],
              ),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.primary),
    );
  }
}