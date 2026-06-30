import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class SokoCacheManager extends CacheManager {
  static const key = 'soko_image_cache';

  static SokoCacheManager? _instance;

  factory SokoCacheManager() {
    _instance ??= SokoCacheManager._();
    return _instance!;
  }

  SokoCacheManager._() : super(Config(
    key,
    stalePeriod: const Duration(days: 3),
    maxNrOfCacheObjects: 400,
    repo: JsonCacheInfoRepository(databaseName: key),
  ));
}
