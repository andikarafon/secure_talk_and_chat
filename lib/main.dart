import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

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
// IDENTITY DEMO PAGE
// ============================================================

class IdentityDemoPage extends StatefulWidget {
  const IdentityDemoPage({super.key});

  @override
  State<IdentityDemoPage> createState() => _IdentityDemoPageState();
}

class _IdentityDemoPageState extends State<IdentityDemoPage> {
  final TextEditingController nameController = TextEditingController();

  bool isLoading = false;

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> enterDemo() async {
    final name = nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nama Anda terlebih dahulu')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final auth = FirebaseAuth.instance;

      // Gunakan sesi yang ada atau login anonim.
      User? user = auth.currentUser;

      if (user == null) {
        final credential = await auth.signInAnonymously();
        user = credential.user;
      }

      if (user == null) {
        throw Exception('Gagal mendapatkan identitas pengguna.');
      }

      // Simpan profil dengan UID sebagai document ID.
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      final existingProfile = await userRef.get();

      final profileData = <String, dynamic>{
        'displayName': name,
        'lastSeen': FieldValue.serverTimestamp(),
      };

      if (!existingProfile.exists) {
        profileData['createdAt'] = FieldValue.serverTimestamp();
      }

      await userRef.set(profileData, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DemoHomePage(userName: name, userId: user!.uid),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Autentikasi gagal: ${e.message ?? e.code}')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Firebase gagal: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Terjadi kesalahan: $e')));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
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

                  // Application logo
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
                    'Identitas Demo',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Masukkan nama untuk memulai demonstrasi aplikasi.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Nama pengguna',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: nameController,
                    enabled: !isLoading,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!isLoading) {
                        enterDemo();
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: 'Contoh: Andi',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Start demo button
                  SizedBox(
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4776F5), Color(0xFF7655E8)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ElevatedButton(
                        onPressed: isLoading ? null : enterDemo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Mulai Demo',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Icon(Icons.arrow_forward_rounded),
                                ],
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Responsive footer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Demo prototype • Belum terhubung ke server',
                          textAlign: TextAlign.center,
                          softWrap: true,
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
// DEMO HOME PAGE
// ============================================================

class DemoHomePage extends StatelessWidget {
  final String userName;
  final String userId;

  const DemoHomePage({super.key, required this.userName, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Secure Talk and Chat')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 38,
                child: Icon(Icons.person, size: 40),
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

              const SizedBox(height: 12),

              const Text(
                'Identitas pengguna berhasil dibuat.',
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Firebase UID',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),

              const SizedBox(height: 8),

              SelectableText(
                userId,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF93B4FF)),
              ),

              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF171F33),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.cloud_done_outlined,
                      size: 32,
                      color: Color(0xFF70D6A5),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Profil tersimpan di Cloud Firestore',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Chat real-time dan phone call '
                      'akan dikembangkan pada tahap berikutnya.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Kembali'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
