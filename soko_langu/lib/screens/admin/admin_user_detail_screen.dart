import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../../extensions/context_tr.dart';
import '../../services/api_config.dart';
import '../../widgets/google_loading.dart';

class AdminUserDetailScreen extends StatefulWidget {
  final String uid;
  const AdminUserDetailScreen({super.key, required this.uid});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  Map<String, dynamic>? _userData;
  List<dynamic> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/user-detail/${widget.uid}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (resp.statusCode != 200) {
        throw Exception(jsonDecode(resp.body)['error'] ?? 'Failed to load');
      }
      final data = jsonDecode(resp.body);
      setState(() {
        _userData = data['user'] as Map<String, dynamic>?;
        _orders = data['orders'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updateUser(Map<String, dynamic> updates) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/users/${widget.uid}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'updates': updates}),
      );
      if (resp.statusCode != 200) {
        throw Exception(jsonDecode(resp.body)['error'] ?? 'Update failed');
      }
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(updates.containsKey('isSuspended')
              ? (updates['isSuspended'] ? context.tr('user_suspended') : context.tr('user_unsuspended'))
              : context.tr('user_updated'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('imeshindwa')}: $e')),
        );
      }
    }
  }

  Future<void> _fullDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_user_forever')),
        content: Text(context.tr('delete_user_forever_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.tr('delete_forever'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/users/${widget.uid}/full-delete'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (resp.statusCode != 200) {
        throw Exception(jsonDecode(resp.body)['error'] ?? 'Delete failed');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('user_permanently_deleted'))),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('imeshindwa')}: $e')),
        );
      }
    }
  }

  void _showKycReview() {
    final kyc = _userData?['kyc'] as Map<String, dynamic>?;
    if (kyc == null) return;
    final fullName = kyc['fullName'] ?? '';
    final idType = kyc['idType'] ?? '';
    final idNumber = kyc['idNumber'] ?? '';
    final idImageUrl = kyc['idImageUrl'] as String?;
    final selfieUrl = kyc['selfieUrl'] as String?;
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('review_kyc')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${context.tr('full_name')}: $fullName', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${context.tr('id_type')}: $idType'),
              Text('${context.tr('number')}: $idNumber'),
              if (idImageUrl != null) ...[
                const SizedBox(height: 8),
                Text(context.tr('identification_label')),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(imageUrl: idImageUrl, height: 120, fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.broken_image)),
                ),
              ],
              if (selfieUrl != null) ...[
                const SizedBox(height: 8),
                Text(context.tr('selfie_label')),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(imageUrl: selfieUrl, height: 120, fit: BoxFit.cover, errorWidget: (_, _, _) => const Icon(Icons.broken_image)),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.tr('rejection_reason_label'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          ElevatedButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: Text(context.tr('reject')),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _submitKycReview(false, notesCtrl.text);
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 16),
            label: Text(context.tr('approve')),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _submitKycReview(true, notesCtrl.text);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _submitKycReview(bool approve, String notes) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/kyc/review'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'userId': widget.uid, 'approve': approve, 'notes': notes}),
      );
      if (resp.statusCode == 200) {
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(jsonDecode(resp.body)['message'] ?? context.tr('kyc_status'))),
          );
        }
      } else {
        throw Exception(jsonDecode(resp.body)['error'] ?? context.tr('kyc_review_failed'));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('imeshindwa').replaceAll('{0}', '$e'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('user_details'))),
      body: _loading
          ? const GoogleLoadingPage()
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: TextStyle(color: cs.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadData, child: Text(context.tr('retry'))),
                    ],
                  ),
                )
              : _buildContent(cs),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    final user = _userData ?? {};
    final name = user['displayName'] ?? user['name'] ?? '';
    final email = user['email'] ?? '';
    final phone = user['phone'] ?? '';
    final suspended = user['isSuspended'] == true;
    final isAdmin = user['isAdmin'] == true;
    final kyc = user['kyc'] as Map<String, dynamic>?;
    final kycStatus = kyc?['status'] as String? ?? 'none';
    final sellerBalance = (user['sellerBalance'] ?? 0).toDouble();
    final pendingEscrow = (user['pendingEscrow'] ?? 0).toDouble();
    final totalSales = (user['totalSales'] ?? 0).toInt();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProfileHeader(cs, name, email, phone, suspended, isAdmin),
          const SizedBox(height: 16),
          _buildKycSection(cs, kyc, kycStatus),
          const SizedBox(height: 12),
          _buildAccountActions(cs, suspended),
          const SizedBox(height: 12),
          _buildBalanceSection(cs, sellerBalance, pendingEscrow, totalSales),
          const SizedBox(height: 12),
          if (_orders.isNotEmpty) _buildOrdersSection(cs),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(ColorScheme cs, String name, String email, String phone, bool suspended, bool admin) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: suspended ? cs.error : cs.primary,
              child: Text(
                (name.toString().isNotEmpty ? name.toString()[0] : '?').toUpperCase(),
                style: TextStyle(fontSize: 28, color: cs.surface),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (email.isNotEmpty) Text(email.toString(), style: TextStyle(color: cs.onSurfaceVariant)),
                  if (phone.isNotEmpty) Text(phone.toString(), style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (suspended) Chip(label: Text(context.tr('suspended'), style: const TextStyle(fontSize: 11, color: Colors.white)), backgroundColor: cs.error, padding: EdgeInsets.zero, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      if (admin) ...[
                        if (suspended) const SizedBox(width: 8),
                        Chip(label: Text('Admin', style: const TextStyle(fontSize: 11)), backgroundColor: cs.primary.withValues(alpha: 0.2), padding: EdgeInsets.zero, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKycSection(ColorScheme cs, Map<String, dynamic>? kyc, String status) {
    final statusColor = status == 'approved' ? Colors.green : (status == 'rejected' ? Colors.red : Colors.orange);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(context.tr('kyc_status'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Chip(
                  label: Text(status.toUpperCase(), style: TextStyle(fontSize: 11, color: statusColor)),
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            if (kyc != null) ...[
              const SizedBox(height: 8),
              _infoRow(context.tr('full_name'), kyc['fullName'] ?? '-'),
              _infoRow(context.tr('id_type'), kyc['idType'] ?? '-'),
              _infoRow(context.tr('number'), kyc['idNumber'] ?? '-'),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.rate_review, size: 18),
                label: Text(context.tr('review_kyc')),
                onPressed: (status == 'pending' || status == 'none') ? _showKycReview : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountActions(ColorScheme cs, bool suspended) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('account_actions'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(suspended ? Icons.lock_open : Icons.lock, size: 18),
                    label: Text(suspended ? context.tr('unsuspend') : context.tr('suspend')),
                    style: OutlinedButton.styleFrom(foregroundColor: suspended ? Colors.green : Colors.red),
                    onPressed: () => _updateUser({'isSuspended': !suspended}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.admin_panel_settings, size: 18),
                    label: const Text('Toggle Admin'),
                    onPressed: () => _updateUser({'isAdmin': !(_userData?['isAdmin'] == true)}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever, size: 18, color: Colors.red),
                label: Text(context.tr('full_delete'), style: const TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                onPressed: _fullDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceSection(ColorScheme cs, double balance, double escrow, int sales) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('financials'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _statTile(cs, 'Seller Balance', 'TZS ${balance.toStringAsFixed(0)}', Icons.account_balance_wallet, cs.primary)),
                const SizedBox(width: 8),
                Expanded(child: _statTile(cs, 'Pending Escrow', 'TZS ${escrow.toStringAsFixed(0)}', Icons.lock, Colors.orange)),
                const SizedBox(width: 8),
                Expanded(child: _statTile(cs, 'Total Sales', '$sales', Icons.shopping_bag, Colors.green)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersSection(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('recent_orders'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...(_orders.take(10).map((o) {
              final order = o as Map<String, dynamic>;
              return ListTile(
                dense: true,
                leading: Icon(Icons.receipt, color: cs.primary),
                title: Text(order['productName'] ?? 'Product', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('TZS ${(order['productPrice'] ?? 0).toStringAsFixed(0)} — ${order['status'] ?? '?'}'),
                trailing: Text(order['createdAt']?.toString()?.substring(0, 10) ?? ''),
              );
            })),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _statTile(ColorScheme cs, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
