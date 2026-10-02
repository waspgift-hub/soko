import 'dart:convert';

/// Parsed `manifest.json` for the downloadable Category Artwork Pack.
///
/// The manifest is the contract between the build pipeline and the app: it is
/// the only thing that decides what a pack contains, what each file should
/// hash to, and which taxonomy ids the pack is allowed to speak about.
class ArtworkManifest {
  /// Monotonic pack version. Compared with the locally installed version to
  /// decide whether an update is available.
  final int version;

  /// Pack identity, e.g. `category_artwork`. Guards against a manifest from a
  /// different pack being served at this path.
  final String pack;

  /// Lowest app version allowed to install this pack. A pack newer than the
  /// running app is not offered, because its taxonomy ids may not exist yet.
  final String minAppVersion;

  final DateTime generatedAt;

  /// Every artwork file in the pack, keyed by taxonomy id.
  final List<ArtworkAsset> assets;

  /// Total bytes of all [assets]; what the download screen shows up front.
  final int totalBytes;

  ArtworkManifest({
    required this.version,
    required this.pack,
    required this.minAppVersion,
    required this.generatedAt,
    required this.assets,
    required this.totalBytes,
  });

  ArtworkAsset? assetForCategory(String categoryId) => _byCategory[categoryId];

  /// Looks up subcategory artwork by its qualified key, `categoryId/subId`.
  /// A bare subcategory slug is ambiguous: `cleaning` is a subcategory of both
  /// `kitchen` and `services` in the shipped taxonomy.
  ArtworkAsset? assetForSubcategory(String key) => _bySub[key];

  Map<String, ArtworkAsset>? _categoryIndex;
  Map<String, ArtworkAsset>? _subIndex;

  Map<String, ArtworkAsset> get _byCategory =>
      _categoryIndex ??= {
        for (final a in assets)
          if (a.type == ArtworkAssetType.category) a.id: a,
      };

  Map<String, ArtworkAsset> get _bySub =>
      _subIndex ??= {
        for (final a in assets)
          if (a.type == ArtworkAssetType.subcategory) a.id: a,
      };

  /// Parses a manifest, throwing [ArtworkManifestException] with a
  /// human-readable reason on anything untrusted or malformed.
  ///
  /// Every failure here is fatal to the download: a manifest we cannot fully
  /// trust must never be partially applied.
  factory ArtworkManifest.parse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw ArtworkManifestException('Manifest is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ArtworkManifestException('Manifest root is not an object');
    }

    final version = _int(decoded['version'], 'version');
    if (version < 1) {
      throw ArtworkManifestException('Manifest version must be >= 1');
    }

    final pack = decoded['pack'];
    if (pack is! String || pack.isEmpty) {
      throw const ArtworkManifestException('Manifest pack name is missing');
    }

    final rawAssets = decoded['assets'];
    if (rawAssets is! List) {
      throw const ArtworkManifestException('Manifest assets is not a list');
    }

    final assets = <ArtworkAsset>[];
    final seenIds = <String>{};
    var total = 0;

    for (final entry in rawAssets) {
      if (entry is! Map<String, dynamic>) {
        throw const ArtworkManifestException('Asset entry is not an object');
      }
      final asset = ArtworkAsset.parse(entry);
      if (!seenIds.add('${asset.type.name}:${asset.id}')) {
        throw ArtworkManifestException('Duplicate asset id ${asset.id}');
      }
      total += asset.size;
      assets.add(asset);
    }

    if (assets.isEmpty) {
      throw const ArtworkManifestException('Manifest contains no assets');
    }

    return ArtworkManifest(
      version: version,
      pack: pack,
      minAppVersion: decoded['minAppVersion'] is String
          ? decoded['minAppVersion'] as String
          : '0.0.0',
      generatedAt:
          DateTime.tryParse('${decoded['generatedAt'] ?? ''}')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      assets: List.unmodifiable(assets),
      totalBytes: total,
    );
  }

  static int _int(Object? value, String field) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw ArtworkManifestException('Manifest $field is missing or not a number');
  }
}

enum ArtworkAssetType {
  category,
  subcategory;

  static ArtworkAssetType parse(String raw) {
    return switch (raw) {
      'category' => ArtworkAssetType.category,
      'subcategory' => ArtworkAssetType.subcategory,
      _ => throw ArtworkManifestException('Unknown asset type "$raw"'),
    };
  }
}

/// One downloadable artwork file.
///
/// [id] is the taxonomy slug (`electronics`, `phones`) — never a display name,
/// so the mapping survives re-localisation of the taxonomy.
class ArtworkAsset {
  final String id;
  final ArtworkAssetType type;
  final String? categoryId;
  final String file;
  final String sha256;
  final int size;
  final int width;
  final int height;

  /// Set when the pack is split into per-category chunks so the app can fetch
  /// one category's artwork instead of the whole pack.
  final String? group;

  const ArtworkAsset({
    required this.id,
    required this.type,
    required this.categoryId,
    required this.file,
    required this.sha256,
    required this.size,
    required this.width,
    required this.height,
    this.group,
  });

  factory ArtworkAsset.parse(Map<String, dynamic> map) {
    final id = map['id'];
    if (id is! String || id.isEmpty) {
      throw const ArtworkManifestException('Asset id is missing');
    }

    final file = map['file'];
    if (file is! String || file.isEmpty) {
      throw ArtworkManifestException('Asset $id has no file path');
    }
    // Path traversal guard: the file path is concatenated onto a base URL and
    // later onto a local directory. Only forward slashes and a known extension
    // are ever allowed, so neither `../` nor an absolute path can escape.
    if (file.contains('..') ||
        file.contains('\\') ||
        file.startsWith('/') ||
        !ArtworkAsset.allowedExtensions.any(
          (ext) => file.toLowerCase().endsWith(ext),
        )) {
      throw ArtworkManifestException('Asset $id has an unsafe file path');
    }

    final sha = map['sha256'];
    if (sha is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw ArtworkManifestException('Asset $id has an invalid sha256');
    }

    final size = map['size'];
    if (size is! int || size < 0) {
      throw ArtworkManifestException('Asset $id has an invalid size');
    }

    final typeRaw = map['type'];
    if (typeRaw is! String) {
      throw ArtworkManifestException('Asset $id has no type');
    }
    final type = ArtworkAssetType.parse(typeRaw);

    final categoryId = map['categoryId'];
    if (type == ArtworkAssetType.subcategory &&
        (categoryId is! String || categoryId.isEmpty)) {
      throw ArtworkManifestException(
        'Subcategory asset $id must declare categoryId',
      );
    }

    return ArtworkAsset(
      id: id,
      type: type,
      categoryId: categoryId is String ? categoryId : null,
      file: file,
      sha256: sha,
      size: size,
      width: map['width'] is int ? map['width'] as int : 0,
      height: map['height'] is int ? map['height'] as int : 0,
      group: map['group'] is String ? map['group'] as String : null,
    );
  }

  static const List<String> allowedExtensions = ['.webp', '.jpg', '.jpeg', '.png'];

  /// Human-readable byte count for the download screen.
  String get sizeLabel {
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '$size B';
  }
}

class ArtworkManifestException implements Exception {
  final String message;
  const ArtworkManifestException(this.message);

  @override
  String toString() => 'ArtworkManifestException: $message';
}