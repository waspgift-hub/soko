import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../services/api_config.dart';
import '../../widgets/google_loading.dart';

class AdminKycScreen extends StatefulWidget {
  const AdminKycScreen({super.key});

  @override
  State<AdminKycScreen> createState() => _AdminKycScreenState();
}

class _AdminKycScreenState extends State<AdminKycScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final List<String> _tabs = ['pending', 'approved', 'rejected', 'revoked', 'all'];
  Map<String, List<Map<String, dynamic>>> _kycData = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        loadKycData();
      }
    });
    loadKycData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> loadKycData() async {
    setState(() => _loading = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/kyc/all'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final all = (body['all'] as List? ?? []).cast<Map<String, dynamic>>();
        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (final tab in _tabs) {
          grouped[tab] = [];
        }
        for (final user in all) {
          final kyc = user['kyc'] as Map<String, dynamic>? ?? {};
          final status = (kyc['status'] as String? ?? 'none').toLowerCase();
          if (status == 'approved') {
            grouped['approved']!.add(user);
            grouped['all']!.add(user);
          } else if (status == 'pending') {
            grouped['pending']!.add(user);
            grouped['all']!.add(user);
          } else if (status == 'rejected') {
            grouped['rejected']!.add(user);
            grouped['all']!.add(user);
          } else if (status == 'revoked') {
            grouped['revoked']!.add(user);
            grouped['all']!.add(user);
          } else {
            grouped['all']!.add(user);
          }
        }
        if (mounted) setState(() { _kycData = grouped; _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('AdminKycScreen.loadKycData: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KYC Management'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          tabs: _tabs.map((t) {
            final count = _kycData[t]?.length ?? 0;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.tr(t)),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: t == 'pending' ? Colors.orange.withValues(alpha: 0.2) : cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: t == 'pending' ? Colors.orange : cs.primary)),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: GoogleLoadingPage())
          : TabBarView(
              controller: _tabCtrl,
              children: _tabs.map((t) => _buildTabContent(cs, t)).toList(),
            ),
    );
  }

  Widget _buildTabContent(ColorScheme cs, String tab) {
    final users = _kycData[tab] ?? [];
    if (users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 64, color: Colors.green.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(context.tr('no_pending_kyc'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: loadKycData,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: users.length,
        itemBuilder: (_, i) => _buildKycCard(cs, users[i]),
      ),
    );
  }

  Widget _buildKycCard(ColorScheme cs, Map<String, dynamic> user) {
    final kyc = user['kyc'] as Map<String, dynamic>? ?? {};
    final uid = user['uid'] as String? ?? '';
    final fullName = kyc['fullName'] ?? user['displayName'] ?? context.tr('unknown');
    final email = user['email'] ?? '';
    final phone = user['phone'] ?? '';
    final idType = kyc['idType'] ?? '';
    final idNumber = kyc['idNumber'] ?? '';
    final status = kyc['status'] as String? ?? 'none';
    final submittedAt = kyc['submittedAt'] as String? ?? '';
    final reviewedAt = kyc['reviewedAt'] as String? ?? '';
    final reviewNotes = kyc['reviewNotes'] as String? ?? '';

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'revoked':
        statusColor = Colors.orange;
        statusIcon = Icons.block;
        break;
      default:
        statusColor = Colors.blue;
        statusIcon = Icons.hourglass_empty;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(fullName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.onSurface)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(status.toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _infoRow(Icons.email_outlined, email, cs),
            _infoRow(Icons.phone_outlined, phone, cs),
            _infoRow(Icons.badge_outlined, '$idType: $idNumber', cs),
            if (submittedAt.isNotEmpty)
              _infoRow(Icons.calendar_today, 'Submitted: $submittedAt', cs),
            if (reviewedAt.isNotEmpty)
              _infoRow(Icons.done_all, 'Reviewed: $reviewedAt', cs),
            if (reviewNotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Notes: $reviewNotes',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (status == 'pending') ...[
                  _actionButton(cs, 'Approve', Icons.check, Colors.green, () => _submitReview(uid, true, '')),
                  const SizedBox(width: 8),
                  _actionButton(cs, 'Reject', Icons.close, Colors.red, () => _showRejectDialog(uid)),
                  const SizedBox(width: 8),
                ],
                if (status == 'approved')
                  _actionButton(cs, 'Revoke', Icons.block, Colors.orange, () => _confirmRevoke(uid)),
                _actionButton(cs, 'View', Icons.visibility, Colors.blue, () => _showKycDetail(user)),
                const SizedBox(width: 8),
                _actionButton(cs, 'Delete', Icons.delete_forever, Colors.red.shade700, () => _confirmDelete(uid)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, ColorScheme cs) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(ColorScheme cs, String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: SizedBox(
        height: 36,
        child: OutlinedButton.icon(
          icon: Icon(icon, size: 16),
          label: Text(label, style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: onTap,
        ),
      ),
    );
  }

  void _showRejectDialog(String uid) {
    final notesCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject KYC'),
        content: TextField(
          controller: notesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Rejection reason (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Reject'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _submitReview(uid, false, notesCtrl.text);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _submitReview(String uid, bool approve, String notes) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/kyc/review'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'userId': uid, 'approve': approve, 'notes': notes}),
      ).timeout(const Duration(seconds: 10));

      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'KYC ${approve ? "approved" : "rejected"} successfully')),
          );
          loadKycData();
        }
      } else {
        throw Exception(result['error'] ?? 'Review failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _confirmRevoke(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke KYC'),
        content: const Text('Are you sure you want to revoke this KYC approval? The user will lose KYC benefits.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.block, size: 16),
            label: const Text('Revoke'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/kyc/revoke'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'userId': uid}),
      ).timeout(const Duration(seconds: 10));

      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'KYC revoked successfully')),
          );
          loadKycData();
        }
      } else {
        throw Exception(result['error'] ?? 'Revoke failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete KYC'),
        content: const Text('Are you sure you want to permanently delete this KYC data? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('Delete Permanently'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/kyc/delete'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'userId': uid}),
      ).timeout(const Duration(seconds: 10));

      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'KYC data deleted successfully')),
          );
          loadKycData();
        }
      } else {
        throw Exception(result['error'] ?? 'Delete failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showKycDetail(Map<String, dynamic> user) {
    final kyc = user['kyc'] as Map<String, dynamic>? ?? {};
    final idImageUrl = kyc['idImageUrl'] as String?;
    final selfieUrl = kyc['selfieUrl'] as String?;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('KYC Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (idImageUrl != null && idImageUrl.isNotEmpty) ...[
                const Text('ID Document:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(imageUrl: idImageUrl, height: 180, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 48)),
                ),
                const SizedBox(height: 12),
              ],
              if (selfieUrl != null && selfieUrl.isNotEmpty) ...[
                const Text('Selfie:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(imageUrl: selfieUrl, height: 180, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 48)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}
