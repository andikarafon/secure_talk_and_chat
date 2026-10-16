import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/chat_service.dart';

class UsersPage extends StatelessWidget {
  UsersPage({super.key}) : _chatService = ChatService();

  final ChatService _chatService;

  Future<void> _openConversation(BuildContext context, AppUser user) async {
    try {
      final conversationId = await _chatService.getOrCreateConversation(
        user.uid,
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Percakapan siap dengan ${user.displayName}')),
      );

      // Step 5.3 akan mengganti notifikasi ini
      // dengan halaman chat real-time.
      debugPrint('Conversation ID: $conversationId');
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal membuka percakapan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengguna')),
      body: StreamBuilder<List<AppUser>>(
        stream: _chatService.watchOtherUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat pengguna.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data ?? [];

          if (users.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline_rounded, size: 56),
                    SizedBox(height: 16),
                    Text(
                      'Belum ada pengguna lain',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Login dari HP kedua menggunakan nama berbeda '
                      'untuk mulai mencoba chat.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = users[index];

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      user.displayName.isNotEmpty
                          ? user.displayName[0].toUpperCase()
                          : '?',
                    ),
                  ),
                  title: Text(user.displayName),
                  subtitle: const Text('Pengguna Secure Talk'),
                  trailing: const Icon(Icons.chat_bubble_outline_rounded),
                  onTap: () => _openConversation(context, user),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
