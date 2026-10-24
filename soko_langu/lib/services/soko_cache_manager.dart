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
    stalePeriod: const Duration(days: 7),
    // A marketplace grid streams past thousands of images in one session. At 400
    // objects the cache thrashed: scrolling back up re-downloaded and re-decoded
    // images that had just been evicted, which showed up as visible stutter on
    // exactly the interaction people repeat most. 1200 covers several screens of
    // browsing on a mid-range device while staying well inside the heap budget,
    // because images are decoded at display size rather than full resolution.
    maxNrOfCacheObjects: 1200,
    repo: JsonCacheInfoRepository(databaseName: key),
  ));
}
