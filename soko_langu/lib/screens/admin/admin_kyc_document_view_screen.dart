import 'dart:convert';
import '../../widgets/product_cached_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../extensions/context_tr.dart';
import '../../services/api_config.dart';
import '../../widgets/google_loading.dart';

class KycDocument {
  const KycDocument({required this.label, required this.url});

  final String label;
  final String url;
}

/// Full-screen reviewer for a seller's submitted KYC documents.
///
/// Shows the ID document + selfie (and any extra documents) submitted by the
/// seller so the admin can inspect them and approve/reject/revoke in place.
/// Falls back to Firestore when the admin API payload omits the image URLs.
class AdminKycDocumentViewScreen extends StatefulWidget {
  const AdminKycDocumentViewScreen({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<AdminKycDocumentViewScreen> createState() =>
      _AdminKycDocumentViewScreenState();
}

class _AdminKycDocumentViewScreenState
    extends State<AdminKycDocumentViewScreen> {
  Map<String, dynamic> _kyc = {};
  bool _loading = true;
  bool _submitting = false;

  String get _uid => widget.user['uid'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _kyc = widget.user['kyc'] as Map<String, dynamic>? ?? {};
    _loadFromFirestore();
  }

  Future<void> _loadFromFirestore() async {
    if (_uid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // Firestore is the source of truth for submitted docs; merge over the
      // admin API payload in case the backend omits image URLs.
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final kyc = doc.data()?['kyc'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        if (kyc != null) _kyc = {..._kyc, ...kyc};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<KycDocument> get _documents {
    final docs = <KycDocument>[];
    final seen = <String>{};
    void add(String label, Object? url) {
      if (url is String && url.isNotEmpty && seen.add(url)) {
        docs.add(KycDocument(label: label, url: url));
      }
    }

    add(context.tr('id_document'), _kyc['idImageUrl']);
    add(context.tr('id_document'), _kyc['idDocumentUrl']);
    add(context.tr('selfie'), _kyc['selfieUrl']);
    add(context.tr('document'), _kyc['addressProofUrl']);
    add(context.tr('document'), _kyc['businessLicenseUrl']);
    final rawDocs = _kyc['documents'];
    if (rawDocs is List) {
      for (final d in rawDocs) {
        if (d is Map) {
          final label = d['label'] ?? d['name'] ?? context.tr('document');
          add(label.toString(), d['url'] ?? d['imageUrl'] ?? d['path']);
        }
      }
    }
    return docs;
  }

  String get _status {
    return (_kyc['status'] as String? ?? 'none').toLowerCase();
  }

  (Color, IconData) get _statusStyle {
    switch (_status) {
      case 'approved':
        return (Colors.green, Icons.check_circle);
      case 'rejected':
        return (Colors.red, Icons.cancel);
      case 'revoked':
        return (Colors.orange, Icons.block);
      default:
        return (Colors.blue, Icons.hourglass_empty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (statusColor, statusIcon) = _statusStyle;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('kyc_documents')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: GoogleLoadingPage())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeader(cs, statusColor, statusIcon),
                const SizedBox(height: 16),
                _buildInfoCard(cs),
                const SizedBox(height: 16),
                _buildDocumentsSection(cs),
              ],
            ),
      bottomNavigationBar: _buildActions(cs),
    );
  }

  Widget _buildHeader(ColorScheme cs, Color statusColor, IconData statusIcon) {
    final fullName = _kyc['fullName'] ?? widget.user['displayName'] ?? '';
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Icon(statusIcon, color: statusColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fullName.toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _status == 'none'
                    ? context.tr('kyc_not_submitted')
                    : context.tr(_status),
                style: TextStyle(fontSize: 12, color: statusColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(ColorScheme cs) {
    final rows = <(IconData, String)>[
      (Icons.badge_outlined,
          '${_kyc['idType'] ?? '-'}: ${_kyc['idNumber'] ?? '-'}'),
      (Icons.email_outlined, widget.user['email']?.toString() ?? '-'),
      (Icons.phone_outlined, widget.user['phone']?.toString() ?? '-'),
      if (_kyc['submittedAt'] != null &&
          (_kyc['submittedAt'] as String).isNotEmpty)
        (Icons.calendar_today,
            context.trParams('submitted_at', {'date': _kyc['submittedAt'].toString()})),
      if (_kyc['reviewedAt'] != null &&
          (_kyc['reviewedAt'] as String).isNotEmpty)
        (Icons.done_all,
            context.trParams('reviewed_at', {'date': _kyc['reviewedAt'].toString()})),
    ];
    final notes = _kyc['reviewNotes'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('account_information'),
            style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
          ),
          const SizedBox(height: 10),
          for (final (icon, text) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          if (notes.isNotEmpty) ...[
            const Divider(height: 20),
            Text(
              context.trParams('review_notes', {'notes': notes}),
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentsSection(ColorScheme cs) {
    final docs = _documents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder_open, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              '${context.tr('documents')} (${docs.length})',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (docs.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.folder_off_outlined,
                    size: 40, color: cs.onSurfaceVariant),
                const SizedBox(height: 8),
                Text(
                  context.tr('no_documents'),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          )
        else
          ...docs.map(
            (doc) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildDocumentCard(cs, doc),
            ),
          ),
      ],
    );
  }

  Widget _buildDocumentCard(ColorScheme cs, KycDocument doc) {
    return Material(
      color: cs.surfaceContainerLow.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openFullScreen(doc.url),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ProductCachedImage(
                  url: doc.url,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.tr('tap_to_zoom'),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.zoom_in, size: 20, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  void _openFullScreen(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: ProductCachedImage(
                  url: url,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildActions(ColorScheme cs) {
    final pending = _status == 'pending';
    final approved = _status == 'approved';
    final rejected = _status == 'rejected';
    if (!pending && !approved && !rejected) return null;
    if (_submitting) {
      return const SafeArea(child: Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ));
    }
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          if (pending || rejected) ...[
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.close, size: 18),
                label: Text(context.tr('reject')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: _submitting ? null : _showRejectDialog,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: Text(context.tr('approve')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: _submitting ? null : () => _submitReview(true, ''),
              ),
            ),
          ] else if (approved)
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.block, size: 18),
                label: Text(context.tr('revoke')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: _submitting ? null : _confirmRevoke,
              ),
            ),
        ],
      ),
    );
  }

  void _showRejectDialog() {
    final notesCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('reject_kyc_title')),
        content: TextField(
          controller: notesCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: context.tr('rejection_reason'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: Text(context.tr('reject')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _submitReview(false, notesCtrl.text);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _submitReview(bool approve, String notes) async {
    if (_uid.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/kyc/review'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': _uid,
          'approve': approve,
          'notes': notes,
        }),
      ).timeout(const Duration(seconds: 10));

      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? context.tr('kyc_review_complete'),
              ),
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(result['error'] ?? context.tr('failed_text'));
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('error_occurred')}: $e')),
        );
      }
    }
  }

  Future<void> _confirmRevoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('revoke_kyc')),
        content: Text(context.tr('revoke_kyc_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.block, size: 16),
            label: Text(context.tr('revoke')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || _uid.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/kyc/revoke'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'userId': _uid}),
      ).timeout(const Duration(seconds: 10));

      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? context.tr('kyc_revoked')),
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(result['error'] ?? context.tr('failed_text'));
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('error_occurred')}: $e')),
        );
      }
    }
  }
}
