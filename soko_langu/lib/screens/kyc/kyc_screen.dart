import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/kyc_service.dart';
import '../../services/cloudinary_service.dart';
import '../../widgets/google_loading.dart';
import '../../theme/app_colors.dart';
import '../../utils/phone_utils.dart';
import '../../extensions/context_tr.dart';

/// The verification document required by product: passport only. The value
/// matches the admin panel's translation key, not the legacy label, so the
/// v1 server's label-keyed format checks are skipped (by design).
const String _kIdType = 'kyc_id_passport';

/// Shop videos are capped well below Cloudinary's 100MB free-tier limit so
/// a mid-upload rejection stays rare on slow uplinks.
const int _kMaxVideoBytes = 90 * 1024 * 1024;

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _feePhoneController = TextEditingController();
  final _phoneOtpController = TextEditingController();
  final _emailOtpController = TextEditingController();

  DateTime? _dob;
  bool _submitting = false;
  String? _status;
  String? _reviewNotes;
  String? _kycIdImageUrl;
  String? _kycSelfieUrl;
  XFile? _idImageFile;
  XFile? _selfieFile;
  XFile? _videoFile;

  bool _phoneOtpSending = false;
  bool _phoneOtpVerifying = false;
  bool _phoneOtpSent = false;
  bool _phoneVerified = false;

  bool _emailOtpSending = false;
  bool _emailOtpVerifying = false;
  bool _emailOtpSent = false;
  bool _emailVerified = false;

  bool _feeLoading = true;
  bool _feeError = false;
  bool _feePaid = false;
  int _feeAmount = KycService.feeAmount;
  String _feeMethod = 'ussd_push';
  bool _feeInitiating = false;
  bool _feeWaiting = false;
  String? _billPayNumber;
  Timer? _feePollTimer;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _feePollTimer?.cancel();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _idNumberController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _feePhoneController.dispose();
    _phoneOtpController.dispose();
    _emailOtpController.dispose();
    super.dispose();
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
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      kyc = doc.data()?['kyc'] as Map<String, dynamic>?;
    }
    final fee = await KycService.getKycFeeStatus();
    if (!mounted) return;
    setState(() {
      _status = kyc?['status'] as String? ?? 'none';
      _reviewNotes = kyc?['reviewNotes'] as String?;
      _kycIdImageUrl = kyc?['idImageUrl'] as String?;
      _kycSelfieUrl = kyc?['selfieUrl'] as String?;
      _feePaid = fee['paid'] == true;
      _feeAmount = (fee['amount'] as num?)?.toInt() ?? KycService.feeAmount;
      _feeError = fee['error'] == true;
      _feeLoading = false;
      if (_feePaid) {
        _feePollTimer?.cancel();
        _feeWaiting = false;
      }
      _prefillFromKyc(kyc, user);
    });
  }

  /// Refills the form from a previous (rejected) application so the seller
  /// edits instead of retyping everything. Runs once — guarded by the
  /// first-name controller still being empty.
  void _prefillFromKyc(Map<String, dynamic>? kyc, User user) {
    if (_firstNameController.text.isNotEmpty) return;
    _firstNameController.text = kyc?['firstName'] as String? ?? '';
    _middleNameController.text = kyc?['middleName'] as String? ?? '';
    _lastNameController.text = kyc?['lastName'] as String? ?? '';
    if (_firstNameController.text.isEmpty) {
      final parts =
          (kyc?['fullName'] as String? ?? '').trim().split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        _firstNameController.text = parts[0];
        _middleNameController.text = parts[1];
        _lastNameController.text = parts.sublist(2).join(' ');
      }
    }
    _idNumberController.text = kyc?['idNumber'] as String? ?? '';
    final dob = kyc?['dateOfBirth'] as String?;
    if (dob != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob)) {
      _dob = DateTime.tryParse(dob);
    }
    _addressController.text = kyc?['address'] as String? ?? '';
    _phoneController.text = PhoneUtils.normalizeToLocal(
        kyc?['phone'] as String? ?? user.phoneNumber ?? '');
    _emailController.text = kyc?['email'] as String? ?? user.email ?? '';
    _feePhoneController.text = _phoneController.text;
  }

  Future<String?> _uploadImage(XFile file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return await CloudinaryService.uploadImage(file, folder: 'kyc/${user.uid}');
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<ImageSource?> _chooseSource({required String cameraLabel}) async {
    return showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('choose_source')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(cameraLabel),
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
  }

  Future<void> _pickImage({required bool isSelfie}) async {
    final source = await _chooseSource(cameraLabel: context.tr('take_photo'));
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

  Future<void> _pickVideo() async {
    final source = await _chooseSource(cameraLabel: context.tr('kyc_take_video'));
    if (source == null) return;

    final file = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 30),
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return;
    // Reject oversize videos before upload — Cloudinary would refuse them
    // anyway after minutes of uploading on a slow connection.
    final size = await file.length();
    if (size > _kMaxVideoBytes) {
      _showError(context.tr('kyc_video_too_large'));
      return;
    }
    setState(() => _videoFile = file);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      // 18+ is a hard product rule; the server re-checks on submission.
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _retryFeeLoad() async {
    setState(() => _feeLoading = true);
    final fee = await KycService.getKycFeeStatus();
    if (!mounted) return;
    setState(() {
      _feePaid = fee['paid'] == true;
      _feeAmount = (fee['amount'] as num?)?.toInt() ?? KycService.feeAmount;
      _feeError = fee['error'] == true;
      _feeLoading = false;
    });
  }

  Future<void> _payFee() async {
    final phone = _feePhoneController.text.trim();
    if (phone.isEmpty) {
      _showError(context.tr('kyc_enter_phone'));
      return;
    }
    setState(() => _feeInitiating = true);
    final result = await KycService.initiateKycFee(
      phone: PhoneUtils.toE164(phone),
      paymentMethod: _feeMethod,
    );
    if (!mounted) return;
    if (result['success'] != true) {
      _showError(result['error']?.toString() ?? context.tr('failed_to_submit_kyc'));
      setState(() => _feeInitiating = false);
      return;
    }
    if (result['alreadyPaid'] == true) {
      setState(() {
        _feePaid = true;
        _feeInitiating = false;
      });
      _showSuccess(context.tr('kyc_fee_paid'));
      return;
    }
    setState(() {
      _feeInitiating = false;
      _feeWaiting = true;
      if (_feeMethod == 'billpay') {
        _billPayNumber = result['billPayNumber']?.toString() ?? '';
      }
    });
    if (_feeMethod == 'ussd_push') {
      _showSuccess(context.tr('kyc_fee_ussd_sent'));
    }
    _startFeePolling();
  }

  void _startFeePolling() {
    _feePollTimer?.cancel();
    _feePollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkFeePaid(),
    );
  }

  Future<void> _checkFeePaid({bool manual = false}) async {
    final fee = await KycService.getKycFeeStatus();
    if (!mounted) return;
    if (fee['paid'] == true) {
      _feePollTimer?.cancel();
      setState(() {
        _feePaid = true;
        _feeWaiting = false;
      });
      _showSuccess(context.tr('kyc_fee_paid'));
    } else if (manual) {
      if (fee['error'] == true) {
        _showError(context.tr('network_error_try_again'));
      } else {
        _showError(context.tr('kyc_fee_not_paid_yet'));
      }
    }
  }

  void _copyControlNumber() {
    if (_billPayNumber == null || _billPayNumber!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _billPayNumber!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('kyc_fee_copied')),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _sendPhoneOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError(context.tr('kyc_enter_phone'));
      return;
    }
    setState(() => _phoneOtpSending = true);
    final result = await KycService.sendPhoneOtp(phone);
    if (!mounted) return;
    setState(() {
      _phoneOtpSending = false;
      _phoneOtpSent = result['success'] == true && result['sent'] != false;
    });
    if (_phoneOtpSent) {
      _showSuccess(context.tr('kyc_otp_sent'));
    } else {
      _showError(
          result['error']?.toString() ?? context.tr('kyc_otp_send_failed'));
    }
  }

  Future<void> _verifyPhoneOtp() async {
    final otp = _phoneOtpController.text.trim();
    if (otp.isEmpty) {
      _showError(context.tr('kyc_enter_otp'));
      return;
    }
    setState(() => _phoneOtpVerifying = true);
    final result =
        await KycService.verifyPhoneOtp(_phoneController.text.trim(), otp);
    if (!mounted) return;
    setState(() {
      _phoneOtpVerifying = false;
      if (result['success'] == true) {
        _phoneVerified = true;
        _phoneOtpSent = false;
        _phoneOtpController.clear();
      }
    });
    if (result['success'] == true) {
      _showSuccess(context.tr('kyc_phone_verified'));
    } else {
      _showError(result['error']?.toString() ?? context.tr('kyc_otp_invalid'));
    }
  }

  Future<void> _sendEmailOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      _showError(context.tr('kyc_enter_email'));
      return;
    }
    setState(() => _emailOtpSending = true);
    final result = await KycService.sendEmailOtp(email);
    if (!mounted) return;
    setState(() {
      _emailOtpSending = false;
      _emailOtpSent = result['success'] == true && result['sent'] != false;
    });
    if (_emailOtpSent) {
      _showSuccess(context.tr('kyc_otp_sent'));
    } else {
      _showError(
          result['error']?.toString() ?? context.tr('kyc_otp_send_failed'));
    }
  }

  Future<void> _verifyEmailOtp() async {
    final otp = _emailOtpController.text.trim();
    if (otp.isEmpty) {
      _showError(context.tr('kyc_enter_otp'));
      return;
    }
    setState(() => _emailOtpVerifying = true);
    final result =
        await KycService.verifyEmailOtp(_emailController.text.trim(), otp);
    if (!mounted) return;
    setState(() {
      _emailOtpVerifying = false;
      if (result['success'] == true) {
        _emailVerified = true;
        _emailOtpSent = false;
        _emailOtpController.clear();
      }
    });
    if (result['success'] == true) {
      _showSuccess(context.tr('kyc_email_verified'));
    } else {
      _showError(result['error']?.toString() ?? context.tr('kyc_otp_invalid'));
    }
  }

  Future<void> _submit() async {
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final idNumber = _idNumberController.text.trim();
    final address = _addressController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (firstName.isEmpty) {
      _showError(context.tr('kyc_enter_first_name'));
      return;
    }
    if (middleName.isEmpty) {
      _showError(context.tr('kyc_enter_middle_name'));
      return;
    }
    if (lastName.isEmpty) {
      _showError(context.tr('kyc_enter_last_name'));
      return;
    }
    if (_dob == null) {
      _showError(context.tr('kyc_enter_dob'));
      return;
    }
    if (address.isEmpty) {
      _showError(context.tr('kyc_enter_address'));
      return;
    }
    if (phone.isEmpty) {
      _showError(context.tr('kyc_enter_phone'));
      return;
    }
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      _showError(context.tr('kyc_enter_email'));
      return;
    }
    if (!_phoneVerified) {
      _showError(context.tr('kyc_verify_phone_required'));
      return;
    }
    if (!_emailVerified) {
      _showError(context.tr('kyc_verify_email_required'));
      return;
    }
    if (idNumber.length < 6) {
      _showError(context.tr('kyc_passport_required'));
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
    if (_videoFile == null) {
      _showError(context.tr('kyc_upload_video_please'));
      return;
    }
    if (!_feePaid) {
      _showError(context.tr('kyc_fee_unpaid_error'));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);

    try {
      final idImageUrl = await _uploadImage(_idImageFile!);
      if (idImageUrl == null) {
        _showError(context.tr('kyc_id_image_upload_failed'));
        setState(() => _submitting = false);
        return;
      }
      final selfieUrl = await _uploadImage(_selfieFile!);
      if (selfieUrl == null) {
        _showError(context.tr('kyc_selfie_upload_failed'));
        setState(() => _submitting = false);
        return;
      }
      String? videoUrl;
      try {
        videoUrl = await CloudinaryService.uploadVideo(
          _videoFile!,
          folder: 'kyc/${user.uid}',
        );
      } catch (e) {
        debugPrint('KYC video upload error: $e');
      }
      if (videoUrl == null) {
        _showError(context.tr('kyc_video_upload_failed'));
        setState(() => _submitting = false);
        return;
      }

      final result = await KycService.submitKyc(
        userId: user.uid,
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        idType: _kIdType,
        idNumber: idNumber,
        idImageUrl: idImageUrl,
        selfieUrl: selfieUrl,
        dateOfBirth: DateFormat('yyyy-MM-dd').format(_dob!),
        address: address,
        phone: PhoneUtils.toE164(phone),
        email: email,
        shopVideoUrl: videoUrl,
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
      } else if (result?['code'] == 'KYC_FEE_UNPAID') {
        // The webhook can race the poll — refresh the receipt before re-gating.
        _checkFeePaid();
        _showError(context.tr('kyc_fee_unpaid_error'));
      } else {
        _showError(result?['error']?.toString() ?? context.tr('failed_to_submit_kyc'));
      }
    } catch (e) {
      _showError(context.trParams('imeshindwa', {'0': e.toString()}));
    }

    if (mounted) setState(() => _submitting = false);
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
              Icon(Icons.verified, size: 80, color: cs.primary),
              const SizedBox(height: 16),
              Text(context.tr('kyc_approved'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(context.tr('kyc_approved_desc'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
              if (_kycIdImageUrl != null) ...[
                const SizedBox(height: 16),
                Text(context.tr('identification_label'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
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
              Icon(Icons.hourglass_top, size: 80, color: cs.tertiary),
              const SizedBox(height: 16),
              Text(context.tr('kyc_pending'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(context.tr('kyc_pending_desc'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
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
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.cancel, color: cs.error, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _reviewNotes ?? context.tr('kyc_rejected_default'),
                    style: TextStyle(color: cs.error),
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
        _buildFeeCard(cs),
        const SizedBox(height: 24),
        TextField(
          controller: _firstNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: context.tr('kyc_first_name'),
            hintText: context.tr('as_on_id'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _middleNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: context.tr('kyc_middle_name'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lastNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: context.tr('kyc_last_name'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person_search),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickDob,
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: context.tr('kyc_dob_label'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.calendar_month),
            ),
            child: Text(
              _dob == null
                  ? context.tr('kyc_dob_hint')
                  : DateFormat('dd/MM/yyyy').format(_dob!),
              style: _dob == null
                  ? TextStyle(color: cs.onSurfaceVariant)
                  : TextStyle(color: cs.onSurface),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _addressController,
          maxLines: 2,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: context.tr('kyc_address_label'),
            hintText: context.tr('kyc_address_hint'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 10,
          decoration: InputDecoration(
            labelText: context.tr('kyc_phone_label'),
            hintText: '0712 345 678',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.phone),
            counterText: '',
            suffixIcon: _phoneVerified
                ? Icon(Icons.verified, color: cs.successGreen)
                : _buildVerifySuffixIcon(
                    sending: _phoneOtpSending, onVerify: _sendPhoneOtp),
          ),
        ),
        _buildOtpField(
          visible: _phoneOtpSent,
          controller: _phoneOtpController,
          verifying: _phoneOtpVerifying,
          onVerify: _verifyPhoneOtp,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: context.tr('kyc_email_label'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.email_outlined),
            suffixIcon: _emailVerified
                ? Icon(Icons.verified, color: cs.successGreen)
                : _buildVerifySuffixIcon(
                    sending: _emailOtpSending, onVerify: _sendEmailOtp),
          ),
        ),
        _buildOtpField(
          visible: _emailOtpSent,
          controller: _emailOtpController,
          verifying: _emailOtpVerifying,
          onVerify: _verifyEmailOtp,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _idNumberController,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
          maxLength: 20,
          decoration: InputDecoration(
            labelText: context.tr('kyc_passport_number'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.book_outlined),
            counterText: '',
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _buildImagePicker(
                label: context.tr('kyc_passport_image'),
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
        const SizedBox(height: 16),
        Text(
          context.tr('kyc_shop_video'),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('kyc_shop_video_desc'),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        _buildVideoPicker(cs),
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
              backgroundColor: cs.successGreen,
              foregroundColor: cs.surface,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildVerifySuffixIcon({
    required bool sending,
    required VoidCallback onVerify,
  }) {
    if (sending) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return TextButton(
      onPressed: onVerify,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(context.tr('verify')),
    );
  }

  Widget _buildOtpField({
    required bool visible,
    required TextEditingController controller,
    required bool verifying,
    required Future<void> Function() onVerify,
  }) {
    if (!visible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: context.tr('kyc_otp_label'),
                  hintText: '0 0 0 0 0 0',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.password, size: 20),
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: verifying ? null : onVerify,
              style: FilledButton.styleFrom(
                foregroundColor: cs.surface,
                backgroundColor: cs.successGreen,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: verifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.tr('verify')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeeCard(ColorScheme cs) {
    final amount = NumberFormat('#,##0', 'en_US').format(_feeAmount);

    if (_feeLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: GoogleLoading(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(context.tr('kyc_fee_title')),
          ],
        ),
      );
    }

    if (_feeError) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.error.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: cs.error, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('kyc_fee_load_failed'),
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _retryFeeLoad,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(context.tr('kyc_fee_retry')),
            ),
          ],
        ),
      );
    }

    if (_feePaid) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.successGreen.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.successGreen.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: cs.successGreen, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('kyc_fee_paid'),
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: cs.successGreen),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr('kyc_fee_paid_desc'),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_outlined, color: cs.primary, size: 24),
              const SizedBox(width: 8),
              Text(context.tr('kyc_fee_title'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('TZS $amount',
                  style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('kyc_fee_one_time'),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(context.tr('kyc_fee_method_ussd')),
                selected: _feeMethod == 'ussd_push',
                onSelected: (_) => setState(() {
                  _feeMethod = 'ussd_push';
                  _billPayNumber = null;
                }),
              ),
              ChoiceChip(
                label: Text(context.tr('kyc_fee_method_billpay')),
                selected: _feeMethod == 'billpay',
                onSelected: (_) => setState(() => _feeMethod = 'billpay'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _feePhoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 10,
            decoration: InputDecoration(
              labelText: context.tr('kyc_phone_label'),
              hintText: '0712 345 678',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.phone_android),
              counterText: '',
              isDense: true,
            ),
          ),
          if (_feeWaiting) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: GoogleLoading(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('kyc_fee_waiting'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
          if (_billPayNumber != null && _billPayNumber!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(context.tr('kyc_fee_control_number_label'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _billPayNumber!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 1.2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: _copyControlNumber,
                    tooltip: context.tr('kyc_fee_copy'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('kyc_fee_billpay_instructions'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          if (!_feeWaiting)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _feeInitiating ? null : _payFee,
                icon: _feeInitiating
                    ? const GoogleLoading(size: 20, strokeWidth: 2)
                    : const Icon(Icons.payments),
                label: Text(
                  _feeInitiating
                      ? context.tr('submitting')
                      : _feeMethod == 'billpay'
                          ? context.tr('kyc_fee_get_control')
                          : context.trParams('kyc_fee_pay_button', {'0': amount}),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _checkFeePaid(manual: true),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(context.tr('kyc_fee_check_again')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoPicker(ColorScheme cs) {
    final hasVideo = _videoFile != null;
    return GestureDetector(
      onTap: _pickVideo,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: hasVideo
              ? cs.primary.withValues(alpha: 0.08)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasVideo ? cs.primary.withValues(alpha: 0.6) : cs.outline,
            width: hasVideo ? 2 : 1,
          ),
        ),
        child: hasVideo
            ? Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(Icons.videocam, size: 32, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('kyc_video_selected'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          _videoFile!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(Icons.check_circle, color: cs.successGreen),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_outlined,
                      size: 32, color: cs.onSurfaceVariant),
                  const SizedBox(height: 6),
                  Text(context.tr('kyc_video_record'),
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
      ),
    );
  }

  Widget _buildImagePicker({
    required String label,
    required IconData icon,
    required XFile? file,
    required String? imageUrl,
    required VoidCallback onPick,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hasImage = file != null || imageUrl != null;
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: hasImage ? Colors.transparent : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage ? cs.primary.withValues(alpha: 0.6) : cs.outline,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: hasImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: file != null
                        ? Image.file(File(file.path),
                            width: double.infinity, height: 140, fit: BoxFit.cover)
                        : Image.network(imageUrl!,
                            width: double.infinity, height: 140, fit: BoxFit.cover),
                  ),
                  if (file != null)
                    Positioned(
                      top: 4, right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check, color: cs.surface, size: 16),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 32, color: cs.onSurfaceVariant),
                  const SizedBox(height: 6),
                  Text(label,
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center),
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
