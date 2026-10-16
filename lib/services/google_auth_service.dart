import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  GoogleAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static Future<void>? _googleInitialization;

  Future<void> _initializeGoogleSignIn() {
    return _googleInitialization ??= GoogleSignIn.instance.initialize();
  }

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();

      // Minta pengguna memilih akun Google setiap kali login.
      provider.setCustomParameters({'prompt': 'select_account'});

      return _auth.signInWithPopup(provider);
    }

    await _initializeGoogleSignIn();

    final googleUser = await GoogleSignIn.instance.authenticate();

    final googleAuth = googleUser.authentication;
    final idToken = googleAuth.idToken;

    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google tidak memberikan ID token.',
      );
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);

    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    // Keluar dari sesi autentikasi Firebase.
    await _auth.signOut();

    // Keluar dari sesi Google pada Android.
    // Untuk web, pemilihan akun ditangani melalui
    // prompt: select_account saat login berikutnya.
    if (!kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
  }
}
