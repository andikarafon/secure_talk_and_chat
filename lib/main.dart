import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/users_page.dart';
import 'services/google_auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const SecureTalkApp());
}

class SecureTalkApp extends StatelessWidget {
  const SecureTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0B1020);
    const blue = Color(0xFF4776F5);

    return MaterialApp(
      title: 'Secure Talk and Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: navy,
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF171F33),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const IdentityDemoPage(),
    );
  }
}

// ============================================================
// GOOGLE LOGIN PAGE
// ============================================================

class IdentityDemoPage extends StatefulWidget {
  const IdentityDemoPage({super.key});

  @override
  State<IdentityDemoPage> createState() => _IdentityDemoPageState();
}

class _IdentityDemoPageState extends State<IdentityDemoPage> {
  final GoogleAuthService _googleAuthService = GoogleAuthService();

  bool isLoading = false;

  Future<void> loginWithGoogle() async {
    if (isLoading) return;

    setState(() => isLoading = true);

    try {
      final credential = await _googleAuthService.signInWithGoogle();

      final user = credential.user;

      if (user == null) {
        throw Exception('Firebase tidak mengembalikan pengguna.');
      }

      final displayName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : user.email?.split('@').first ?? 'Pengguna';

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      final existingProfile = await userRef.get();

      final profileData = <String, dynamic>{
        'displayName': displayName,
        'lastSeen': FieldValue.serverTimestamp(),
      };

      if (!existingProfile.exists) {
        profileData['createdAt'] = FieldValue.serverTimestamp();
      }

      // Mengikuti field yang diizinkan oleh Firestore Rules saat ini.
      await userRef.set(profileData, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DemoHomePage(
            userName: displayName,
            userId: user.uid,
            userEmail: user.email ?? '',
            photoUrl: user.photoURL,
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login Google gagal: ${e.message ?? e.code}'),
          duration: const Duration(seconds: 5),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Firebase gagal: ${e.message ?? e.code}'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi kesalahan: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4776F5), Color(0xFF8B5CF6)],
                        ),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Secure Talk\nand Chat',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      height: 1.2,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Connect privately. Talk freely.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 48),
                  const Text(
                    'Login ke Secure Talk',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gunakan akun Google Anda untuk masuk '
                    'dan mulai mengobrol.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: isLoading ? null : loginWithGoogle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF202124),
                        disabledBackgroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(
                        isLoading
                            ? 'Sedang login...'
                            : 'Lanjutkan dengan Google',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Autentikasi menggunakan Firebase',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HOME PAGE
// ============================================================

class DemoHomePage extends StatelessWidget {
  final String userName;
  final String userId;
  final String userEmail;
  final String? photoUrl;

  const DemoHomePage({
    super.key,
    required this.userName,
    required this.userId,
    required this.userEmail,
    this.photoUrl,
  });

  Future<void> _signOut(BuildContext context) async {
    try {
      await GoogleAuthService().signOut();

      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const IdentityDemoPage()),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal logout: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Talk and Chat'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundImage: photoUrl != null && photoUrl!.isNotEmpty
                      ? NetworkImage(photoUrl!)
                      : null,
                  child: photoUrl == null || photoUrl!.isEmpty
                      ? const Icon(Icons.person, size: 42)
                      : null,
                ),
                const SizedBox(height: 20),
                Text(
                  'Halo, $userName!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  userEmail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171F33),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Firebase UID',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        userId,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF93B4FF),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(
                            Icons.cloud_done_outlined,
                            color: Color(0xFF70D6A5),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Profil pengguna tersimpan di Firestore',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const UsersPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.people_outline_rounded),
                    label: const Text('Cari Pengguna untuk Chat'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _signOut(context),
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
