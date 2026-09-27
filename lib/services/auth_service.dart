import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Wraps Firebase Auth + Google Sign-In behind one small surface - the
/// rest of the app only ever talks to this, never to the Firebase or
/// Google plugins directly.
class AuthService {
  // Getters, not eagerly-initialized fields: constructing an AuthService
  // (as AuthGate does as soon as the app starts) must not itself touch
  // Firebase - that only happens once something actually calls
  // authStateChanges/currentUser/signInWithGoogle/signOut. This also
  // keeps AuthService safe to construct in a widget test that never
  // exercises those members.
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;
  GoogleSignIn get _googleSignIn => GoogleSignIn();

  /// Emits the current user right away, then again on every sign-in/out -
  /// this is what [AuthGate] listens to to decide which screen to show.
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  /// Runs the Google account picker, then exchanges the result for a
  /// Firebase session. Returns null (not an error) if the user closes
  /// the picker without choosing an account.
  Future<User?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _firebaseAuth.signInWithCredential(credential);
    return userCredential.user;
  }

  Future<void> signOut() async {
    await Future.wait([
      _firebaseAuth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }
}
