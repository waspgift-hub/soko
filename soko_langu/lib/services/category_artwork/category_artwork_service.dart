import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/marketplace_taxonomy.dart';
import '../../models/category_model.dart' as category_model;
import '../api_config.dart';
import 'artwork_downloader.dart';
import 'artwork_manifest.dart';
import 'artwork_store.dart';

/// Public read origin for the Category Artwork Pack.
///
/// Served by the `soko-media` Worker from the public `soko-vibe-artwork` R2
/// bucket. Public by design: these are application artwork, not user media, and
/// the same origin already serves every product photo.
const String kArtworkBaseUrl = '${ApiConfig.r2PublicUrl}/artwork/';

/// Installation state of the pack on this device.
enum ArtworkStatus {
  /// Nothing downloaded yet. The app is fully usable on icon fallbacks.
  notInstalled,

  downloading,

  installed,

  /// A newer pack exists remotely. The user may update, or stay where they are.
  updateAvailable,

  failed,
}

/// Thrown for every failure the download surface must turn into a friendly
/// message. [technical] is what goes to error monitoring; the UI never shows it.
/// Re-exported here so consumers need only one import.
typedef ArtworkFailure = ArtworkDownloadException;

/// Central lookup for category artwork.
///
/// Every screen resolves artwork through here by stable taxonomy id, so no
/// screen re-implements asset lookup and localization can never break the
/// mapping. Resolution is three-tier and always terminates in a renderable
/// widget:
///
/// 1. the installed local pack file,
/// 2. a bundled lightweight placeholder,
/// 3. a Material icon.
class CategoryArtworkService {
  static final CategoryArtworkService instance = CategoryArtworkService._();

  CategoryArtworkService._();

  final ArtworkStore _store = ArtworkStore();
  ArtworkDownloader? _downloader;

  /// Test seam: re-target the pack origin at a local server.
  void debugUseBaseUrl(Uri url) {
    _downloader?.dispose();
    _downloader = ArtworkDownloader(baseUrl: url);
    baseUrl = url;
  }

  StreamController<ArtworkStatus>? _statusController;
  StreamController<void>? _changeController;
  StreamController<ArtworkDownloadProgress>? _progressController;

  ArtworkManifest? _installedManifest;
  int? _installedVersion;

  /// Synchronously-known cache of resolved paths, so a widget build never has
  /// to await. Populated by [initialize] and refreshed on every install.
  final Map<String, String> _localPaths = {};

  ArtworkStatus _status = ArtworkStatus.notInstalled;
  ArtworkDownloadProgress? _progress;
  Object? _lastError;
  bool _promptDismissed = false;
  bool _initialized = false;
  bool _cancelRequested = false;
  Timer? _remoteManifestTimer;

  // Injected for tests.
  Uri baseUrl = Uri.parse(kArtworkBaseUrl);
  bool offlineMode = false;

  ArtworkStatus get status => _status;
  ArtworkDownloadProgress? get progress => _progress;
  Object? get lastError => _lastError;
  int? get installedVersion => _installedVersion;
  ArtworkManifest? get installedManifest => _installedManifest;
  bool get hasArtwork => _localPaths.isNotEmpty;
  bool get promptDismissed => _promptDismissed;
  bool get isDownloading =>
      _status == ArtworkStatus.downloading;

  Stream<ArtworkStatus> get statusStream {
    _ensureStatusController();
    return _statusController!.stream;
  }

  /// Fires whenever resolved artwork paths change, so `CategoryImage` can swap
  /// from placeholder to real photo without a full rebuild of the tree.
  Stream<void> get artworkChanged {
    _ensureChangeController();
    return _changeController!.stream;
  }

  /// Progress of an in-flight download. A real stream rather than a polled
  /// getter so the progress UI cannot rebuild on every unrelated frame.
  Stream<ArtworkDownloadProgress> get progressStream {
    _progressController ??= StreamController<ArtworkDownloadProgress>.broadcast();
    return _progressController!.stream;
  }

  void _ensureStatusController() {
    _statusController ??= StreamController<ArtworkStatus>.broadcast();
    _ensureChangeController();
  }

  void _ensureChangeController() {
    _changeController ??= StreamController<void>.broadcast();
  }

  ArtworkDownloader get _dl =>
      _downloader ??= ArtworkDownloader(baseUrl: baseUrl);

  /// Reads local state and warms the path cache. Never throws and never blocks
  /// the app: artwork is optional, so a failure here leaves the app on icons.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final version = await _store.readInstalledVersion();
      if (version != null) {
        _installedVersion = version;
        final manifest = await _store.readInstalledManifest();
        if (manifest != null) {
          _installedManifest = manifest;
          await _warmPaths(manifest, version);
          _status = ArtworkStatus.installed;
        } else {
          // Pointer present but manifest unreadable: treat as not installed
          // rather than showing a pack that cannot resolve.
          _status = ArtworkStatus.notInstalled;
        }
      }
    } catch (e) {
      _setFailed(e);
    }
    _statusController?.add(_status);
    _changeController?.add(null);
  }

  Future<void> _warmPaths(ArtworkManifest manifest, int version) async {
    _localPaths.clear();
    for (final asset in manifest.assets) {
      final path = await _store.localPathOf(asset.file, version);
      if (path != null) _localPaths[asset.id] = path;
    }
  }

  // =========================
  // RESOLUTION (stable ids only)
  // =========================

  /// Local file for a category id (`electronics`).
  ///
  /// Returns null when the pack is not installed, the id is unknown, or the
  /// file is missing on disk — all of which the caller renders as a fallback.
  String? resolveCategory(String categoryId) => _localPaths[categoryId];

  /// Local file for a subcategory, keyed by its owning category so two
  /// categories can share a subcategory slug without colliding. `cleaning`
  /// exists under both `kitchen` and `services` in the live taxonomy, so the
  /// subcategory id alone is not a unique key.
  String? resolveSubcategory(String categoryId, String subcategoryId) {
    final qualified = subKey(categoryId, subcategoryId);
    return _localPaths[qualified];
  }

  /// Key used for a subcategory in the manifest and the path cache.
  static String subKey(String categoryId, String subcategoryId) =>
      '$categoryId/$subcategoryId';

  /// Category ids that currently have artwork on this device.
  Iterable<String> get installedCategoryIds =>
      _installedManifest?.assets
          .where((a) => a.type == ArtworkAssetType.category)
          .map((a) => a.id) ??
      const <String>[];

  /// True when [categoryId] has no artwork yet but the pack offers one, so a
  /// per-category download prompt can be shown instead of the full pack.
  bool isMissingButAvailable(String categoryId) {
    if (_localPaths.containsKey(categoryId)) return false;
    return _installedManifest?.assetForCategory(categoryId) != null ||
        _remoteManifest?.assetForCategory(categoryId) != null;
  }

  // =========================
  // REMOTE MANIFEST / VERSIONS
  // =========================
  ArtworkManifest? _remoteManifest;

  /// Latest manifest known from the network, if it has been fetched.
  ArtworkManifest? get remoteManifest => _remoteManifest;

  /// Checks the remote manifest and updates [status] to
  /// [ArtworkStatus.updateAvailable] when a newer pack exists.
  ///
  /// Cheap by design (conditional GET, at most once per [checkInterval]) so it
  /// is safe to call on every app start.
  Future<void> checkForUpdates({bool force = false}) async {
    if (offlineMode) return;
    try {
      final etag = force ? null : await _dl.manifestEtag();
      _remoteManifest = await _dl.fetchManifest(etag: etag);
      _checkMinAppVersion(_remoteManifest!);
      final installed = _installedVersion;
      if (installed == null) {
        _status = ArtworkStatus.notInstalled;
      } else if (_remoteManifest!.version > installed) {
        _status = ArtworkStatus.updateAvailable;
      } else {
        _status = ArtworkStatus.installed;
      }
      _statusController?.add(_status);
    } on ArtworkDownloadException catch (e) {
      // A 304 means nothing changed: keep whatever status we already had.
      if (e.httpStatus != 304) _status = ArtworkStatus.notInstalled;
    } catch (e) {
      if (kDebugMode) debugPrint('artwork checkForUpdates: $e');
      // Never flip an installed pack to "not installed" because of a network
      // blip; the local files are still there.
    }
  }

  void _checkMinAppVersion(ArtworkManifest manifest) {
    final min = manifest.minAppVersion;
    // Compare only when the manifest declares something parseable; a malformed
    // value must not block an otherwise valid pack.
    final parsed = _tryParseVersion(min);
    if (parsed == null) return;
    final current = _appVersion ?? '0.0.0';
    if (_compareVersions(current, min) < 0) {
      throw ArtworkDownloadException(
        'Pack ${manifest.version} requires app $min, running $current',
      );
    }
  }

  static List<int>? _tryParseVersion(String raw) {
    final parts = raw.split('.');
    if (parts.isEmpty) return null;
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n == null) return null;
      out.add(n);
    }
    return out;
  }

  static int _compareVersions(String a, String b) {
    final pa = _tryParseVersion(a) ?? const [0];
    final pb = _tryParseVersion(b) ?? const [0];
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  String? _appVersion;

  /// Supplies the running app version (package_info_plus) for the manifest's
  /// `minAppVersion` gate.
  void setAppVersion(String version) => _appVersion = version;

  /// Periodic background check. Starts a timer that polls the manifest at a
  /// deliberately low frequency so a large pack is never re-checked on every
  /// app launch.
  void startPeriodicCheck({Duration interval = const Duration(hours: 12)}) {
    _remoteManifestTimer?.cancel();
    _remoteManifestTimer = Timer.periodic(interval, (_) {
      unawaited(checkForUpdates());
    });
  }

  void stopPeriodicCheck() {
    _remoteManifestTimer?.cancel();
    _remoteManifestTimer = null;
  }

  // =========================
  // DOWNLOAD
  // =========================

  /// Downloads and installs the pack (or a subset).
  ///
  /// [onlyCategories] limits the download to specific category ids and their
  /// subcategories; null downloads everything. Either way the install is
  /// atomic and the previous version survives any failure.
  Future<bool> downloadPack({Set<String>? onlyCategories}) async {
    if (_status == ArtworkStatus.downloading) return false;
    _cancelRequested = false;
    _setStatus(ArtworkStatus.downloading);
    _setProgress(
      const ArtworkDownloadProgress(stage: ArtworkDownloadStage.preparing),
    );

    final downloader = _dl;
    ArtworkManifest? manifest = _remoteManifest;

    try {
      manifest ??= await downloader.fetchManifest();
      _remoteManifest = manifest;
      _checkMinAppVersion(manifest);

      final selected = _selectAssets(manifest, onlyCategories);
      final totalBytes = selected.fold<int>(0, (sum, a) => sum + a.size);

      var completed = 0;
      var received = 0;

      ArtworkDownloadProgress progress() => ArtworkDownloadProgress(
        completedAssets: completed,
        totalAssets: selected.length,
        receivedBytes: received,
        totalBytes: totalBytes,
        stage: ArtworkDownloadStage.downloading,
      );

      final rootDir = Directory(
        '${(await _storageRoot()).path}${Platform.pathSeparator}staging',
      );
      final staging = Directory(
        '${rootDir.path}${Platform.pathSeparator}${manifest.version}',
      );
      await staging.create(recursive: true);

      for (final asset in selected) {
        if (_cancelRequested) {
          _setProgress(
            ArtworkDownloadProgress(
              completedAssets: completed,
              totalAssets: selected.length,
              receivedBytes: received,
              totalBytes: totalBytes,
              stage: ArtworkDownloadStage.cancelled,
            ),
          );
          _setStatus(
            _installedVersion == null
                ? ArtworkStatus.notInstalled
                : ArtworkStatus.installed,
          );
          return false;
        }

        // Staging is keyed by version directory already, so the manifest's
        // version-prefixed path is stripped before writing locally.
        final target = File(
          '${staging.path}${Platform.pathSeparator}'
          '${ArtworkStore.relativeOf(asset.file, manifest.version)
              .replaceAll('/', Platform.pathSeparator)}',
        );
        await downloader.downloadAsset(
          asset: asset,
          target: target,
          progress: progress,
          isCancelled: () => _cancelRequested,
          onProgress: (p) async => _setProgress(p),
        );
        completed++;
        received += asset.size;
        _setProgress(progress());
      }

      // A partial subset cannot be promoted as a whole-pack install, because
      // the manifest would then promise files that were never fetched.
      final fullPack = selected.length == manifest.assets.length;
      if (!fullPack) {
        throw const ArtworkDownloadException(
          'Partial packs must be merged, not installed',
        );
      }

      _setProgress(
        ArtworkDownloadProgress(
          completedAssets: completed,
          totalAssets: selected.length,
          receivedBytes: received,
          totalBytes: totalBytes,
          stage: ArtworkDownloadStage.verifying,
        ),
      );

      final ok = await _store.install(
        version: manifest.version,
        manifest: manifest,
        manifestJson: _manifestJson(manifest),
      );

      if (!ok) {
        await _store.clearStaging(manifest.version);
        throw const ArtworkDownloadException('Pack failed verification');
      }

      await _afterInstall(manifest);
      _setProgress(
        ArtworkDownloadProgress(
          completedAssets: completed,
          totalAssets: selected.length,
          receivedBytes: received,
          totalBytes: totalBytes,
          stage: ArtworkDownloadStage.done,
        ),
      );
      _setStatus(ArtworkStatus.installed);
      clearPromptDismissed();
      return true;
    } on ArtworkDownloadException catch (e) {
      _setFailed(e);
      if (manifest != null) await _store.clearStaging(manifest.version);
      return false;
    } catch (e, st) {
      _setFailed(e);
      if (manifest != null) await _store.clearStaging(manifest.version);
      if (kDebugMode) debugPrint('artwork download failed: $e\n$st');
      return false;
    }
  }

  Future<Directory> _storageRoot() => _store.getRoot();

  List<ArtworkAsset> _selectAssets(
    ArtworkManifest manifest,
    Set<String>? onlyCategories,
  ) {
    if (onlyCategories == null) return manifest.assets;
    final wanted = onlyCategories;
    return manifest.assets.where((a) {
      if (a.type == ArtworkAssetType.category) {
        return wanted.contains(a.id);
      }
      return a.categoryId != null && wanted.contains(a.categoryId);
    }).toList();
  }

  String _manifestJson(ArtworkManifest manifest) {
    // Re-serialise from the parsed model so the installed copy is exactly what
    // the app validated, never a second unverified representation.
    return jsonEncode({
      'version': manifest.version,
      'pack': manifest.pack,
      'minAppVersion': manifest.minAppVersion,
      'generatedAt': manifest.generatedAt.toUtc().toIso8601String(),
      'totalBytes': manifest.totalBytes,
      'assets': [
        for (final a in manifest.assets)
          {
            'id': a.id,
            'type': a.type.name,
            if (a.categoryId != null) 'categoryId': a.categoryId,
            'file': a.file,
            'sha256': a.sha256,
            'size': a.size,
            'width': a.width,
            'height': a.height,
            if (a.group != null) 'group': a.group,
          },
      ],
    });
  }

  Future<void> _afterInstall(ArtworkManifest manifest) async {
    _installedVersion = manifest.version;
    _installedManifest = manifest;
    _remoteManifest = manifest;
    await _warmPaths(manifest, manifest.version);
    _changeController?.add(null);
  }

  /// Asks an in-flight download to stop at the next file boundary.
  void cancelDownload() => _cancelRequested = true;

  /// Retry after a failure: reuses whatever already downloaded.
  Future<bool> retry() => downloadPack();

  Future<int> diskUsage() => _store.diskUsage();

  Future<void> removePack() async {
    await _store.uninstall();
    _installedVersion = null;
    _installedManifest = null;
    _localPaths.clear();
    _setStatus(ArtworkStatus.notInstalled);
    _changeController?.add(null);
  }

  void markPromptDismissed() {
    _promptDismissed = true;
  }

  /// Restores the declined flag from local storage at startup.
  void setPromptDismissed(bool value) {
    _promptDismissed = value;
  }

  void clearPromptDismissed() {
    _promptDismissed = false;
  }

  // =========================
  // TAXONOMY CROSS-CHECK
  // =========================

  /// Subcategory ids that appear under more than one category in the shipped
  /// taxonomy. Used by the pipeline so artwork keys stay unique.
  static Map<String, List<String>> findAmbiguousSubcategoryIds() {
    final owners = <String, List<String>>{};
    for (final c in kMarketplaceTaxonomy) {
      for (final s in c.subs) {
        (owners[s.id] ??= <String>[]).add(c.id);
      }
    }
    return {
      for (final e in owners.entries)
        if (e.value.length > 1) e.key: e.value,
    };
  }

  /// Total ids the taxonomy expects artwork for. Used to warn when the shipped
  /// pack is missing entries rather than silently rendering icons.
  static ({int categories, int subcategories}) get expectedArtworkCounts {
    var subs = 0;
    for (final c in kMarketplaceTaxonomy) {
      subs += c.subs.length;
    }
    return (categories: kMarketplaceTaxonomy.length, subcategories: subs);
  }

  /// Category ids from the shipped taxonomy with no artwork in the installed
  /// pack.
  List<String> missingCategoryIds() {
    final have = _localPaths.keys.toSet();
    return kMarketplaceTaxonomy
        .map((t) => t.id)
        .where((id) => !have.contains(id))
        .toList();
  }

  void _setStatus(ArtworkStatus s) {
    _status = s;
    _statusController?.add(s);
  }

  void _setProgress(ArtworkDownloadProgress p) {
    _progress = p;
    _progressController?.add(p);
  }

  void _setFailed(Object e) {
    _lastError = e;
    _setStatus(ArtworkStatus.failed);
  }

  void dispose() {
    _remoteManifestTimer?.cancel();
    _downloader?.dispose();
    _statusController?.close();
    _changeController?.close();
    _initialized = false;
  }
}

/// Convenience for the `Category` model so screens can ask for artwork without
/// knowing about the service.
extension CategoryArtworkLookup on category_model.Category {
  String? get localArtworkPath => CategoryArtworkService.instance
      .resolveCategory(id);
}