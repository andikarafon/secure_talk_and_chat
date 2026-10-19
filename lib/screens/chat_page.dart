import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';

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

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || _sending) return;

    if (text.length > 4000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pesan maksimal 4000 karakter.')),
      );
      return;
    }

    setState(() {
      _sending = true;
    });

    _messageController.clear();

    try {
      await _chatService.sendMessage(
        conversationId: widget.conversationId,
        text: text,
      );
    } catch (e) {
      if (!mounted) return;

      _messageController.text = text;
      _messageController.selection = TextSelection.collapsed(
        offset: _messageController.text.length,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengirim pesan: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  String _formatTime(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    return 'Mengirim...';
  }

  Widget _buildConversationInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: const Color(0xFF171B24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'INFORMASI USER LOGIN',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            'CURRENT UID: ${_currentUid ?? "Belum login"}',
            style: const TextStyle(color: Colors.greenAccent, fontSize: 10),
          ),
          const SizedBox(height: 4),
          SelectableText(
            'TARGET UID: ${widget.otherUserId}',
            style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 10),
          ),
          const SizedBox(height: 4),
          SelectableText(
            'CONVERSATION UID: ${widget.conversationId}',
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    final isMine = data['senderId'] == _currentUid;
    final text = data['text'] as String? ?? '';
    final time = _formatTime(data['createdAt']);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFF34558A) : const Color(0xFF202631),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
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
              time,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
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
              padding: const EdgeInsets.all(16),
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

        final documents = snapshot.data?.docs ?? [];

        if (documents.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Belum ada pesan.\nMulai percakapan sekarang!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: false,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildMessage(documents[index]);
          },
        );
      },
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: const BoxDecoration(
          color: Color(0xFF111318),
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 5,
                maxLength: 4000,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Tulis pesan...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF202631),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: IconButton(
                onPressed: _sending ? null : _sendMessage,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF34558A),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey,
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111318),
        foregroundColor: Colors.white,
        toolbarHeight: 90,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.otherUserName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            const Text(
              'Secure Talk',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            SelectableText(
              'CONVERSATION UID: ${widget.conversationId}',
              style: const TextStyle(fontSize: 10, color: Colors.orangeAccent),
            ),
          ],
        ),
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
