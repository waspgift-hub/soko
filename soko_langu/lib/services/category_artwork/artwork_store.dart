import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/error_reporting_service.dart';
import 'artwork_manifest.dart';

/// On-device owner of the installed Category Artwork Pack.
///
/// Layout under the app-support directory (never a public path, so another app
/// and the gallery cannot reach it):
///
/// ```
/// category_artwork/
///   active.json                  # {"version":1,"installedAt":"..."} — the pointer
///   manifest.json                # cached copy of the installed manifest
///   versions/1/                  # installed pack
///     categories/electronics.webp
///     subcategories/electronics/phones.webp
///   staging/1/                   # in-flight download, never read by the UI
/// ```
///
/// The `active.json` pointer is written last, after every file of the new
/// version is verified. That is what makes an install atomic: a crash halfway
/// through leaves the previous version fully intact and readable.
class ArtworkStore {
  static const String _rootDirName = 'category_artwork';
  static const String _activeFile = 'active.json';
  static const String _manifestFile = 'manifest.json';
  static const String _versionsDir = 'versions';
  static const String _stagingDir = 'staging';

  Directory? _root;
  Directory? _versionsRootOverride;

  /// Test seam: point the store at a temp directory instead of path_provider.
  void debugUseRoot(Directory dir) {
    _versionsRootOverride = dir;
    _root = null;
  }

  Future<Directory> get _rootDir async {
    if (_root != null) return _root!;
    if (_versionsRootOverride != null) {
      _root = _versionsRootOverride!;
      return _root!;
    }
    final base = await getApplicationSupportDirectory();
    _root = Directory('${base.path}${Platform.pathSeparator}$_rootDirName');
    return _root!;
  }

  File _activeFileFor(Directory root) =>
      File('${root.path}${Platform.pathSeparator}$_activeFile');

  /// Strips the version segment from a manifest file path.
  ///
  /// Published keys are version-prefixed (`1/categories/electronics.webp`) so
  /// every R2 object is immutable, but on disk the version is already the
  /// directory (`versions/1/…`). Without this, the two prefixes would compose
  /// into `versions/1/1/…`.
  static String relativeOf(String file, int version) {
    final normalised = file.replaceAll('\\', '/');
    final prefix = '$version/';
    if (normalised.startsWith(prefix)) {
      return normalised.substring(prefix.length);
    }
    return normalised;
  }

  /// Version currently marked active, or null when no pack is installed.
  Future<int?> readInstalledVersion() async {
    try {
      final root = await _rootDir;
      final file = _activeFileFor(root);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded['version'];
      if (version is! int) return null;
      // A pointer to a directory that was removed (manual clear, failed
      // migration) must read as "not installed", not as a broken pack.
      final dir = versionDir(root, version);
      if (!await dir.exists()) return null;
      return version;
    } catch (e) {
      _report(e, stage: 'read_active_pointer');
      return null;
    }
  }

  Future<DateTime?> readInstalledAt() async {
    try {
      final root = await _rootDir;
      final file = _activeFileFor(root);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return DateTime.tryParse('${decoded['installedAt'] ?? ''}');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Directory versionDir(Directory root, int version) => Directory(
    '${root.path}${Platform.pathSeparator}$_versionsDir'
    '${Platform.pathSeparator}$version',
  );

  /// Directory a pack's files are downloaded into before it is installed.
  Directory stagingDir(Directory root, int version) => Directory(
    '${root.path}${Platform.pathSeparator}$_stagingDir'
    '${Platform.pathSeparator}$version',
  );

  /// Manifest of the installed pack, or null when nothing usable is installed.
  Future<ArtworkManifest?> readInstalledManifest() async {
    try {
      final version = await readInstalledVersion();
      if (version == null) return null;
      final root = await _rootDir;
      final manifestFile = File(
        '${root.path}${Platform.pathSeparator}$_versionsDir'
        '${Platform.pathSeparator}$version'
        '${Platform.pathSeparator}$_manifestFile',
      );
      if (!await manifestFile.exists()) return null;
      return ArtworkManifest.parse(await manifestFile.readAsString());
    } catch (e) {
      _report(e, stage: 'read_installed_manifest');
      return null;
    }
  }

  /// Absolute path of one installed artwork file, or null when the pack does
  /// not contain it. Callers treat null as "fall back to the icon".
  Future<String?> localPathOf(String relativeFile, int version) async {
    try {
      final root = await _rootDir;
      final dir = versionDir(root, version);
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        '${relativeOf(relativeFile, version).replaceAll('/', Platform.pathSeparator)}',
      );
      if (!await file.exists()) return null;
      return file.path;
    } catch (e) {
      _report(e, stage: 'resolve_local_path');
      return null;
    }
  }

  /// Moves a verified staging directory into place and flips the pointer.
  ///
  /// Returns false when the staging copy is not fully present, in which case
  /// staging is discarded and the previously installed version stays active.
  Future<bool> install({
    required int version,
    required ArtworkManifest manifest,
    required String manifestJson,
  }) async {
    Directory? root;
    try {
      root = await _rootDir;
      final staging = stagingDir(root, version);
      if (!await staging.exists()) return false;

      // Last-line completeness check before anything becomes visible: a pack
      // missing a single file must not be promoted, because the UI would then
      // show icon fallbacks for tiles the manifest promised were photos.
      for (final asset in manifest.assets) {
        final f = File(
          '${staging.path}${Platform.pathSeparator}'
          '${relativeOf(asset.file, version).replaceAll('/', Platform.pathSeparator)}',
        );
        if (!await f.exists()) return false;
      }

      final target = versionDir(root, version);
      if (await target.exists()) {
        await target.delete(recursive: true);
      }
      await target.parent.create(recursive: true);
      await staging.rename(target.path);

      await File(
        '${target.path}${Platform.pathSeparator}$_manifestFile',
      ).writeAsString(manifestJson, flush: true);

      // Pointer flip last. Everything above is invisible to the UI until this
      // write lands, so an interrupted install leaves no half-visible pack.
      final active = _activeFileFor(root);
      await active.writeAsString(
        jsonEncode({
          'version': version,
          'pack': manifest.pack,
          'installedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );

      await _pruneOldVersions(root, keep: version);
      return true;
    } catch (e) {
      _report(e, stage: 'atomic_install', extra: {'version': version});
      return false;
    }
  }

  /// Deletes every installed version except [keep], plus any staging leftovers.
  Future<void> _pruneOldVersions(Directory root, {required int keep}) async {
    try {
      final versions = Directory(
        '${root.path}${Platform.pathSeparator}$_versionsDir',
      );
      if (await versions.exists()) {
        await for (final entity in versions.list()) {
          final name = entity.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last;
          final v = int.tryParse(name);
          if (v != null && v != keep) {
            await entity.delete(recursive: true);
          }
        }
      }
      final staging = Directory(
        '${root.path}${Platform.pathSeparator}$_stagingDir',
      );
      if (await staging.exists()) {
        await for (final entity in staging.list()) {
          final name = entity.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last;
          final v = int.tryParse(name);
          if (v == null || v != keep) {
            await entity.delete(recursive: true);
          }
        }
      }
    } catch (e) {
      // Pruning is housekeeping: a failure here costs disk space, never
      // correctness, so it must not fail the install.
      _report(e, stage: 'prune_old_versions');
    }
  }

  /// Total bytes currently occupied by the pack, for the settings screen.
  Future<int> diskUsage() async {
    try {
      final root = await _rootDir;
      if (!await root.exists()) return 0;
      var total = 0;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Removes the pack entirely (settings → "freeshaga"). The app keeps working
  /// on icon fallbacks.
  Future<void> uninstall() async {
    try {
      final root = await _rootDir;
      if (await root.exists()) await root.delete(recursive: true);
      _root = null;
    } catch (e) {
      _report(e, stage: 'uninstall');
    }
  }

  /// Discards a partial download so the next attempt starts from zero.
  Future<void> clearStaging(int version) async {
    try {
      final root = await _rootDir;
      final staging = stagingDir(root, version);
      if (await staging.exists()) await staging.delete(recursive: true);
    } catch (e) {
      _report(e, stage: 'clear_staging', extra: {'version': version});
    }
  }

  /// Bytes already present in staging for [version], used to decide whether a
  /// fresh download can skip already-fetched files.
  Future<bool> hasStagedFile(int version, String relativeFile) async {
    try {
      final root = await _rootDir;
      final f = File(
        '${stagingDir(root, version).path}${Platform.pathSeparator}'
        '${relativeOf(relativeFile, version).replaceAll('/', Platform.pathSeparator)}',
      );
      return await f.exists() && await f.length() > 0;
    } catch (_) {
      return false;
    }
  }

  Future<File> stagedFile(int version, String relativeFile) async {
    final root = await _rootDir;
    return File(
      '${stagingDir(root, version).path}${Platform.pathSeparator}'
      '${relativeOf(relativeFile, version).replaceAll('/', Platform.pathSeparator)}',
    );
  }

  Future<Directory> ensureStagingDir(int version) async {
    final root = await _rootDir;
    final dir = stagingDir(root, version);
    await dir.create(recursive: true);
    return dir;
  }

  /// Parent of all staging directories. Exposed so the download service writes
  /// to exactly the location [install] will promote from.
  Future<Directory> getRoot() => _rootDir;

  void _report(
    Object error, {
    required String stage,
    Map<String, dynamic>? extra,
  }) {
    ErrorReportingService().reportError(
      error: error,
      userMessage: 'Artwork storage failed',
      feature: 'category_artwork_store',
      screen: stage,
      extraData: {'stage': stage, ...?extra},
    );
    if (kDebugMode) debugPrint('ArtworkStore[$stage]: $error');
  }
}