import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/status_model.dart';
import '../../services/status_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import 'status_viewer_screen.dart';
import 'add_status_screen.dart';

class StatusListScreen extends StatefulWidget {
  const StatusListScreen({super.key});

  @override
  State<StatusListScreen> createState() => _StatusListScreenState();
}

class _StatusListScreenState extends State<StatusListScreen> {
  final StatusService _statusService = StatusService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _cleanupExpired();
  }

  Future<void> _cleanupExpired() async {
    try {
      await _statusService.cleanupExpiredStatuses();
    } catch (_) {}
  }

  Future<void> _openAddStatus() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddStatusScreen()),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  void _openViewer(List<StatusUpdate> updates) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatusViewerScreen(
          updates: updates,
          initialIndex: 0,
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return context.tr('just_now');
    if (diff.inHours < 1) {
      return '${diff.inMinutes} ${context.tr('minutes_ago')}';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} ${context.tr('hours_ago')}';
    }
    return '${diff.inDays} ${context.tr('days_ago')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentUid = _auth.currentUser?.uid;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.tr('status'),
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFD8F3DC), Color(0xFFF0F9F1)],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        color: const Color(0xFF2D6A4F),
        child: StreamBuilder<List<StatusViewerState>>(
          stream: _statusService.getAllStatuses(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const GoogleLoadingPage();
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: cs.error),
                    const SizedBox(height: 12),
                    Text(
                      '${context.tr('status_error')}${snapshot.error}',
                      style: TextStyle(color: cs.onSurface),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            final others = snapshot.data ?? [];

            return ListView(
              children: [
                _buildMyStatusTile(cs, currentUid),
                const Divider(height: 1, indent: 72),
                if (others.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.photo_camera_outlined,
                          size: 64,
                          color: cs.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.tr('no_status_yet'),
                          style: TextStyle(
                            fontSize: 16,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            context.tr('recent_updates'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        ...others.map(
                          (state) => _buildStatusTile(state, cs),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMyStatusTile(ColorScheme cs, String? currentUid) {
    return StreamBuilder<List<StatusUpdate>>(
      stream: _statusService.getMyStatuses(),
      builder: (context, snapshot) {
        final myStatuses = snapshot.data ?? [];
        final hasUnviewed = myStatuses.any(
          (s) => !s.viewers.contains(currentUid),
        );
        final latestTime = myStatuses.isNotEmpty
            ? myStatuses.first.createdAt
            : null;

        return InkWell(
          onTap: () {
            if (myStatuses.isEmpty) {
              _openAddStatus();
            } else {
              _openViewer(myStatuses);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: myStatuses.isEmpty
                              ? cs.outlineVariant
                              : (hasUnviewed
                                  ? const Color(0xFF2D6A4F)
                                  : cs.outlineVariant),
                          width: 2.5,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: cs.surfaceContainerHighest,
                        backgroundImage: _auth.currentUser?.photoURL != null
                            ? NetworkImage(_auth.currentUser!.photoURL!)
                            : null,
                        child: _auth.currentUser?.photoURL == null
                            ? Text(
                                (_auth.currentUser?.displayName ?? 'U')
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 20,
                                ),
                              )
                            : null,
                      ),
                    ),
                    if (myStatuses.isEmpty)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D6A4F),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: cs.surface,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('my_status'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        latestTime != null
                            ? _timeAgo(latestTime)
                            : context.tr('tap_to_view'),
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (myStatuses.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
                    onPressed: () => _showMyStatusOptions(myStatuses),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusTile(StatusViewerState state, ColorScheme cs) {
    final unviewedCount = state.updates.where(
      (s) => !s.viewers.contains(_auth.currentUser?.uid),
    ).length;

    return InkWell(
      onTap: () => _openViewer(state.updates),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: state.hasUnviewed
                      ? const Color(0xFF2D6A4F)
                      : cs.outlineVariant,
                  width: 2.5,
                ),
              ),
              child: CircleAvatar(
                radius: 26,
                backgroundColor: cs.surfaceContainerHighest,
                backgroundImage: state.userImage != null
                    ? CachedNetworkImageProvider(state.userImage!)
                    : null,
                child: state.userImage == null
                    ? Text(
                        state.userName.isNotEmpty
                            ? state.userName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 20,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.userName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _timeAgo(state.updates.last.createdAt),
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (unviewedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$unviewedCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D6A4F),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMyStatusOptions(List<StatusUpdate> myStatuses) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(context.tr('add_status')),
              onTap: () {
                Navigator.pop(ctx);
                _openAddStatus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(
                context.tr('delete_status'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: Text(context.tr('delete_status')),
                    content: Text(context.tr('delete_status_confirm')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: Text(context.tr('cancel')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: Text(
                          context.tr('delete'),
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  try {
                    await _statusService.deleteAllMyStatuses();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.tr('status_deleted'))),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${context.tr('status_error')}$e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
