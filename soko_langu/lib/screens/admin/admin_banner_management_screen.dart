import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/banner_model.dart';
import '../../services/banner_service.dart';
import '../../theme/design_tokens.dart';
import '../../theme/app_typography.dart';
import '../../extensions/context_tr.dart';

/// Admin screen for managing banner campaigns.
class AdminBannerManagementScreen extends StatefulWidget {
  const AdminBannerManagementScreen({super.key});

  @override
  State<AdminBannerManagementScreen> createState() =>
      _AdminBannerManagementScreenState();
}

class _AdminBannerManagementScreenState
    extends State<AdminBannerManagementScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  List<BannerCampaign> _campaigns = [];
  bool _loading = true;
  String? _error;

  // Filters
  BannerType? _typeFilter;
  BannerPlacement? _placementFilter;
  BannerStatus? _statusFilter;
  DateTimeRange? _dateRangeFilter;
  String _searchQuery = '';

  // Pagination
  static const int _pageSize = 20;
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadCampaigns();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCampaigns({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _loading = true;
        _error = null;
        _campaigns = [];
        _lastDoc = null;
        _hasMore = true;
      });
    }

    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('banner_campaigns')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      if (_typeFilter != null) {
        query = query.where('type', isEqualTo: _typeFilter!.name);
      }
      if (_placementFilter != null) {
        query = query.where('placement', isEqualTo: _placementFilter!.name);
      }
      if (_statusFilter != null) {
        query = query.where('status', isEqualTo: _statusFilter!.name);
      }
      if (_dateRangeFilter != null) {
        query = query
            .where('startDate',
                isGreaterThanOrEqualTo: Timestamp.fromDate(_dateRangeFilter!.start))
            .where('startDate',
                isLessThanOrEqualTo: Timestamp.fromDate(_dateRangeFilter!.end));
      }

      if (loadMore && _lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }

      final snapshot = await query.get();
      final newCampaigns = snapshot.docs
          .map(BannerCampaign.fromFirestore)
          .where((c) => _searchQuery.isEmpty ||
              c.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              c.mainText.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();

      if (mounted) {
        setState(() {
          _campaigns.addAll(newCampaigns);
          _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length == _pageSize;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load campaigns: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() => _searchQuery = query);
    await _loadCampaigns();
  }

  void _onFilterChanged() {
    _loadCampaigns();
  }

  Future<void> _onRefresh() async {
    await _loadCampaigns();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Banner Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateDialog(),
            tooltip: 'Create Banner',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: Column(
          children: [
            // Filter bar
            _buildFilterBar(cs),

            // Campaign list
            Expanded(
              child: _loading && _campaigns.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorState(cs)
                      : _campaigns.isEmpty
                          ? _buildEmptyState(cs)
                          : _buildCampaignList(cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(Ds.sp3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search field
          TextField(
            decoration: InputDecoration(
              hintText: context.tr('search_banners'),
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: Ds.sp2),

          // Filter chips
          Wrap(
            spacing: Ds.sp2,
            runSpacing: Ds.sp2,
            children: [
              _FilterChip<BannerType?>(
                label: 'All Types',
                value: _typeFilter,
                selected: _typeFilter == null,
                onSelected: (v) => setState(() => _typeFilter = v),
              ),
              ...BannerType.values.map((type) => _FilterChip<BannerType?>(
                    label: type.name,
                    value: type,
                    selected: _typeFilter == type,
                    onSelected: (v) => setState(() => _typeFilter = v),
                  )),
              const SizedBox(width: Ds.sp3),
              _FilterChip<BannerPlacement?>(
                label: 'All Placements',
                value: _placementFilter,
                selected: _placementFilter == null,
                onSelected: (v) => setState(() => _placementFilter = v),
              ),
              ...BannerPlacement.values.map((p) => _FilterChip<BannerPlacement?>(
                    label: p.name,
                    value: p,
                    selected: _placementFilter == p,
                    onSelected: (v) => setState(() => _placementFilter = v),
                  )),
              const SizedBox(width: Ds.sp3),
              _FilterChip<BannerStatus?>(
                label: 'All Status',
                value: _statusFilter,
                selected: _statusFilter == null,
                onSelected: (v) => setState(() => _statusFilter = v),
              ),
              ...BannerStatus.values.map((s) => _FilterChip<BannerStatus?>(
                    label: s.name,
                    value: s,
                    selected: _statusFilter == s,
                    onSelected: (v) => setState(() => _statusFilter = v),
                  )),
            ],
          ),

          // Date range filter
          if (_dateRangeFilter != null)
            Padding(
              padding: const EdgeInsets.only(top: Ds.sp2),
              child: Row(
                children: [
                  Text(
                    'Date: ${_formatDate(_dateRangeFilter!.start)} - ${_formatDate(_dateRangeFilter!.end)}',
                    style: Ds.caption(cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _dateRangeFilter = null),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
        ],
      );
    }
  }

  Widget _buildErrorState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Ds.sp6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 48),
            const SizedBox(height: Ds.sp3),
            Text(
              _error!,
              style: Ds.bodyMd(cs.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Ds.sp3),
            FilledButton(
              onPressed: _loadCampaigns,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Ds.sp6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, color: cs.onSurfaceVariant, size: 48),
            const SizedBox(height: Ds.sp3),
            Text(
              'No banner campaigns found',
              style: Ds.bodyMd(cs.onSurfaceVariant),
            ),
            const SizedBox(height: Ds.sp2),
            Text(
              'Create your first banner campaign to get started',
              style: Ds.caption(cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Ds.sp4),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              onPressed: () => _showCreateDialog(),
              label: const Text('Create Banner'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampaignList(ColorScheme cs) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 200 &&
            _hasMore &&
            !_loading) {
          _loadCampaigns(loadMore: true);
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(Ds.sp3),
        itemCount: _campaigns.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: Ds.sp2),
        itemBuilder: (context, index) {
          if (index >= _campaigns.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(Ds.sp3),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _CampaignTile(
            campaign: _campaigns[index],
            onTap: () => _showEditDialog(_campaigns[index]),
            onDelete: () => _confirmDelete(_campaigns[index]),
            onDuplicate: () => _duplicateCampaign(_campaigns[index]),
            onPreview: () => _showPreview(_campaigns[index]),
          );
        },
      ),
    );
  }

  void _showCreateDialog() => _showCampaignDialog(null);

  void _showEditDialog(BannerCampaign campaign) => _showCampaignDialog(campaign);

  void _showPreview(BannerCampaign campaign) {
    showDialog(
      context: context,
      builder: (ctx) => _BannerPreviewDialog(campaign: campaign),
    );
  }

  Future<void> _confirmDelete(BannerCampaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Campaign'),
        content: Text('Delete "${campaign.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteCampaign(campaign);
    }
  }

  Future<void> _deleteCampaign(BannerCampaign campaign) async {
    try {
      await _firestore
          .collection('banner_campaigns')
          .doc(campaign.id)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Campaign deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Future<void> _duplicateCampaign(BannerCampaign campaign) async {
    try {
      final newCampaign = campaign.copyWith(
        id: '',
        title: '${campaign.title} (Copy)',
        status: BannerStatus.draft,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        impressionCount: 0,
        clickCount: 0,
      );
      await _firestore
          .collection('banner_campaigns')
          .add(newCampaign.toFirestore());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Campaign duplicated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to duplicate: $e')),
        );
      }
    }
  }

  Future<void> _showCampaignDialog(BannerCampaign? campaign) async {
    final isEditing = campaign != null;
    final formKey = GlobalKey<FormState>();

    // Form controllers
    final titleCtrl = TextEditingController(text: campaign?.title);
    final mainTextCtrl = TextEditingController(text: campaign?.mainText);
    final subtitleCtrl = TextEditingController(text: campaign?.subtitle);
    final ctaLabelCtrl = TextEditingController(text: campaign?.ctaLabel);
    final imageUrlCtrl = TextEditingController(text: campaign?.imageUrl);
    final videoUrlCtrl = TextEditingController(text: campaign?.videoUrl);
    final destinationValueCtrl =
        TextEditingController(text: campaign?.destinationValue);
    final sponsorNameCtrl = TextEditingController(text: campaign?.sponsorName);
    final sponsorInfoCtrl = TextEditingController(text: campaign?.sponsorInfo);

    BannerType selectedType = campaign?.type ?? BannerType.adminConfigured;
    BannerPlacement selectedPlacement = campaign?.placement ?? BannerPlacement.homeFeed;
    BannerStatus selectedStatus = campaign?.status ?? BannerStatus.draft;
    BannerDestinationType selectedDestType =
        campaign?.destinationType ?? BannerDestinationType.externalUrl;
    BannerAudience selectedAudience = campaign?.targetAudience ?? BannerAudience.allUsers;
    int priority = campaign?.priority ?? 0;
    DateTime startDate = campaign?.startDate ?? DateTime.now();
    DateTime endDate = campaign?.endDate ??
        DateTime.now().add(const Duration(days: 30));
    int? impressionLimit = campaign?.impressionLimit;
    int? clickLimit = campaign?.clickLimit;
    List<String> deviceTargeting = List.from(campaign?.deviceTargeting ?? []);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit Campaign' : 'Create Campaign'),
          content: SizedBox(
            width: 600,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Basic Info
                    _sectionTitle('Basic Information'),
                    TextFormField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Title *'),
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: mainTextCtrl,
                      decoration: const InputDecoration(labelText: 'Main Text *'),
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                      maxLines: 2,
                    ),
                    TextFormField(
                      controller: subtitleCtrl,
                      decoration: const InputDecoration(labelText: 'Subtitle'),
                      maxLines: 2,
                    ),
                    TextFormField(
                      controller: ctaLabelCtrl,
                      decoration:
                          const InputDecoration(labelText: 'CTA Label *'),
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: Ds.sp3),

                    // Type & Placement
                    _sectionTitle('Type & Placement'),
                    DropdownButtonFormField<BannerType>(
                      value: selectedType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: BannerType.values
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.name),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedType = v!),
                    ),
                    DropdownButtonFormField<BannerPlacement>(
                      value: selectedPlacement,
                      decoration: const InputDecoration(labelText: 'Placement'),
                      items: BannerPlacement.values
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.name),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedPlacement = v!),
                    ),
                    DropdownButtonFormField<BannerStatus>(
                      value: selectedStatus,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: BannerStatus.values
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s.name),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedStatus = v!),
                    ),
                    const SizedBox(height: Ds.sp3),

                    // Destination
                    _sectionTitle('Destination'),
                    DropdownButtonFormField<BannerDestinationType>(
                      value: selectedDestType,
                      decoration: const InputDecoration(labelText: 'Destination Type'),
                      items: BannerDestinationType.values
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text(d.name),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedDestType = v!),
                    ),
                    TextFormField(
                      controller: destinationValueCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Destination Value (ID/URL)'),
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: Ds.sp3),

                    // Media
                    _sectionTitle('Media (Optional)'),
                    TextFormField(
                      controller: imageUrlCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Image URL (https://...)'),
                    ),
                    TextFormField(
                      controller: videoUrlCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Video URL (https://...)'),
                    ),
                    const SizedBox(height: Ds.sp3),

                    // Audience & Schedule
                    _sectionTitle('Audience & Schedule'),
                    DropdownButtonFormField<BannerAudience>(
                      value: selectedAudience,
                      decoration: const InputDecoration(labelText: 'Target Audience'),
                      items: BannerAudience.values
                          .map((a) => DropdownMenuItem(
                                value: a,
                                child: Text(a.name),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedAudience = v!),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: ctx,
                                initialDate: startDate,
                                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                setDialogState(() => startDate = date);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                  labelText: 'Start Date'),
                              child: Text(_formatDate(startDate)),
                            ),
                          ),
                        ),
                        const SizedBox(width: Ds.sp3),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: ctx,
                                initialDate: endDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                setDialogState(() => endDate = date);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                  labelText: 'End Date'),
                              child: Text(_formatDate(endDate)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      initialValue: priority.toString(),
                      decoration: const InputDecoration(labelText: 'Priority'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) =>
                          setDialogState(() => priority = int.tryParse(v) ?? 0),
                    ),
                    const SizedBox(height: Ds.sp3),

                    // Limits
                    _sectionTitle('Campaign Limits (Optional)'),
                    TextFormField(
                      initialValue: impressionLimit?.toString(),
                      decoration: const InputDecoration(labelText: 'Impression Limit'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) =>
                          setDialogState(() => impressionLimit = int.tryParse(v)),
                    ),
                    TextFormField(
                      initialValue: clickLimit?.toString(),
                      decoration: const InputDecoration(labelText: 'Click Limit'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) =>
                          setDialogState(() => clickLimit = int.tryParse(v)),
                    ),
                    const SizedBox(height: Ds.sp3),

                    // Device targeting
                    _sectionTitle('Device Targeting (Optional)'),
                    Wrap(
                      spacing: Ds.sp2,
                      children: ['mobile', 'tablet', 'desktop', 'web'].map((d) {
                        final selected = deviceTargeting.contains(d);
                        return FilterChip(
                          label: Text(d),
                          selected: selected,
                          onSelected: (v) => setDialogState(() {
                            if (v) {
                              deviceTargeting.add(d);
                            } else {
                              deviceTargeting.remove(d);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: Ds.sp3),

                    // Sponsor info
                    if (selectedType == BannerType.sponsoredAd) ...[
                      _sectionTitle('Sponsor Information'),
                      TextFormField(
                        controller: sponsorNameCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Sponsor Name *'),
                        validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: sponsorInfoCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Sponsor Info / Campaign Reference'),
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final newCampaign = BannerCampaign(
                  id: campaign?.id ?? '',
                  title: titleCtrl.text,
                  mainText: mainTextCtrl.text,
                  subtitle: subtitleCtrl.text.isEmpty ? null : subtitleCtrl.text,
                  type: selectedType,
                  imageUrl: imageUrlCtrl.text.isEmpty ? null : imageUrlCtrl.text,
                  videoUrl: videoUrlCtrl.text.isEmpty ? null : videoUrlCtrl.text,
                  ctaLabel: ctaLabelCtrl.text,
                  destinationType: selectedDestType,
                  destinationValue: destinationValueCtrl.text,
                  placement: selectedPlacement,
                  priority: priority,
                  startDate: startDate,
                  endDate: endDate,
                  targetAudience: selectedAudience,
                  deviceTargeting: deviceTargeting.isEmpty ? null : deviceTargeting,
                  status: selectedStatus,
                  impressionLimit: impressionLimit,
                  clickLimit: clickLimit,
                  sponsorName:
                      selectedType == BannerType.sponsoredAd ? sponsorNameCtrl.text : null,
                  sponsorInfo:
                      selectedType == BannerType.sponsoredAd ? sponsorInfoCtrl.text : null,
                  createdAt: campaign?.createdAt ?? DateTime.now(),
                  updatedAt: DateTime.now(),
                  createdBy: 'admin', // TODO: get actual admin ID
                );

                try {
                  if (isEditing) {
                    await _firestore
                        .collection('banner_campaigns')
                        .doc(campaign.id)
                        .update(newCampaign.toFirestore());
                  } else {
                    await _firestore
                        .collection('banner_campaigns')
                        .add(newCampaign.toFirestore());
                  }
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              isEditing ? 'Campaign updated' : 'Campaign created')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to save: $e')),
                    );
                  }
                }
              },
              child: Text(isEditing ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.sp1, top: Ds.sp2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: Ds.labelMd(Theme.of(context).colorScheme.onSurfaceVariant)
              .copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _FilterChip<T> extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final T value;
  final bool selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
      selectedColor: cs.primary.withValues(alpha: 0.15),
      checkmarkColor: cs.primary,
    );
  }
}

class _CampaignTile extends StatelessWidget {
  const _CampaignTile({
    required this.campaign,
    required this.onTap,
    required this.onDelete,
    required this.onDuplicate,
    required this.onPreview,
  });

  final BannerCampaign campaign;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = campaign.isCurrentlyActive();

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ds.rMd),
        child: Padding(
          padding: const EdgeInsets.all(Ds.sp3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                campaign.title,
                                style: Ds.bodyMd(cs.onSurface).copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _StatusBadge(status: campaign.status),
                          ],
                        ),
                        const SizedBox(height: Ds.sp1),
                        Text(
                          campaign.mainText,
                          style: Ds.caption(cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: Ds.sp1),
                        Wrap(
                          spacing: Ds.sp1,
                          runSpacing: Ds.sp1,
                          children: [
                            _InfoChip(
                                label: campaign.type.name, color: cs.primary),
                            _InfoChip(
                                label: campaign.placement.name, color: cs.secondary),
                            _InfoChip(
                                label: campaign.targetAudience.name, color: cs.tertiary),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onTap();
                          break;
                        case 'preview':
                          onPreview();
                          break;
                        case 'duplicate':
                          onDuplicate();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'preview',
                        child: Row(
                          children: [
                            Icon(Icons.preview, size: 18),
                            SizedBox(width: 8),
                            Text('Preview'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: Row(
                          children: [
                            Icon(Icons.content_copy, size: 18),
                            SizedBox(width: 8),
                            Text('Duplicate'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Ds.sp2),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: Ds.sp1),
                  Text(
                    '${_formatDate(campaign.startDate)} - ${_formatDate(campaign.endDate)}',
                    style: Ds.caption(cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: Ds.sp3),
                  if (campaign.impressionLimit != null) ...[
                    Icon(Icons.visibility, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: Ds.sp1),
                    Text(
                      'Impressions: ${campaign.impressionCount}/${campaign.impressionLimit}',
                      style: Ds.caption(cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: Ds.sp3),
                  ],
                  if (campaign.clickLimit != null) ...[
                    Icon(Icons.touch_app, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: Ds.sp1),
                    Text(
                      'Clicks: ${campaign.clickCount}/${campaign.clickLimit}',
                      style: Ds.caption(cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final BannerStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bgColor;
    Color textColor;

    switch (status) {
      case BannerStatus.active:
        bgColor = Colors.green.withValues(alpha: 0.15);
        textColor = Colors.green;
        break;
      case BannerStatus.scheduled:
        bgColor = Colors.blue.withValues(alpha: 0.15);
        textColor = Colors.blue;
        break;
      case BannerStatus.paused:
        bgColor = Colors.orange.withValues(alpha: 0.15);
        textColor = Colors.orange;
        break;
      case BannerStatus.expired:
        bgColor = Colors.grey.withValues(alpha: 0.15);
        textColor = Colors.grey;
        break;
      case BannerStatus.archived:
        bgColor = Colors.grey.withValues(alpha: 0.1);
        textColor = Colors.grey;
        break;
      case BannerStatus.draft:
        bgColor = cs.surfaceContainerHighest;
        textColor = cs.onSurfaceVariant;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

class _BannerPreviewDialog extends StatelessWidget {
  const _BannerPreviewDialog({required this.campaign});

  final BannerCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(Ds.sp3),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(Ds.rLg)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Preview: ${campaign.title}',
                      style: Ds.bodyMd(cs.onPrimaryContainer).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Preview content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Ds.sp3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Device selector tabs
                    DefaultTabController(
                      length: 3,
                      child: Column(
                        children: [
                          TabBar(
                            tabs: const [
                              Tab(text: 'Mobile'),
                              Tab(text: 'Tablet'),
                              Tab(text: 'Desktop'),
                            ],
                            labelStyle: Ds.labelMd(cs.onSurface),
                            unselectedLabelStyle: Ds.labelMd(cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: Ds.sp3),
                          SizedBox(
                            height: 400,
                            child: TabBarView(
                              children: [
                                _buildPreviewForDevice(context, 375),
                                _buildPreviewForDevice(context, 768),
                                _buildPreviewForDevice(context, 1200),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Ds.sp3),

                    // Campaign details
                    _buildDetailRow('Type', campaign.type.name),
                    _buildDetailRow('Placement', campaign.placement.name),
                    _buildDetailRow('Status', campaign.status.name),
                    _buildDetailRow('Audience', campaign.targetAudience.name),
                    _buildDetailRow('Priority', campaign.priority.toString()),
                    _buildDetailRow(
                        'Schedule',
                        '${_formatDate(campaign.startDate)} - ${_formatDate(campaign.endDate)}'),
                    if (campaign.impressionLimit != null)
                      _buildDetailRow('Impression Limit', campaign.impressionLimit.toString()),
                    if (campaign.clickLimit != null)
                      _buildDetailRow('Click Limit', campaign.clickLimit.toString()),
                    if (campaign.sponsorName != null)
                      _buildDetailRow('Sponsor', campaign.sponsorName!),
                  ],
                ),
              ),
            ),

            // Close button
            Padding(
              padding: const EdgeInsets.all(Ds.sp3),
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewForDevice(BuildContext context, double width) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(Ds.sp3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${width.toInt()}px width',
                  style: Ds.caption(Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Ds.sp3),
                // This would ideally render the actual banner widget
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(Ds.rLg),
                  ),
                  child: Center(
                    child: Text(
                      'Banner Preview\n(${campaign.type.name})',
                      style: Ds.bodyMd(Theme.of(context).colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Ds.caption(Theme.of(context).colorScheme.onSurfaceVariant)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(value, style: Ds.bodySm(Theme.of(context).colorScheme.onSurface)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}