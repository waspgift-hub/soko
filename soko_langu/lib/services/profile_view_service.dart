import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

/// Tracks public-profile views: increments a `profileViews` counter on the
/// owner's users doc and pushes a notification to the owner the first time a
/// viewer opens their profile (throttled via SharedPreferences so one viewer
/// doesn't spam the owner on every visit).
class ProfileViewService {
  static const String _throttleKey = 'notified_profile_views';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notif = NotificationService();

  Future<void> trackView(String profileOwnerId, String profileOwnerName) async {
    final viewer = FirebaseAuth.instance.currentUser;
    if (viewer == null) return;
    if (viewer.uid == profileOwnerId) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = (prefs.getStringList(_throttleKey) ?? const []).toSet();
      final key = '${viewer.uid}:$profileOwnerId';
      if (seen.contains(key)) {
        _incrementCounter(profileOwnerId);
        return;
      }
      seen.add(key);
      await prefs.setStringList(_throttleKey, seen.toList());

      _incrementCounter(profileOwnerId);

      final viewerName = viewer.displayName ?? viewer.email ?? 'Someone';
      await _notif.sendNotification(
        userId: profileOwnerId,
        title: 'Profile View',
        body: '$viewerName viewed your profile',
        data: {'type': 'profile_view', 'viewerId': viewer.uid},
      );
    } catch (e) {
      // non-critical — never block profile rendering on view tracking
    }
  }

  Future<void> _incrementCounter(String profileOwnerId) async {
    try {
      await _db
          .collection('users')
          .doc(profileOwnerId)
          .update({'profileViews': FieldValue.increment(1)});
    } catch (_) {
      // counter may not exist yet — create it
      await _db
          .collection('users')
          .doc(profileOwnerId)
          .set({'profileViews': 1}, SetOptions(merge: true));
    }
  }
}
