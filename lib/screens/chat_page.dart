import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import 'call_page.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _sending = false;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  // TAMBAHAN: Membuka halaman panggilan LiveKit.
  void _openCallPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallPage(
          conversationId: widget.conversationId,
          otherUserName: widget.otherUserName,
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || _sending) return;

    if (_currentUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan login terlebih dahulu.')),
      );
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await _chatService.sendMessage(
        conversationId: widget.conversationId,
        text: text,
      );

      _messageController.clear();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal mengirim pesan: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp is! Timestamp) return '';

    final dateTime = timestamp.toDate();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  // Informasi diagnostik yang sudah tersedia pada halaman chat.
  Widget _buildConversationInfo() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF151D30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('CURRENT UID', _currentUid ?? '-'),
          _infoRow('TARGET UID', widget.otherUserId),
          _infoRow('CONVERSATION UID', widget.conversationId),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> data, String documentId) {
    final currentUid = _currentUid;

    // Asumsi struktur pesan menggunakan senderId, text, dan createdAt.
    final senderId = data['senderId']?.toString() ?? '';
    final text = data['text']?.toString() ?? '';
    final timestamp = data['createdAt'];

    final isMe = senderId == currentUid;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF34558A) : const Color(0xFF202A3D),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMe ? 14 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _formatTime(timestamp),
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _chatService.watchMessages(widget.conversationId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Gagal memuat pesan:\n${snapshot.error}',
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

        final messages = snapshot.data?.docs ?? [];

        if (messages.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 48,
                  color: Colors.white30,
                ),
                SizedBox(height: 12),
                Text(
                  'Belum ada pesan',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                SizedBox(height: 4),
                Text(
                  'Mulai percakapan sekarang.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            // Daftar dibalik agar pesan terbaru berada di bawah.
            final message = messages[index];

            return _buildMessage(message.data(), message.id);
          },
        );
      },
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Tulis pesan...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF202A3D),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                tooltip: 'Kirim pesan',
                onPressed: _sending ? null : _sendMessage,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF34558A),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white12,
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111318),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherUserName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Text(
              'Secure Talk and Chat',
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          // TAMBAHAN: Tombol untuk membuka halaman panggilan LiveKit.
          IconButton(
            tooltip: 'Panggilan suara',
            onPressed: _openCallPage,
            icon: const Icon(Icons.call, color: Colors.greenAccent),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildConversationInfo(),
          Expanded(child: _buildMessages()),
          _buildComposer(),
        ],
      ),
    );
  }
}
