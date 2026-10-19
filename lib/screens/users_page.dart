import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/chat_service.dart';
import 'chat_page.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final ChatService _chatService = ChatService();

  String? _openingUserId;

  Future<void> _openConversation(AppUser user) async {
    if (_openingUserId != null) return;

    setState(() {
      _openingUserId = user.uid;
    });

    try {
      final conversationId = await _chatService.getOrCreateConversation(
        user.uid,
      );

      if (!mounted) return;

      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) => ChatPage(
            conversationId: conversationId,
            otherUserId: user.uid,
            otherUserName: user.displayName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuka percakapan: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingUserId = null;
        });
      }
    }
  }

  Widget _buildDebugPanel() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171B24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'INFORMASI USER',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            'CURRENT UID:\n${_chatService.currentUid}',
            style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
          ),
          const SizedBox(height: 4),
          // const Text(
          //   'Pilih pengguna untuk melihat TARGET UID '
          //   'dan CONVERSATION UID.',
          //   style: TextStyle(color: Colors.white70, fontSize: 11),
          // ),
        ],
      ),
    );
  }

  Widget _buildUserTile(AppUser user) {
    final isOpening = _openingUserId == user.uid;

    final conversationId = _chatService.conversationIdFor(user.uid);

    return Card(
      color: const Color(0xFF191D26),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF34558A),
          child: Text(
            user.displayName.isNotEmpty
                ? user.displayName[0].toUpperCase()
                : '?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          user.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pengguna Secure Talk',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 10),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 8),
              const Text(
                'TARGET UID:',
                style: TextStyle(
                  color: Colors.lightBlueAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                user.uid,
                style: const TextStyle(
                  color: Colors.lightBlueAccent,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'CONVERSATION UID:',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                conversationId,
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        trailing: isOpening
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.chat_bubble_outline,
                color: Colors.lightBlueAccent,
              ),
        onTap: _openingUserId != null ? null : () => _openConversation(user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        title: const Text('Pengguna'),
        backgroundColor: const Color(0xFF111318),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildDebugPanel(),
          Expanded(
            child: StreamBuilder<List<AppUser>>(
              stream: _chatService.watchOtherUsers(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Gagal memuat pengguna:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = snapshot.data ?? [];

                if (users.isEmpty) {
                  return const Center(
                    child: Text(
                      'Belum ada pengguna lain.\n'
                      'Login di perangkat lain untuk menguji chat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    return _buildUserTile(users[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
