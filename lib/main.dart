import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/chat_page.dart';
import 'screens/users_page.dart';
import 'services/chat_service.dart';
import 'services/google_auth_service.dart';
import 'widgets/incoming_call_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const SecureTalkApp());
}

// ============================================================
// APPLICATION
// ============================================================

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
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          elevation: 0,
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
      home: const AuthGate(),
    );
  }
}

// ============================================================
// AUTH GATE
// ============================================================

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memeriksa status login:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const IdentityDemoPage();
        }

        final displayName = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : user.email?.split('@').first ?? 'Pengguna';

        return IncomingCallListener(
          child: DemoHomePage(
            userName: displayName,
            userId: user.uid,
            userEmail: user.email ?? '',
            photoUrl: user.photoURL,
          ),
        );
      },
    );
  }
}

// ============================================================
// GOOGLE LOGIN
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

      await userRef.set(profileData, SetOptions(merge: true));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login Google gagal: ${e.message ?? e.code}')),
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
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF4776F5);
    const panel = Color(0xFF121A2B);
    const muted = Color(0xFF9AA6BD);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        size: 40,
                        color: Color(0xFF82A2FF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                  const Text(
                    'Connect privately. Talk freely.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 14),
                  ),
                  const SizedBox(height: 44),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF29344A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Welcome',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Login menggunakan akun Google '
                          'untuk mulai mengobrol.',
                          style: TextStyle(color: muted, height: 1.6),
                        ),
                        const SizedBox(height: 26),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : loginWithGoogle,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF202124),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.g_mobiledata_rounded,
                                        size: 30,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Lanjutkan dengan Google',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 17,
                              color: muted,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Autentikasi menggunakan Firebase',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: muted, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'SECURE TALK AND CHAT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF66738D),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
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

class DemoHomePage extends StatefulWidget {
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

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();

  String _searchText = '';
  bool _isTestingFirestore = false;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      if (!mounted) return;

      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ==========================================================
  // FIRESTORE ACCESS DIAGNOSTIC
  // ==========================================================

  Future<void> _testConversationAccess() async {
    if (_isTestingFirestore) return;

    final user = FirebaseAuth.instance.currentUser;

    try {
      final idToken = await user?.getIdToken(true);

      debugPrint('========== AUTH TOKEN DIAGNOSTIC ==========');
      debugPrint('AUTH UID: ${user?.uid}');
      debugPrint('TOKEN AVAILABLE: ${idToken != null && idToken.isNotEmpty}');
      debugPrint('===========================================');
    } on FirebaseAuthException catch (e) {
      debugPrint('TOKEN ERROR: ${e.code} - ${e.message}');
    }

    if (user == null) {
      debugPrint('TEST FIRESTORE: User belum login.');
      _showDiagnosticResult('Pengguna belum login. Silakan login kembali.');
      return;
    }

    setState(() => _isTestingFirestore = true);

    final firestore = FirebaseFirestore.instance;

    // ID dokumen percakapan yang sebelumnya muncul pada log.
    const conversationId =
        '30bTj5JyDSdRMJyJILbYd9PCYcv1_lOQssLX3xhMIM9M4v2xQA3QMbhj1';

    final results = <String>[];

    debugPrint('');
    debugPrint('========== FIRESTORE ACCESS TEST ==========');
    debugPrint('PROJECT ID: ${firestore.app.options.projectId}');
    debugPrint('AUTH UID: ${user.uid}');
    debugPrint('HOME UID: ${widget.userId}');
    debugPrint('CONVERSATION ID: $conversationId');

    // TEST A: GET dokumen langsung dari server.
    try {
      final doc = await firestore
          .collection('conversations')
          .doc(conversationId)
          .get(const GetOptions(source: Source.server));

      final participants = doc.data()?['participants'];

      debugPrint('TEST GET SERVER: BERHASIL');
      debugPrint('DOCUMENT EXISTS: ${doc.exists}');
      debugPrint('PARTICIPANTS: $participants');

      results.add(
        'GET dokumen: BERHASIL\n'
        'Dokumen ditemukan: ${doc.exists}\n'
        'Peserta: $participants',
      );
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('TEST GET SERVER: GAGAL');
      debugPrint('ERROR CODE: ${e.code}');
      debugPrint('ERROR MESSAGE: ${e.message}');
      debugPrintStack(stackTrace: stackTrace);

      results.add(
        'GET dokumen: GAGAL\n'
        'Kode: ${e.code}\n'
        'Pesan: ${e.message ?? "-"}',
      );
    } catch (e, stackTrace) {
      debugPrint('TEST GET SERVER: ERROR TAK TERDUGA: $e');
      debugPrintStack(stackTrace: stackTrace);

      results.add('GET dokumen: ERROR\n$e');
    }

    // TEST B: QUERY daftar percakapan langsung dari server.
    try {
      final result = await firestore
          .collection('conversations')
          .where('participants', arrayContains: user.uid)
          .get(const GetOptions(source: Source.server));

      debugPrint('TEST QUERY SERVER: BERHASIL');
      debugPrint('DOCUMENT COUNT: ${result.docs.length}');
      debugPrint('FROM CACHE: ${result.metadata.isFromCache}');

      for (final doc in result.docs) {
        debugPrint('QUERY DOCUMENT ID: ${doc.id}');
        debugPrint('QUERY PARTICIPANTS: ${doc.data()['participants']}');
      }

      results.add(
        'QUERY daftar percakapan: BERHASIL\n'
        'Jumlah dokumen: ${result.docs.length}\n'
        'Dari cache: ${result.metadata.isFromCache}',
      );
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('TEST QUERY SERVER: GAGAL');
      debugPrint('ERROR CODE: ${e.code}');
      debugPrint('ERROR MESSAGE: ${e.message}');
      debugPrintStack(stackTrace: stackTrace);

      results.add(
        'QUERY daftar percakapan: GAGAL\n'
        'Kode: ${e.code}\n'
        'Pesan: ${e.message ?? "-"}',
      );
    } catch (e, stackTrace) {
      debugPrint('TEST QUERY SERVER: ERROR TAK TERDUGA: $e');
      debugPrintStack(stackTrace: stackTrace);

      results.add('QUERY daftar percakapan: ERROR\n$e');
    }

    debugPrint('========== END FIRESTORE ACCESS TEST ==========');
    debugPrint('');

    if (!mounted) return;

    setState(() => _isTestingFirestore = false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hasil Diagnostik Firestore'),
          content: SingleChildScrollView(
            child: SelectableText(
              'Project ID: ${firestore.app.options.projectId}\n'
              'UID: ${user.uid}\n\n'
              '${results.join('\n\n')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  void _showDiagnosticResult(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ==========================================================
  // FIRESTORE CONVERSATION QUERY
  // ==========================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> _watchConversations() {
    final currentUser = FirebaseAuth.instance.currentUser;

    debugPrint('');
    debugPrint('========== CHAT QUERY START ==========');
    debugPrint(
      'Firebase project: '
      '${FirebaseFirestore.instance.app.options.projectId}',
    );
    debugPrint('Firebase Auth UID: ${currentUser?.uid ?? "null"}');
    debugPrint('HOME UID widget: ${widget.userId}');
    debugPrint('Authenticated: ${currentUser != null}');
    debugPrint('QUERY COLLECTION: conversations');
    debugPrint('QUERY FIELD: participants');
    debugPrint('QUERY OPERATOR: arrayContains');

    if (currentUser == null) {
      debugPrint('CHAT QUERY ABORTED: User belum login.');
      debugPrint('======================================');

      return const Stream.empty();
    }

    debugPrint(
      'QUERY: conversations where participants '
      'arrayContains ${currentUser.uid}',
    );
    debugPrint('======================================');

    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots()
        .handleError((Object error, StackTrace stackTrace) {
          debugPrint('');
          debugPrint('========== CHAT QUERY ERROR ==========');
          debugPrint('Error type: ${error.runtimeType}');
          debugPrint('Error detail: $error');
          debugPrintStack(stackTrace: stackTrace);
          debugPrint('=======================================');
        });
  }

  // ==========================================================
  // DEBUG SNAPSHOT
  // ==========================================================

  void _logSnapshotDiagnostic(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> conversations,
  ) {
    debugPrint('');
    debugPrint('========== CHAT SNAPSHOT DIAGNOSTIC ==========');
    debugPrint('STREAM STATE: ${snapshot.connectionState}');
    debugPrint('HAS DATA: ${snapshot.hasData}');
    debugPrint('HAS ERROR: ${snapshot.hasError}');
    debugPrint('ERROR: ${snapshot.error}');
    debugPrint('FROM CACHE: ${snapshot.data?.metadata.isFromCache}');
    debugPrint('PENDING WRITES: ${snapshot.data?.metadata.hasPendingWrites}');
    debugPrint('DOCUMENT COUNT: ${conversations.length}');

    if (snapshot.data != null) {
      debugPrint('SNAPSHOT METADATA: ${snapshot.data!.metadata}');

      for (final doc in conversations) {
        final data = doc.data();

        debugPrint('--- CONVERSATION DOCUMENT ---');
        debugPrint('DOCUMENT ID: ${doc.id}');
        debugPrint('PARTICIPANTS: ${data['participants']}');
        debugPrint('LAST MESSAGE: ${data['lastMessage']}');
        debugPrint('LAST MESSAGE AT: ${data['lastMessageAt']}');
      }
    }

    debugPrint('==============================================');
  }

  // ==========================================================
  // OPEN CHAT
  // ==========================================================

  Future<void> _openChat({
    required String otherUserId,
    required String otherUserName,
  }) async {
    try {
      final conversationId = await _chatService.getOrCreateConversation(
        otherUserId,
      );

      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(
            conversationId: conversationId,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('GAGAL MEMBUKA CHAT: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal membuka chat: $e')));
    }
  }

  // ==========================================================
  // SIGN OUT
  // ==========================================================

  Future<void> _signOut() async {
    try {
      await GoogleAuthService().signOut();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal logout: $e')));
    }
  }

  // ==========================================================
  // OPEN USER LIST
  // ==========================================================

  Future<void> _openUsersPage() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => const UsersPage()));
  }

  // ==========================================================
  // CONVERSATION LIST
  // ==========================================================

  Widget _buildConversationList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _watchConversations(),
      builder: (context, snapshot) {
        debugPrint('CONVERSATION STREAM STATE: ${snapshot.connectionState}');

        if (snapshot.hasError) {
          debugPrint('CONVERSATION STREAM BUILDER ERROR: ${snapshot.error}');
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF4776F5)),
          );
        }

        final conversations = snapshot.data?.docs.toList() ?? [];

        _logSnapshotDiagnostic(snapshot, conversations);

        if (snapshot.hasError && !snapshot.hasData) {
          return _buildMessageState(
            icon: Icons.cloud_off_outlined,
            title: 'Gagal memuat percakapan',
            message: 'Periksa Firestore Rules dan log diagnostik.',
            actionLabel: 'Coba lagi',
            onAction: () {
              setState(() {});
            },
          );
        }

        final validConversations = conversations.where((doc) {
          final data = doc.data();
          final participants = data['participants'];

          return participants is List && participants.contains(widget.userId);
        }).toList();

        debugPrint(
          'VALID CONVERSATIONS AFTER FILTER: '
          '${validConversations.length}',
        );

        if (validConversations.isEmpty) {
          return _buildMessageState(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Belum ada percakapan',
            message: 'Mulai percakapan dengan pengguna lain.',
            actionLabel: 'Chat baru',
            onAction: _openUsersPage,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          itemCount: validConversations.length,
          itemBuilder: (context, index) {
            final conversation = validConversations[index];
            final data = conversation.data();

            final participants = List<String>.from(
              data['participants'] as List,
            );

            final otherUserId = participants.firstWhere(
              (uid) => uid != widget.userId,
              orElse: () => '',
            );

            if (otherUserId.isEmpty) {
              return const SizedBox.shrink();
            }

            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(otherUserId)
                  .get(),
              builder: (context, userSnapshot) {
                final userData = userSnapshot.data?.data();

                final otherUserName =
                    userData?['displayName']?.toString() ?? 'Pengguna';

                final lastMessage = data['lastMessage']?.toString() ?? '';

                if (_searchText.isNotEmpty &&
                    !otherUserName.toLowerCase().contains(_searchText) &&
                    !lastMessage.toLowerCase().contains(_searchText)) {
                  return const SizedBox.shrink();
                }

                return _buildConversationTile(
                  name: otherUserName,
                  lastMessage: lastMessage.isEmpty
                      ? 'Mulai percakapan'
                      : lastMessage,
                  onTap: () => _openChat(
                    otherUserId: otherUserId,
                    otherUserName: otherUserName,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ==========================================================
  // CONVERSATION TILE
  // ==========================================================

  Widget _buildConversationTile({
    required String name,
    required String lastMessage,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: const Color(0xFF24365C),
        child: Text(
          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
          style: const TextStyle(
            color: Color(0xFFBBD0FF),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
    );
  }

  // ==========================================================
  // EMPTY / ERROR STATE
  // ==========================================================

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Colors.white30),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.5),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // HOME UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Secure Talk',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            SizedBox(height: 2),
            Text(
              'Messages',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Profil dan pengaturan',
            icon: CircleAvatar(
              radius: 17,
              backgroundImage:
                  widget.photoUrl != null && widget.photoUrl!.isNotEmpty
                  ? NetworkImage(widget.photoUrl!)
                  : null,
              child: widget.photoUrl == null || widget.photoUrl!.isEmpty
                  ? const Icon(Icons.person, size: 20)
                  : null,
            ),
            onSelected: (value) {
              if (value == 'profile') {
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) {
                    return AlertDialog(
                      title: const Text('Profil pengguna'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.userName),
                          const SizedBox(height: 8),
                          SelectableText(widget.userEmail),
                          const SizedBox(height: 8),
                          SelectableText('UID: ${widget.userId}'),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Tutup'),
                        ),
                      ],
                    );
                  },
                );
              } else if (value == 'diagnostic') {
                _testConversationAccess();
              } else if (value == 'logout') {
                _signOut();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline),
                    SizedBox(width: 12),
                    Text('Profil'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'diagnostic',
                enabled: !_isTestingFirestore,
                child: Row(
                  children: [
                    const Icon(Icons.fact_check_outlined),
                    const SizedBox(width: 12),
                    Text(
                      _isTestingFirestore
                          ? 'Sedang menguji Firestore...'
                          : 'Diagnostik Firestore',
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 12),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cari percakapan...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(
                        tooltip: 'Hapus pencarian',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      )
                    : null,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Pesan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildConversationList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openUsersPage,
        tooltip: 'Chat baru',
        backgroundColor: const Color(0xFF4776F5),
        foregroundColor: Colors.white,
        child: const Icon(Icons.chat_rounded),
      ),
    );
  }
}
