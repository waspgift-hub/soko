import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../extensions/context_tr.dart';
import '../../services/category_artwork/artwork_downloader.dart';
import '../../services/category_artwork/category_artwork_service.dart';
import '../../services/error_reporting_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// "Download additional data" screen for the Category Artwork Pack.
///
/// The pack is never mandatory: dismissing this screen leaves the app fully
/// usable on icon fallbacks, which is why [allowDismiss] defaults to true and
/// there is always a visible way out.
class ArtworkPackScreen extends StatefulWidget {
  /// False for the blocking first-launch prompt, true for the settings entry
  /// point where the user can leave at any time.
  final bool allowDismiss;

  const ArtworkPackScreen({super.key, this.allowDismiss = true});

  @override
  State<ArtworkPackScreen> createState() => _ArtworkPackScreenState();
}

class _ArtworkPackScreenState extends State<ArtworkPackScreen> {
  final CategoryArtworkService _service = CategoryArtworkService.instance;

  bool _checking = true;
  bool _online = true;
  bool _wifiOnly = false;
  int? _remoteSizeBytes;
  int _remoteAssetCount = 0;
  bool _tooLargeForData = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await _service.initialize();
    final online = await _isOnline();
    if (!mounted) return;
    setState(() {
      _online = online;
      _checking = false;
    });
    // Size is fetched after the first frame so a slow manifest never delays
    // the screen appearing: the user sees the offer, then the exact size.
    unawaited(_loadRemoteSize());
  }

  Future<void> _loadRemoteSize() async {
    try {
      await _service.checkForUpdates(force: true);
      final manifest = _service.remoteManifest;
      if (!mounted || manifest == null) return;
      setState(() {
        _remoteAssetCount = manifest.assets.length;
        _remoteSizeBytes = manifest.totalBytes;
        // 25 MB is roughly the ceiling for an implicit mobile-data prompt in
        // this market; above it the user must explicitly opt in.
        _tooLargeForData = manifest.totalBytes > 25 * 1024 * 1024;
      });
    } catch (_) {
      if (mounted) setState(() => _remoteSizeBytes = null);
    }
  }

  Future<bool> _isOnline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (_) {
      // Connectivity is advisory here: the download itself is the real test,
      // so an unknown state is treated as online.
      return true;
    }
  }

  Future<void> _startDownload() async {
    await _service.downloadPack();
    if (!mounted) return;
    final failed = _service.status == ArtworkStatus.failed;
    if (failed) {
      _reportFailure('download');
      _toast(context.tr('artwork_pack_error'));
    }
  }

  void _reportFailure(String stage) {
    ErrorReportingService().reportError(
      error: _service.lastError ?? 'unknown artwork failure',
      userMessage: context.tr('artwork_pack_error'),
      severity: ErrorSeverity.warning,
      feature: 'category_artwork_download',
      screen: stage,
      extraData: {
        'stage': stage,
        'packVersion': _service.installedVersion,
        'remoteVersion': _service.remoteManifest?.version,
        'assetCount': _remoteAssetCount,
        'totalBytes': _remoteSizeBytes,
      },
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _close() {
    _service.markPromptDismissed();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = _service.status;

    if (_checking) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: widget.allowDismiss,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: widget.allowDismiss
            ? AppBar(
                elevation: 0,
                backgroundColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _close,
                  tooltip: context.tr('artwork_pack_later'),
                ),
              )
            : null,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppInsets.lg,
              AppInsets.md,
              AppInsets.lg,
              AppInsets.lg,
            ),
            children: [
              _Hero(status: status),
              const SizedBox(height: AppInsets.lg),
              _Body(
                status: status,
                online: _online,
                sizeBytes: _remoteSizeBytes,
                assetCount: _remoteAssetCount,
                tooLargeForData: _tooLargeForData,
              ),
              const SizedBox(height: AppInsets.lg),
              if (!_online)
                _Notice(
                  icon: Icons.wifi_off_rounded,
                  text: context.tr('artwork_pack_offline'),
                  tone: _NoticeTone.warning,
                ),
              if (_online &&
                  _tooLargeForData &&
                  !(_wifiOnly == true) &&
                  status != ArtworkStatus.downloading)
                _Notice(
                  icon: Icons.network_cell_rounded,
                  text: context.tr('artwork_pack_wifi_note'),
                  tone: _NoticeTone.info,
                ),
              if (status == ArtworkStatus.downloading)
                _WifiOnlyToggle(
                  value: _wifiOnly,
                  onChanged: (v) {
                    // Toggling mid-download cannot abort the in-flight bytes,
                    // so it only affects whether we let it continue: cancel,
                    // flip the flag, then restart from the resume point.
                    if (v) _service.cancelDownload();
                    setState(() => _wifiOnly = v);
                    if (v) {
                      unawaited(_resumeAfterWifiSwitch());
                    }
                  },
                ),
              const SizedBox(height: AppInsets.lg),
              _Actions(
                status: status,
                online: _online,
                allowDismiss: widget.allowDismiss,
                onDownload: _startDownload,
                onRetry: _startDownload,
                onCancel: () => _service.cancelDownload(),
                onDismiss: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// After a mid-download Wi-Fi-only switch the old transfer has been asked to
  /// stop; restarting reuses every verified file, so the cost is only the
  /// partially received one.
  Future<void> _resumeAfterWifiSwitch() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || _wifiOnly) return;
    if (_service.status == ArtworkStatus.downloading) return;
    await _startDownload();
  }
}

class _Hero extends StatelessWidget {
  final ArtworkStatus status;
  const _Hero({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final downloading = status == ArtworkStatus.downloading;
    final icon = switch (status) {
      ArtworkStatus.installed => Icons.check_circle_rounded,
      ArtworkStatus.updateAvailable => Icons.auto_awesome_rounded,
      ArtworkStatus.failed => Icons.cloud_off_rounded,
      _ => Icons.image_outlined,
    };

    return Column(
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.brandPrimary.withValues(alpha: 0.22),
                cs.brandPrimary.withValues(alpha: 0.06),
              ],
            ),
          ),
          child: Icon(icon, size: 48, color: cs.brandPrimary),
        ),
        const SizedBox(height: AppInsets.md),
        Text(
          context.tr(
            switch (status) {
              ArtworkStatus.installed => 'artwork_pack_installed',
              ArtworkStatus.updateAvailable => 'artwork_pack_update_available',
              _ => 'artwork_pack_title',
            },
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: AppInsets.xs),
        Text(
          context.tr(
            switch (status) {
              ArtworkStatus.installed => 'artwork_pack_installed_body',
              ArtworkStatus.updateAvailable => 'artwork_pack_update_body',
              _ => 'artwork_pack_subtitle',
            },
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: cs.onSurfaceVariant,
          ),
        ),
        if (downloading) ...[
          const SizedBox(height: AppInsets.lg),
          const _ProgressBlock(),
        ],
      ],
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final service = CategoryArtworkService.instance;
    return StreamBuilder<ArtworkDownloadProgress>(
      stream: service.progressStream,
      builder: (context, snapshot) {
        final p = snapshot.data ?? service.progress;
        final fraction = p?.fraction;
        final stage = p?.stage ?? ArtworkDownloadStage.preparing;
        final total = p?.totalBytes ?? 0;
        final received = p?.receivedBytes ?? 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                // null drives the indeterminate animation; showing a bar that
                // sits at 0% while the size is unknown would read as "stuck".
                value: stage == ArtworkDownloadStage.downloading
                    ? fraction
                    : null,
                minHeight: 10,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(cs.brandPrimary),
              ),
            ),
            const SizedBox(height: AppInsets.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _stageLabel(context, stage),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (total > 0)
                  Text(
                    '${_mb(received)} / ${_mb(total)} '
                    '${context.tr('artwork_pack_mb')}',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (stage == ArtworkDownloadStage.downloading && total > 0) ...[
              const SizedBox(height: AppInsets.xs),
              Text(
                context.tr(
                  'artwork_pack_remaining',
                  '{0} left',
                ).replaceAll('{0}', _mb(total - received)),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
            if (p != null && p.totalAssets > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppInsets.xs),
                child: Text(
                  context
                      .tr('artwork_pack_files', '{0} photos')
                      .replaceAll('{0}', '${p.completedAssets}/${p.totalAssets}'),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _stageLabel(BuildContext context, ArtworkDownloadStage s) {
    return switch (s) {
      ArtworkDownloadStage.preparing => context.tr('artwork_pack_downloading'),
      ArtworkDownloadStage.downloading => context.tr(
        'artwork_pack_downloading',
      ),
      ArtworkDownloadStage.verifying => context.tr('artwork_pack_verifying'),
      ArtworkDownloadStage.installing => context.tr('artwork_pack_installing'),
      ArtworkDownloadStage.done => context.tr('artwork_pack_done'),
      ArtworkDownloadStage.failed => context.tr('artwork_pack_error'),
      ArtworkDownloadStage.cancelled => context.tr('artwork_pack_cancelled'),
    };
  }

  static String _mb(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1);
}

class _Body extends StatelessWidget {
  final ArtworkStatus status;
  final bool online;
  final int? sizeBytes;
  final int assetCount;
  final bool tooLargeForData;

  const _Body({
    required this.status,
    required this.online,
    required this.sizeBytes,
    required this.assetCount,
    required this.tooLargeForData,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppInsets.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status != ArtworkStatus.installed) ...[
            Row(
              children: [
                Icon(Icons.photo_library_rounded,
                    size: 18, color: cs.brandPrimary),
                const SizedBox(width: 8),
                Text(
                  context.tr('artwork_pack_why_title'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('artwork_pack_why_body'),
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppInsets.md),
            const Divider(height: 1),
            const SizedBox(height: AppInsets.md),
          ],
          _InfoRow(
            label: context.tr('artwork_pack_size'),
            value: sizeBytes == null
                ? '…'
                : '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} '
                      '${context.tr('artwork_pack_mb')}',
          ),
          if (assetCount > 0)
_InfoRow(
            label: context.tr('artwork_pack_photos_count'),
            value: '$assetCount',
          ),
          _InfoRow(
            label: context.tr('artwork_pack_storage_used'),
            value: FutureBuilder<int>(
              future: CategoryArtworkService.instance.diskUsage(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Text('…');
                }
                final bytes = snap.data ?? 0;
                return Text(
                  '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;

  /// Either a resolved string or a widget (e.g. a FutureBuilder for a
  /// disk-usage read that must not be awaited inside build).
  final Object value;

  static Widget _asWidget(Object value, TextStyle style) => value is Widget
      ? value
      : Text(value as String, style: style);

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.trim(),
            style: TextStyle(fontSize: 13.5, color: cs.onSurfaceVariant),
          ),
          _asWidget(value, style),
        ],
      ),
    );
  }
}

enum _NoticeTone { info, warning }

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final _NoticeTone tone;

  const _Notice({
    required this.icon,
    required this.text,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = tone == _NoticeTone.warning ? cs.error : cs.brandInfo;
    return Container(
      margin: const EdgeInsets.only(bottom: AppInsets.sm),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WifiOnlyToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _WifiOnlyToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(
        context.tr('artwork_pack_only_wifi'),
        style: TextStyle(fontSize: 14, color: cs.onSurface),
      ),
      secondary: Icon(Icons.wifi_rounded, color: cs.onSurfaceVariant),
    );
  }
}

class _Actions extends StatelessWidget {
  final ArtworkStatus status;
  final bool online;
  final bool allowDismiss;
  final VoidCallback onDownload;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  const _Actions({
    required this.status,
    required this.online,
    required this.allowDismiss,
    required this.onDownload,
    required this.onRetry,
    required this.onCancel,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (status == ArtworkStatus.downloading) {
      return OutlinedButton.icon(
        onPressed: onCancel,
        icon: const Icon(Icons.pause_rounded),
        label: Text(context.tr('artwork_pack_pause')),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: cs.onSurface,
        ),
      );
    }

    final primaryLabel = switch (status) {
      ArtworkStatus.failed => context.tr('artwork_pack_retry'),
      ArtworkStatus.updateAvailable => context.tr('artwork_pack_update'),
      _ => context.tr('artwork_pack_download_now'),
    };

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            // Offline still allows the tap: the attempt itself is the real
            // connectivity test, and hard-disabling gives the user no feedback.
            onPressed: onDownload,
            icon: Icon(
              status == ArtworkStatus.failed
                  ? Icons.refresh_rounded
                  : Icons.download_rounded,
            ),
            label: Text(primaryLabel),
          ),
        ),
        if (allowDismiss) ...[
          const SizedBox(height: AppInsets.sm),
          TextButton(
            onPressed: onDismiss,
            child: Text(context.tr('artwork_pack_later')),
          ),
        ],
      ],
    );
  }
}

/// Shows the pack prompt once per install when artwork is not downloaded.
///
/// Never blocks the marketplace: it is presented as a sheet over whatever the
/// user was already doing, and dismissing it is one tap.
class ArtworkPackPrompt {
  static Future<void> maybeShow(BuildContext context) async {
    final service = CategoryArtworkService.instance;
    if (service.promptDismissed) return;
    if (service.status == ArtworkStatus.installed) return;

    await service.checkForUpdates();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.92,
        child: ArtworkPackScreen(allowDismiss: true),
      ),
    );
  }
}

/// Reads the running app version once and hands it to the artwork service so
/// the manifest's `minAppVersion` gate can be evaluated.
Future<void> primeArtworkService() async {
  final service = CategoryArtworkService.instance;
  try {
    final info = await PackageInfo.fromPlatform();
    service.setAppVersion(info.version);
  } catch (_) {
    // Without a version the gate simply cannot reject the pack; that is the
    // safe direction to fail.
  }
  await service.initialize();
}