import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../extensions/context_tr.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('admin_dashboard')),
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStats(),
              const SizedBox(height: 24),
              Text(
                context.tr('recent_users'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildRecentUsers(),
              const SizedBox(height: 24),
              Text(
                context.tr('recent_products'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildRecentProducts(),
              const SizedBox(height: 24),
              Text(
                context.tr('pending_verifications'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildPendingVerifications(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats() {
    return FutureBuilder<int>(
      future: _db.collection('users').count().get().then((s) => s.count ?? 0),
      builder: (context, userSnap) {
        return FutureBuilder<int>(
          future: _db.collection('products').count().get().then((s) => s.count ?? 0),
          builder: (context, productSnap) {
            return FutureBuilder<int>(
              future: _db.collection('orders').count().get().then((s) => s.count ?? 0),
              builder: (context, orderSnap) {
                final userCount = userSnap.data ?? 0;
                final productCount = productSnap.data ?? 0;
                final orderCount = orderSnap.data ?? 0;

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    _statCard(Icons.people, userCount.toString(), context.tr('total_users'), Colors.blue),
                    _statCard(Icons.inventory_2, productCount.toString(), context.tr('total_products'), Colors.green),
                    _statCard(Icons.shopping_bag, orderCount.toString(), context.tr('total_orders'), Colors.orange),
                    _statCard(Icons.rocket_launch, '0', context.tr('boosted_products'), Colors.red),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _statCard(IconData icon, String value, String label, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentUsers() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').orderBy('premiumUntil', descending: true).limit(5).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = snap.data!.docs;
        if (users.isEmpty) {
          return Text(context.tr('no_users_yet'), style: TextStyle(color: Colors.grey[500]));
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: users.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = users[index].data() as Map<String, dynamic>;
            final name = data['displayName'] ?? 'No name';
            final email = data['email'] ?? '';
            final tier = data['accountTier'] ?? 'free';
            final isVerified = data['isVerified'] == true;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: tier == 'premium' ? Colors.amber : (tier == 'silver' ? Colors.blueGrey : Colors.grey),
                child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
              ),
              title: Text(name),
              subtitle: Text(email),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isVerified) const Icon(Icons.verified, color: Colors.blue, size: 18),
                  const SizedBox(width: 4),
                  Text(tier.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRecentProducts() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('products').orderBy('createdAt', descending: true).limit(5).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final products = snap.data!.docs;
        if (products.isEmpty) {
          return Text(context.tr('no_products_yet'), style: TextStyle(color: Colors.grey[500]));
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: products.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = products[index].data() as Map<String, dynamic>;
            final name = data['name'] ?? 'No name';
            final price = (data['price'] ?? 0).toStringAsFixed(0);
            final seller = data['sellerName'] ?? '';
            final isActive = data['isActive'] ?? true;

            return ListTile(
              leading: Icon(Icons.shopping_bag, color: isActive ? Colors.green : Colors.grey),
              title: Text(name),
              subtitle: Text('$seller - TSh $price'),
              trailing: Text(isActive ? 'Active' : 'Inactive',
                  style: TextStyle(color: isActive ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
            );
          },
        );
      },
    );
  }

  Widget _buildPendingVerifications() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').where('accountTier', whereIn: ['silver', 'premium']).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = snap.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return (data['isVerified'] ?? false) == false;
        }).toList();

        if (users.isEmpty) {
          return Text(context.tr('no_pending_verifications'), style: TextStyle(color: Colors.grey[500]));
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: users.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = users[index].data() as Map<String, dynamic>;
            final name = data['displayName'] ?? 'No name';
            final tier = data['accountTier'] ?? 'free';
            final uid = users[index].id;

            return ListTile(
              leading: const Icon(Icons.shield_outlined, color: Colors.orange),
              title: Text(name),
              subtitle: Text(tier.toUpperCase()),
              trailing: ElevatedButton(
                onPressed: () async {
                  await _db.collection('users').doc(uid).update({'isVerified': true});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('Verify'),
              ),
            );
          },
        );
      },
    );
  }
}
