import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

class TierVisualService {
  static final TierVisualService _instance = TierVisualService._();
  factory TierVisualService() => _instance;
  TierVisualService._();

  static const String _wallpaperKey = 'wallpaper_path';

  Future<String?> getWallpaperPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_wallpaperKey);
  }

  Future<void> setWallpaperPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperKey, path);
  }

  Future<void> clearWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wallpaperKey);
  }

  Future<String?> pickAndSaveWallpaper() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    await setWallpaperPath(file.path);
    return file.path;
  }
}
