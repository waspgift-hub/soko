import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../services/kyc_service.dart';
import '../../widgets/google_loading.dart';

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
  File? _idImageFile;
  File? _selfieFile;

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
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!mounted) return;
    final kyc = doc.data()?['kyc'] as Map<String, dynamic>?;
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

  Future<String?> _uploadImage(File file, String prefix) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final ext = file.path.split('.').last;
      final ref = _storage.ref().child('kyc/${user.uid}/${prefix}_${const Uuid().v4()}.$ext');
      await ref.putFile(file);
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
        title: const Text('Chagua chanzo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Piga Picha'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Chagua Kutoka Gallery'),
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
          _selfieFile = File(file.path);
        } else {
          _idImageFile = File(file.path);
        }
      });
    }
  }

  Future<void> _submit() async {
    final fullName = _fullNameController.text.trim();
    final idNumber = _idNumberController.text.trim();

    if (fullName.isEmpty) {
      _showError('Tafadhali jaza jina lako kamili');
      return;
    }
    if (idNumber.isEmpty) {
      _showError('Tafadhali jaza namba ya kitambulisho');
      return;
    }
    if (_idImageFile == null) {
      _showError('Tafadhali pakia picha ya kitambulisho chako');
      return;
    }
    if (_selfieFile == null) {
      _showError('Tafadhali piga selfie yako');
      return;
    }

    setState(() => _submitting = true);

    try {
      final idImageUrl = await _uploadImage(_idImageFile!, 'id');
      final selfieUrl = await _uploadImage(_selfieFile!, 'selfie');

      if (idImageUrl == null || selfieUrl == null) {
        _showError('Imeshindwa kupakia picha. Angalia muunganisho wako.');
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
          _showSuccess('KYC imekubaliwa! Sasa unaweza kuuza bidhaa.');
        } else {
          _showSuccess('KYC imetumwa. Sababu: ${result['reason'] ?? 'Inakaguliwa...'}');
        }
        _loadStatus();
      } else {
        _showError(result?['error'] ?? 'Imeshindwa kutuma KYC. Jaribu tena.');
      }
    } catch (e) {
      _showError('Kosa: $e');
    }

    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Uhalalishaji wa Akaunti (KYC)')),
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
              Icon(Icons.verified, size: 80, color: Colors.green.shade600),
              const SizedBox(height: 16),
              const Text('KYC Imekubaliwa', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Sasa unaweza kuuza bidhaa kwenye Soko Langu.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 15)),
              if (_kycIdImageUrl != null) ...[
                const SizedBox(height: 16),
                const Text('Kitambulisho:', style: TextStyle(fontWeight: FontWeight.w600)),
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
              Icon(Icons.hourglass_top, size: 80, color: Colors.orange.shade600),
              const SizedBox(height: 16),
              const Text('KYC Inakaguliwa', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Taarifa zako zinakaguliwa. Utapokea taarifa ukishakubaliwa.',
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
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.cancel, color: Colors.red.shade700, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _reviewNotes ?? 'KYC imekataliwa. Tuma tena baada ya kusahihisha.',
                    style: TextStyle(color: Colors.red.shade800),
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
          'Jaza taarifa zako za utambulisho',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          'Pakia picha ya kitambulisho chako na selfie kwa uthibitisho.',
          style: TextStyle(color: cs.onSurface.withAlpha(150), fontSize: 13),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _fullNameController,
          decoration: const InputDecoration(
            labelText: 'Jina Kamili',
            hintText: 'Kama ilivyo kwenye kitambulisho',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _idType,
          decoration: const InputDecoration(
            labelText: 'Aina ya Kitambulisho',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.badge),
          ),
          items: _idTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _idType = v ?? 'National ID'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _idNumberController,
          decoration: const InputDecoration(
            labelText: 'Namba ya Kitambulisho',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.numbers),
          ),
        ),
        const SizedBox(height: 24),
        // Image upload section
        Row(
          children: [
            Expanded(
              child: _buildImagePicker(
                label: 'Picha ya Kitambulisho',
                icon: Icons.credit_card,
                file: _idImageFile,
                imageUrl: _kycIdImageUrl,
                onPick: () => _pickImage(isSelfie: false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildImagePicker(
                label: 'Selfie Yako',
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
            label: Text(_submitting ? 'Inatuma...' : 'Tuma KYC'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF065535),
              foregroundColor: Colors.white,
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
    required File? file,
    required String? imageUrl,
    required VoidCallback onPick,
  }) {
    final hasImage = file != null || imageUrl != null;
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: hasImage ? Colors.transparent : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage ? Colors.green.shade400 : Colors.grey.shade300,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: hasImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: file != null
                        ? Image.file(file, width: double.infinity, height: 140, fit: BoxFit.cover)
                        : Image.network(imageUrl!, width: double.infinity, height: 140, fit: BoxFit.cover),
                  ),
                  if (file != null)
                    Positioned(
                      top: 4, right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 16),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 32, color: Colors.grey.shade400),
                  const SizedBox(height: 6),
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), textAlign: TextAlign.center),
                ],
              ),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }
}