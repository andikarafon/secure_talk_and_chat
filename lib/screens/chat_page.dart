import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/chat_service.dart';
import '../services/call_signaling_service.dart';
import '../services/media_service.dart';
import 'call_page.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final bool openCallOnStart;
  final String? callId;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.openCallOnStart = false,
    this.callId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatService _chatService = ChatService();
  final MediaService _mediaService = MediaService();
  final CallSignalingService _callSignalingService = CallSignalingService();

  final TextEditingController _messageController = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  bool _sending = false;
  bool _uploadingMedia = false;
  bool _callPageOpened = false;

  double _uploadProgress = 0;

  String? _lastMessageId;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();

    if (widget.openCallOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openCallPage();
      });
    }
  }

  // ============================================================
  // OPEN CALL PAGE
  // ============================================================

  Future<void> _openCallPage() async {
    if (_callPageOpened) return;

    final currentUid = _currentUid;

    if (currentUid == null) {
      _showMessage('Silakan login terlebih dahulu.');
      return;
    }

    _callPageOpened = true;
    String? activeCallId;

    try {
      if (widget.openCallOnStart) {
        // Panggilan masuk menggunakan dokumen panggilan
        // yang sudah dibuat oleh penelepon.
        activeCallId = widget.callId;

        if (activeCallId == null || activeCallId.trim().isEmpty) {
          throw StateError('ID panggilan masuk tidak tersedia.');
        }
      } else {
        // Panggilan keluar membuat dokumen baru di Firestore.
        activeCallId = await _callSignalingService.createCall(
          conversationId: widget.conversationId,
          callerId: currentUid,
          calleeId: widget.otherUserId,
        );
      }

      if (!mounted) {
        if (!widget.openCallOnStart) {
          await _callSignalingService.cancelCall(callId: activeCallId);
        }
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CallPage(
            userId: currentUid,
            conversationId: widget.conversationId,
            otherUserName: widget.otherUserName,
            callId: activeCallId,
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Gagal membuka panggilan: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage('Gagal memulai panggilan: $e');
      }
    } finally {
      _callPageOpened = false;
    }
  }

  // ============================================================
  // SEND TEXT MESSAGE
  // ============================================================

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || _sending) return;

    if (text.length > 4000) {
      _showMessage('Pesan maksimal 4000 karakter.');
      return;
    }

    if (_currentUid == null) {
      _showMessage('Silakan login terlebih dahulu.');
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

      if (!mounted) return;

      _messageController.clear();
    } catch (e) {
      if (!mounted) return;

      _showMessage('Gagal mengirim pesan: $e');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  // ============================================================
  // ATTACHMENT OPTIONS
  // ============================================================

  Future<void> _showAttachmentOptions() async {
    if (_sending) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF202A3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Kirim Lampiran',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF34558A),
                    child: Icon(Icons.image, color: Colors.white),
                  ),
                  title: const Text(
                    'Foto dari Galeri',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'JPG, JPEG, PNG, WEBP',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () {
                    Navigator.pop(context, 'image');
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF34558A),
                    child: Icon(Icons.insert_drive_file, color: Colors.white),
                  ),
                  title: const Text(
                    'Dokumen',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'PDF, Word, Excel, PowerPoint, TXT',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () {
                    Navigator.pop(context, 'document');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;

    if (selected == 'image') {
      await _pickAndSendImage();
    } else if (selected == 'document') {
      await _pickAndSendDocument();
    }
  }

  // ============================================================
  // PICK AND SEND IMAGE
  // ============================================================

  Future<void> _pickAndSendImage() async {
    if (_sending) return;

    if (_currentUid == null) {
      _showMessage('Silakan login terlebih dahulu.');
      return;
    }

    setState(() {
      _sending = true;
      _uploadingMedia = true;
      _uploadProgress = 0;
    });

    try {
      final media = await _mediaService.pickAndUploadImage(
        conversationId: widget.conversationId,
        onProgress: (progress) {
          if (!mounted) return;

          setState(() {
            _uploadProgress = progress.clamp(0.0, 1.0);
          });
        },
      );

      if (media == null) return;

      await _chatService.sendMediaMessage(
        conversationId: widget.conversationId,
        media: media,
        text: _messageController.text.trim(),
      );

      if (!mounted) return;

      _messageController.clear();

      _showMessage('Foto berhasil dikirim.');
    } catch (e, stackTrace) {
      debugPrint('GAGAL MENGIRIM FOTO: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage('Gagal mengirim foto: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadingMedia = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  // ============================================================
  // PICK AND SEND DOCUMENT
  // ============================================================

  Future<void> _pickAndSendDocument() async {
    if (_sending) return;

    if (_currentUid == null) {
      _showMessage('Silakan login terlebih dahulu.');
      return;
    }

    setState(() {
      _sending = true;
      _uploadingMedia = true;
      _uploadProgress = 0;
    });

    try {
      final media = await _mediaService.pickAndUploadDocument(
        conversationId: widget.conversationId,
        onProgress: (progress) {
          if (!mounted) return;

          setState(() {
            _uploadProgress = progress.clamp(0.0, 1.0);
          });
        },
      );

      if (media == null) return;

      await _chatService.sendMediaMessage(
        conversationId: widget.conversationId,
        media: media,
        text: _messageController.text.trim(),
      );

      if (!mounted) return;

      _messageController.clear();

      _showMessage('Dokumen berhasil dikirim.');
    } catch (e, stackTrace) {
      debugPrint('GAGAL MENGIRIM DOKUMEN: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage('Gagal mengirim dokumen: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadingMedia = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  // ============================================================
  // MESSAGE TIME
  // ============================================================

  String _formatTime(dynamic timestamp) {
    if (timestamp is! Timestamp) return '';

    final dateTime = timestamp.toDate();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  // ============================================================
  // FORMAT FILE SIZE
  // ============================================================

  String _formatFileSize(dynamic size) {
    if (size is! num) return '';

    final bytes = size.toDouble();

    if (bytes < 1024) {
      return '${bytes.toInt()} B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // ============================================================
  // CONVERSATION INFORMATION
  // ============================================================

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

  // ============================================================
  // IMAGE ATTACHMENT
  // ============================================================

  Widget _buildImageAttachment(String url) {
    return GestureDetector(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(12),
              child: Stack(
                children: [
                  InteractiveViewer(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Padding(
                          padding: EdgeInsets.all(30),
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white,
                            size: 60,
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                      },
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 230,
          height: 180,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;

            final total = loadingProgress.expectedTotalBytes;
            final loaded = loadingProgress.cumulativeBytesLoaded;

            return Container(
              width: 230,
              height: 180,
              color: Colors.black26,
              alignment: Alignment.center,
              child: CircularProgressIndicator(
                value: total != null ? loaded / total : null,
                color: Colors.white,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 230,
              height: 120,
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, color: Colors.white70, size: 35),
                  SizedBox(height: 6),
                  Text(
                    'Foto tidak dapat ditampilkan',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // DOCUMENT ICON
  // ============================================================

  IconData _documentIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;

      case 'doc':
      case 'docx':
        return Icons.description;

      case 'xls':
      case 'xlsx':
        return Icons.table_chart;

      case 'ppt':
      case 'pptx':
        return Icons.slideshow;

      case 'txt':
        return Icons.article;

      default:
        return Icons.insert_drive_file;
    }
  }

  // ============================================================
  // OPEN DOCUMENT
  // ============================================================

  Future<void> _openDocument(String url) async {
    try {
      final uri = Uri.tryParse(url);

      if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
        throw ArgumentError('URL dokumen tidak valid.');
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        _showMessage('Tidak dapat membuka dokumen.');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Gagal membuka dokumen: $e');
      }
    }
  }

  // ============================================================
  // DOCUMENT ATTACHMENT
  // ============================================================

  Widget _buildDocumentAttachment({
    required String name,
    required String url,
    required dynamic size,
  }) {
    return InkWell(
      onTap: () => _openDocument(url),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(_documentIcon(name), color: Colors.white, size: 35),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(size),
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Ketuk untuk membuka',
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.open_in_new, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MESSAGE BUBBLE
  // ============================================================

  Widget _buildMessage(Map<String, dynamic> data) {
    final currentUid = _currentUid;

    final senderId = data['senderId']?.toString() ?? '';
    final text = data['text']?.toString() ?? '';
    final timestamp = data['createdAt'];
    final type = data['type']?.toString() ?? 'text';

    final isMe = senderId == currentUid;

    final rawAttachment = data['attachment'];

    final attachment = rawAttachment is Map
        ? Map<String, dynamic>.from(rawAttachment)
        : <String, dynamic>{};

    final attachmentUrl = attachment['url']?.toString() ?? '';
    final attachmentName = attachment['name']?.toString() ?? '';
    final attachmentSize = attachment['size'];

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
            if (type == 'image' && attachmentUrl.isNotEmpty)
              _buildImageAttachment(attachmentUrl),

            if (type == 'document' && attachmentUrl.isNotEmpty)
              _buildDocumentAttachment(
                name: attachmentName,
                url: attachmentUrl,
                size: attachmentSize,
              ),

            if (text.isNotEmpty) ...[
              if (type != 'text' || attachmentUrl.isNotEmpty)
                const SizedBox(height: 7),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ],

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

  // ============================================================
  // REAL-TIME MESSAGES
  // ============================================================

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

        final latestMessageId = messages.last.id;

        if (_lastMessageId != latestMessageId) {
          _lastMessageId = latestMessageId;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) {
              return;
            }

            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          });
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            return _buildMessage(messages[index].data());
          },
        );
      },
    );
  }

  // ============================================================
  // UPLOAD PROGRESS
  // ============================================================

  Widget _buildUploadProgress() {
    if (!_uploadingMedia) {
      return const SizedBox.shrink();
    }

    final percentage = (_uploadProgress * 100).toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Mengunggah lampiran...',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
              Text(
                '$percentage%',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: _uploadProgress,
            backgroundColor: Colors.white12,
            color: const Color(0xFF5B9BFF),
            minHeight: 4,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MESSAGE COMPOSER
  // ============================================================

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Lampirkan foto atau dokumen',
                  onPressed: _sending ? null : _showAttachmentOptions,
                  icon: const Icon(Icons.attach_file, color: Colors.white70),
                ),

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

            _buildUploadProgress(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HELPER
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // PAGE UI
  // ============================================================

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
