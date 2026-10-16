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

      await Navigator.push(
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
          behavior: SnackBarBehavior.floating,
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

  String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengguna')),
      body: StreamBuilder<List<AppUser>>(
        stream: _chatService.watchOtherUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildError(snapshot.error.toString());
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data ?? <AppUser>[];

          if (users.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: users.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = users[index];
              final isOpening = _openingUserId == user.uid;
              final isBusy = _openingUserId != null;

              return Card(
                margin: EdgeInsets.zero,
                color: const Color(0xFF191C24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF304B7E),
                    child: Text(
                      _initial(user.displayName),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  title: Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Pengguna Secure Talk'),
                  trailing: isOpening
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chat_bubble_outline_rounded),
                  enabled: !isBusy,
                  onTap: isBusy ? null : () => _openConversation(user),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.people_outline_rounded,
              size: 64,
              color: Color(0xFF8FA9E8),
            ),
            const SizedBox(height: 16),
            const Text(
              'Belum ada pengguna lain',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Jalankan Secure Talk and Chat pada HP kedua '
              'dan masuk dengan identitas berbeda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 52,
              color: Colors.orangeAccent,
            ),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat pengguna',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
