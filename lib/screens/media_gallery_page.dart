import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/chat_service.dart';

class MediaGalleryPage extends StatefulWidget {
  final String conversationId;
  final String otherUserName;

  const MediaGalleryPage({
    super.key,
    required this.conversationId,
    required this.otherUserName,
  });

  @override
  State<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends State<MediaGalleryPage>
    with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();

  late final TabController _tabController;

  static const Color _background = Color(0xFF0B1020);
  static const Color _surface = Color(0xFF111827);
  static const Color _textSecondary = Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp is! Timestamp) return '';

    final date = timestamp.toDate();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatSize(dynamic size) {
    if (size is! num) return '';

    final bytes = size.toDouble();

    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  List<Map<String, dynamic>> _extractPhotos(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> messages,
  ) {
    final photos = <Map<String, dynamic>>[];

    for (final message in messages) {
      final data = message.data();
      final type = data['type']?.toString() ?? '';

      if (type == 'image') {
        final raw = data['attachment'];

        if (raw is Map) {
          final attachment = Map<String, dynamic>.from(raw);
          final url = attachment['url']?.toString() ?? '';

          if (url.isNotEmpty) {
            photos.add({...attachment, 'createdAt': data['createdAt']});
          }
        }
      }

      if (type == 'image_gallery') {
        final rawAttachments = data['attachments'];

        if (rawAttachments is List) {
          for (final item in rawAttachments) {
            if (item is! Map) continue;

            final attachment = Map<String, dynamic>.from(item);
            final url = attachment['url']?.toString() ?? '';

            if (url.isNotEmpty) {
              photos.add({...attachment, 'createdAt': data['createdAt']});
            }
          }
        }
      }
    }

    return photos;
  }

  List<Map<String, dynamic>> _extractDocuments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> messages,
  ) {
    final documents = <Map<String, dynamic>>[];

    for (final message in messages) {
      final data = message.data();

      if (data['type']?.toString() != 'document') continue;

      final raw = data['attachment'];
      if (raw is! Map) continue;

      final attachment = Map<String, dynamic>.from(raw);
      final url = attachment['url']?.toString() ?? '';

      if (url.isEmpty) continue;

      documents.add({...attachment, 'createdAt': data['createdAt']});
    }

    return documents;
  }

  void _openPhotoViewer(List<Map<String, dynamic>> photos, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _PhotoViewerPage(photos: photos, initialIndex: initialIndex),
      ),
    );
  }

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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  IconData _documentIcon(String name) {
    final extension = name.split('.').last.toLowerCase();

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

  Widget _buildPhotos(List<Map<String, dynamic>> photos) {
    if (photos.isEmpty) {
      return _emptyState(
        Icons.photo_library_outlined,
        'Belum ada foto',
        'Foto yang dibagikan akan muncul di sini.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(3),
      itemCount: photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemBuilder: (context, index) {
        final photo = photos[index];
        final url = photo['url']?.toString() ?? '';

        return GestureDetector(
          onTap: () => _openPhotoViewer(photos, index),
          child: Hero(
            tag: 'shared-photo-$index-$url',
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: _surface,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image, color: Colors.white54),
              ),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;

                return Container(
                  color: _surface,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocuments(List<Map<String, dynamic>> documents) {
    if (documents.isEmpty) {
      return _emptyState(
        Icons.folder_open_outlined,
        'Belum ada dokumen',
        'Dokumen yang dibagikan akan muncul di sini.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: documents.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Colors.white10, indent: 70),
      itemBuilder: (context, index) {
        final document = documents[index];
        final name = document['name']?.toString() ?? 'Dokumen';
        final url = document['url']?.toString() ?? '';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 5,
          ),
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF202A3D),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_documentIcon(name), color: Colors.white, size: 25),
          ),
          title: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '${_formatSize(document['size'])}  •  '
              '${_formatDate(document['createdAt'])}',
              style: const TextStyle(color: _textSecondary, fontSize: 11),
            ),
          ),
          trailing: const Icon(
            Icons.open_in_new,
            color: _textSecondary,
            size: 19,
          ),
          onTap: () => _openDocument(url),
        );
      },
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: Colors.white30),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shared Media',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.otherUserName,
              style: const TextStyle(color: _textSecondary, fontSize: 11),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF5B9BFF),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: _textSecondary,
          tabs: const [
            Tab(
              icon: Icon(Icons.photo_library_outlined, size: 19),
              text: 'Photos',
            ),
            Tab(icon: Icon(Icons.folder_outlined, size: 19), text: 'Documents'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _chatService.watchMessages(widget.conversationId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _emptyState(
              Icons.error_outline,
              'Gagal memuat media',
              'Periksa koneksi dan coba kembali.',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final messages = snapshot.data?.docs ?? [];
          final photos = _extractPhotos(messages);
          final documents = _extractDocuments(messages);

          return TabBarView(
            controller: _tabController,
            children: [_buildPhotos(photos), _buildDocuments(documents)],
          );
        },
      ),
    );
  }
}

class _PhotoViewerPage extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;

  const _PhotoViewerPage({required this.photos, required this.initialIndex});

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.photos.length}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          final url = widget.photos[index]['url']?.toString() ?? '';

          return Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image,
                  color: Colors.white70,
                  size: 60,
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;

                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
