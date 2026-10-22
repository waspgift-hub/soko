import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthSetupException implements Exception {
  const AuthSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      _initialized = true;
    } on FirebaseException catch (error) {
      throw AuthSetupException('Google login is not configured yet. Add this app to Firebase, enable Google in Authentication, and add android/app/google-services.json plus SHA fingerprints. (' + error.code + ')');
    } catch (_) {
      throw const AuthSetupException('Google login setup is incomplete. Configure Firebase for this Android app first.');
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    await _ensureInitialized();
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) throw const AuthSetupException('Google sign-in was cancelled.');
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      return await FirebaseAuth.instance.signInWithCredential(credential);
    } on AuthSetupException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AuthSetupException('Google login failed: ' + (error.message ?? error.code));
    } catch (_) {
      throw const AuthSetupException('Could not sign in with Google. Please try again.');
    }
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    await FirebaseAuth.instance.signOut();
    try { await GoogleSignIn().signOut(); } catch (_) {}
  }

  User? get currentUser => _initialized && Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;
}