import 'profile_media_controller.dart';

/// App-wide owner of the profile media queue (Namida miniplayer equivalent).
///
/// The seller profile section plays through this shared controller instead of
/// a screen-local one, so a persistent mini player in the bottom nav can
/// reflect and drive the same playback after the user navigates away. Only
/// one inline player exists at a time; the section registers itself while
/// visible so the mini bar hides instead of duplicating it.
class ProfileMediaSession {
  ProfileMediaSession._();

  static final ProfileMediaSession instance = ProfileMediaSession._();

  final ProfileMediaController controller = ProfileMediaController();

  String? sellerId;
  String? sellerName;
  int _inlinePlayers = 0;

  bool get hasInlinePlayer => _inlinePlayers > 0;

  Future<void> playSellerQueue({
    required String sellerId,
    required String sellerName,
    required List<ProfileMediaItem> items,
    int startAt = 0,
  }) async {
    this.sellerId = sellerId;
    this.sellerName = sellerName;
    await controller.setQueue(items, startAt: startAt);
  }

  void enterInlinePlayer() => _inlinePlayers++;

  void exitInlinePlayer() {
    if (_inlinePlayers > 0) _inlinePlayers--;
  }

  Future<void> stop() async {
    await controller.pause();
    await controller.setQueue(const []);
    sellerId = null;
    sellerName = null;
  }
}
