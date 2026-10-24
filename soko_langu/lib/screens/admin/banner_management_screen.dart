import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:soko_langu/lib/services/banner/banner_admin.dart';
import 'package:soko_langu/lib/services/banner/banner_campaign.dart';
import 'package:soko_langu/lib/extensions/context_tr.dart';

/// Admin banner management screen.
class AdminBannerManagementScreen extends ConsumerStatefulWidget {
  const AdminBannerManagementScreen({super.key});

  @override
  ConsumerState<AdminBannerManagementScreen> createState() =>
      _AdminBannerManagementScreenState();
}

class _AdminBannerManagementScreenState extends ConsumerState<AdminBannerManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AdminBannerQuery _query = const AdminBannerQuery();
  AdminBannerListResponse? _bannerList;
  bool _isLoading = false;
  String? _error;
  int _currentPage = 1;
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBanners();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBanners({bool refresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // This would call the API
      // final response = await BannerAdminApi.instance.listBanners(query: _query);
      // setState(() { _bannerList = response; });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('banner_management')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: context.tr('all_banners')),
            Tab(text: context.tr('drafts')),
            Tab(text: context.tr('archived')),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateBannerDialog,
            tooltip: 'Create Banner',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadBanners(refresh: true),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(context.tr('failed_to_load')),
                      const SizedBox(height: 8),
                      Text(_error!, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => _loadBanners(refresh: true),
                        child: Text(context.tr('retry')),
                      ),
                    ],
                  )
              : _bannerList == null
                  ? Center(child: Text(context.tr('no_banners_found')))
                  : _buildBannerList(),
    );
  }

  Widget _buildBannerList() {
    final banners = _bannerList?.banners ?? [];

    if (banners.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(context.tr('no_banners_found')),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _showCreateBannerDialog,
              icon: const Icon(Icons.add),
              label: Text('Create First Banner'),
            ),
          ],
        );
      }

      return RefreshIndicator(
        onRefresh: () => _loadBanners(refresh: true),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: (_bannerList?.banners.length ?? 0) + (_hasMorePages ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == (_bannerList?.banners.length ?? 0)) {
              return _buildLoadMoreButton();
            }
            final banner = (_bannerList?.banners ?? [])[index];
            return _buildBannerCard(banner as Map<String, dynamic>);
          },
        ),
      );
  }

  Widget _buildLoadMoreButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: _loadMore,
          icon: const Icon(Icons.keyboard_arrow_down),
          label: Text('Load More'),
        ),
      );
    }

  Future<void> _loadMore() async {
    // Load next page
  }

  Widget _buildBannerCard(Map<String, dynamic> banner) {
    final status = banner['status'] as String? ?? 'DRAFT';
    final type = banner['type'] as String? ?? 'UNKNOWN';
    final placements = (banner['placements'] as List<dynamic>?)?.map((e) => e.toString()).join(', ') ?? '';

    return Card(
      child: ListTile(
        leading: _buildTypeIcon(type),
        title: Text(
          banner['title']?.toString() ?? 'Untitled',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${type.toUpperCase()}'),
            if (banner['placements'] != null)
              Text('Placements: ${placements}'),
            Text('Status: $status'),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleBannerAction(value, banner),
          itemBuilder: (context) => [
            PopupMenuItem(value: 'edit', child: Row(
              children: [Icon(Icons.edit), SizedBox(width: 8), Text('Edit')],
            )),
            PopupMenuItem(value: 'preview', child: Row(
              children: [Icon(Icons.preview), SizedBox(width: 8), Text('Preview')],
            )),
            PopupMenuItem(value: 'duplicate', child: Row(
              children: [Icon(Icons.copy), SizedBox(width: 8), Text('Duplicate')],
            )),
            PopupMenuItem(value: 'delete', child: Row(
              children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))],
            )),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildTypeIcon(String type) {
    IconData icon;
    Color color;

    switch (type.toUpperCase()) {
      case 'SPONSORED_AD':
        icon = Icons.campaign;
        color = Colors.amber;
        break;
      case 'PROMOTION':
        icon = Icons.local_offer;
        color = Colors.green;
        break;
      case 'NEW_FEATURE':
        icon = Icons.new_releases;
        color = Colors.blue;
        break;
      case 'PLATFORM_ANNOUNCEMENT':
        icon = Icons.announcement;
        color = Colors.purple;
        break;
      default:
        icon = Icons.campaign;
        color = Colors.grey;
    }

    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, color: color),
    );
  }

  String _getStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE': return 'Active';
      case 'DRAFT': return 'Draft';
      case 'SCHEDULED': return 'Scheduled';
      case 'PAUSED': return 'Paused';
      case 'EXPIRED': return 'Expired';
      case 'ARCHIVED': return 'Archived';
      default: return status;
    }
  }

  void _handleBannerAction(String action, Map<String, dynamic> banner) {
    switch (action) {
      case 'edit':
        _showEditBannerDialog(banner);
        break;
      case 'preview':
        _showPreview(banner);
        break;
      case 'duplicate':
        _duplicateBanner(banner);
        break;
      case 'delete':
        _confirmDelete(banner);
        break;
    }
  }

  Future<void> _showCreateBannerDialog() async {
    // TODO: Implement create banner dialog
  }

  Future<void> _showEditBannerDialog(Map<String, dynamic> banner) async {
    // TODO: Implement edit dialog
  }

  Future<void> _showPreview(Map<String, dynamic> banner) async {
    // TODO: Implement preview
  }

  Future<void> _duplicateBanner(Map<String, dynamic> banner) async {
    // TODO: Implement duplicate
  }

  Future<void> _confirmDelete(Map<String, dynamic> banner) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Banner?'),
        content: Text('Are you sure you want to delete "${banner['title']}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // TODO: Delete banner
    }
  }

  @override
  Widget build(BuildContext context) {
    // Implementation continues...
    return Scaffold(
      appBar: AppBar(
        title: Text('Banner Management'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () => _showCreateBannerDialog(),
          ),
        ],
      ),
      body: Center(child: Text('Banner Management Dashboard - Implementation in progress')),
    );
  }
}