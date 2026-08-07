import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ignore: unused_import
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../extensions/context_tr.dart';
import '../../services/api_config.dart';
import '../../widgets/google_loading.dart';
import 'admin_kyc_document_view_screen.dart';

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

  Future<void> _showKycReview() async {
    final user = <String, dynamic>{'uid': widget.uid, ...?_userData};
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminKycDocumentViewScreen(user: user)),
    );
    if (changed == true) _loadData();
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
    final policyWarnings = (user['policyWarnings'] as num?)?.toInt() ?? 0;
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
          _buildAccountActions(cs, suspended, policyWarnings),
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
                        Chip(label: Text(context.tr('admin'), style: const TextStyle(fontSize: 11)), backgroundColor: cs.primary.withValues(alpha: 0.2), padding: EdgeInsets.zero, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
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

  Widget _buildAccountActions(ColorScheme cs, bool suspended, int policyWarnings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(context.tr('account_actions'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Chip(
                  label: Text(
                    policyWarnings >= 3
                        ? context.tr('account_blocked')
                        : context.trParams('warnings_x_of_3', {'count': '$policyWarnings'}),
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  backgroundColor: policyWarnings >= 3 ? Colors.red : (policyWarnings > 0 ? Colors.orange : Colors.grey),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
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
                    label: Text(context.tr('toggle_admin')),
                    onPressed: () => _updateUser({'isAdmin': !(_userData?['isAdmin'] == true)}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.warning_amber, size: 18, color: Colors.orange),
                    label: Text(context.tr('send_warning')),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                    onPressed: policyWarnings >= 3 ? null : _showWarningDialog,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.send, size: 18),
                    label: Text(context.tr('send_message')),
                    onPressed: _showSendMessageDialog,
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

  void _showWarningDialog() {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('send_warning')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('warning_will_block_after_3')),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.tr('warning_reason'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => _sendWarning(ctx, reasonCtrl.text),
            child: Text(context.tr('send_warning'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _sendWarning(BuildContext ctx, String reason) async {
    if (reason.trim().isEmpty) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(context.tr('warning_reason_required'))),
        );
      }
      return;
    }
    Navigator.pop(ctx);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/users/${widget.uid}/warn'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'reason': reason.trim()}),
      );
      if (resp.statusCode != 200) {
        throw Exception(jsonDecode(resp.body)['error'] ?? 'Warning failed');
      }
      final data = jsonDecode(resp.body);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['blocked'] == true
              ? context.tr('warning_sent_blocked')
              : context.tr('warning_sent'))),
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

  void _showSendMessageDialog() {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('send_message')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: context.tr('title'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: context.tr('message'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => _sendMessage(ctx, titleCtrl.text, bodyCtrl.text),
            child: Text(context.tr('send')),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(BuildContext ctx, String title, String body) async {
    if (title.trim().isEmpty) return;
    Navigator.pop(ctx);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/send-notification'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': widget.uid,
          'title': title.trim(),
          'body': body.trim(),
          'type': 'system',
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resp.statusCode == 200
                ? context.tr('message_sent')
                : '${context.tr('imeshindwa')}: ${jsonDecode(resp.body)['error'] ?? resp.statusCode}'),
          ),
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
                Expanded(child: _statTile(cs, context.tr('seller_balance'), 'TZS ${balance.toStringAsFixed(0)}', Icons.account_balance_wallet, cs.primary)),
                const SizedBox(width: 8),
                Expanded(child: _statTile(cs, context.tr('pending_escrow'), 'TZS ${escrow.toStringAsFixed(0)}', Icons.lock, Colors.orange)),
                const SizedBox(width: 8),
                Expanded(child: _statTile(cs, context.tr('total_sales'), '$sales', Icons.shopping_bag, Colors.green)),
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
                title: Text(order['productName'] ?? context.tr('product'), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('TZS ${(order['productPrice'] ?? 0).toStringAsFixed(0)} — ${order['status'] ?? '?'}'),
                trailing: Text(order['createdAt'].toString().substring(0, 10)),
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
