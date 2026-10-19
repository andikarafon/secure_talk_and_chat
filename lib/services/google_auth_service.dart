import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  GoogleAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static Future<void>? _googleInitialization;

  /// Inisialisasi Google Sign-In.
  Future<void> _initializeGoogleSignIn() {
    return _googleInitialization ??= _initializeGoogleSignInInternal();
  }

  Future<void> _initializeGoogleSignInInternal() async {
    // OAuth 2.0 Client ID bertipe Web application.
    // Pastikan ID ini benar-benar milik project Firebase Anda.
    const serverClientId =
        '372241843368-33bh7fqsbiead10crceogm4ad63kiq6s.apps.googleusercontent.com';

    // PEMERIKSAAN SEMENTARA
    debugPrint('========== GOOGLE SIGN-IN DEBUG ==========');
    debugPrint('Platform Web: $kIsWeb');
    debugPrint('Web Client ID tersedia: ${serverClientId.isNotEmpty}');
    debugPrint('Web Client ID panjang: ${serverClientId.length}');
    debugPrint('==========================================');

    if (!kIsWeb && serverClientId.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-server-client-id',
        message: 'Web Client ID belum dikonfigurasi.',
      );
    }

    await GoogleSignIn.instance.initialize(
      serverClientId: kIsWeb ? null : serverClientId,
    );
  }

  /// Login menggunakan akun Google.
  Future<UserCredential> signInWithGoogle() async {
    try {
      // Login untuk Web.
      if (kIsWeb) {
        final provider = GoogleAuthProvider();

        provider.setCustomParameters({'prompt': 'select_account'});

        return await _auth.signInWithPopup(provider);
      }

      // Login untuk Android.
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

      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException {
      rethrow;
    } on GoogleSignInException catch (e) {
      debugPrint('Google Sign-In error code: ${e.code}');
      debugPrint('Google Sign-In error description: ${e.description}');
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('Unexpected Google login error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Logout dari Firebase dan Google.
  Future<void> signOut() async {
    await _auth.signOut();

    if (!kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
  }
}
