import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import 'media_service.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // =====================================================
  // CURRENT USER
  // =====================================================

  String get currentUid {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      throw StateError('Pengguna belum login.');
    }

    return uid;
  }

  // =====================================================
  // WATCH OTHER USERS
  // =====================================================

  Stream<List<AppUser>> watchOtherUsers() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      final uid = currentUid;

      final users = snapshot.docs
          .where((doc) => doc.id != uid)
          .map((doc) => AppUser.fromMap(doc.id, doc.data()))
          .toList();

      users.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

      return users;
    });
  }

  // =====================================================
  // CONVERSATION ID
  // =====================================================

  String conversationIdFor(String otherUid) {
    if (otherUid == currentUid) {
      throw ArgumentError('Tidak dapat chat dengan diri sendiri.');
    }

    final ids = [currentUid, otherUid]..sort();

    return '${ids[0]}_${ids[1]}';
  }

  // =====================================================
  // CONVERSATION REFERENCE
  // =====================================================

  DocumentReference<Map<String, dynamic>> _conversationRef(
    String conversationId,
  ) {
    return _firestore.collection('conversations').doc(conversationId);
  }

  // =====================================================
  // GET OR CREATE CONVERSATION
  // =====================================================

  Future<String> getOrCreateConversation(String otherUid) async {
    final myUid = currentUid;

    if (otherUid == myUid) {
      throw ArgumentError('Tidak dapat chat dengan diri sendiri.');
    }

    final ids = [myUid, otherUid]..sort();
    final conversationId = '${ids[0]}_${ids[1]}';
    final ref = _conversationRef(conversationId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);

      if (snapshot.exists) {
        final data = snapshot.data()!;

        final participants = List<String>.from(
          data['participants'] ?? const [],
        );

        if (!participants.contains(myUid) || !participants.contains(otherUid)) {
          throw StateError('Peserta percakapan tidak valid.');
        }

        return;
      }

      transaction.set(ref, {
        'participants': ids,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    });

    return conversationId;
  }

  // =====================================================
  // DIAGNOSTIC: QUERY CONVERSATIONS FROM SERVER
  // =====================================================

  /// Menguji query percakapan langsung ke server Firestore.
  ///
  /// Tidak mengubah atau menghapus data.
  /// Panggil setelah pengguna berhasil login.
  Future<void> diagnoseConversationQuery() async {
    debugPrint('========== SERVER QUERY DIAGNOSTIC ==========');

    try {
      final user = _auth.currentUser;

      if (user == null) {
        debugPrint('DIAGNOSTIC FAILED: Pengguna belum login.');
        return;
      }

      final uid = user.uid;

      debugPrint('FIREBASE PROJECT: ${_firestore.app.options.projectId}');
      debugPrint('AUTH UID: $uid');
      debugPrint('AUTHENTICATED: ${user.uid.isNotEmpty}');
      debugPrint('QUERY COLLECTION: conversations');
      debugPrint('QUERY FIELD: participants');
      debugPrint('QUERY OPERATOR: arrayContains');
      debugPrint('QUERY UID: $uid');

      final snapshot = await _firestore
          .collection('conversations')
          .where('participants', arrayContains: uid)
          .get(const GetOptions(source: Source.server));

      debugPrint('SERVER QUERY SUCCESS');
      debugPrint('FROM CACHE: ${snapshot.metadata.isFromCache}');
      debugPrint('DOCUMENT COUNT: ${snapshot.docs.length}');

      for (final doc in snapshot.docs) {
        final data = doc.data();

        debugPrint('--- CONVERSATION DOCUMENT ---');
        debugPrint('DOCUMENT ID: ${doc.id}');
        debugPrint('PARTICIPANTS: ${data['participants']}');
        debugPrint('LAST MESSAGE: ${data['lastMessage']}');
        debugPrint('LAST MESSAGE AT: ${data['lastMessageAt']}');
      }
    } on FirebaseException catch (e) {
      debugPrint('SERVER QUERY FAILED');
      debugPrint('ERROR CODE: ${e.code}');
      debugPrint('ERROR MESSAGE: ${e.message}');
    } catch (e, stackTrace) {
      debugPrint('UNEXPECTED DIAGNOSTIC ERROR: $e');
      debugPrint('$stackTrace');
    } finally {
      debugPrint('=============================================');
    }
  }

  // =====================================================
  // WATCH MESSAGES
  // =====================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(
    String conversationId,
  ) {
    return _conversationRef(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  // =====================================================
  // VALIDATE CONVERSATION PARTICIPANT
  // =====================================================

  Future<void> _validateConversationParticipant({
    required String conversationId,
    required String uid,
  }) async {
    if (conversationId.trim().isEmpty) {
      throw ArgumentError('Conversation ID tidak valid.');
    }

    final conversationRef = _conversationRef(conversationId);

    final conversation = await conversationRef.get(
      const GetOptions(source: Source.server),
    );

    if (!conversation.exists) {
      throw StateError('Percakapan tidak ditemukan.');
    }

    final data = conversation.data()!;

    final participants = List<String>.from(data['participants'] ?? const []);

    if (!participants.contains(uid)) {
      throw StateError('Anda bukan peserta percakapan ini.');
    }
  }

  // =====================================================
  // SEND TEXT MESSAGE
  // =====================================================

  Future<void> sendMessage({
    required String conversationId,
    required String text,
  }) async {
    final message = text.trim();

    if (message.isEmpty) return;

    if (message.length > 4000) {
      throw ArgumentError('Pesan maksimal 4000 karakter.');
    }

    final uid = currentUid;

    await _validateConversationParticipant(
      conversationId: conversationId,
      uid: uid,
    );

    final conversationRef = _conversationRef(conversationId);

    final batch = _firestore.batch();
    final messageRef = conversationRef.collection('messages').doc();

    batch.set(messageRef, {
      'senderId': uid,
      'text': message,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.update(conversationRef, {
      'lastMessage': message,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // =====================================================
  // SEND SINGLE MEDIA MESSAGE
  // =====================================================

  Future<void> sendMediaMessage({
    required String conversationId,
    required UploadedMedia media,
    String text = '',
  }) async {
    final uid = currentUid;
    final conversationRef = _conversationRef(conversationId);

    // ---------------------------------------------------
    // VALIDASI MEDIA TYPE
    // ---------------------------------------------------

    if (!['image', 'document'].contains(media.type)) {
      throw ArgumentError('Tipe attachment tidak valid.');
    }

    // ---------------------------------------------------
    // VALIDASI FILE SIZE
    // ---------------------------------------------------

    if (media.size <= 0) {
      throw ArgumentError('Ukuran file tidak valid.');
    }

    if (media.type == 'image' && media.size > MediaService.maxImageSize) {
      throw ArgumentError('Ukuran foto maksimal 10 MB.');
    }

    if (media.type == 'document' && media.size > MediaService.maxDocumentSize) {
      throw ArgumentError('Ukuran dokumen maksimal 20 MB.');
    }

    // ---------------------------------------------------
    // VALIDASI CONVERSATION
    // ---------------------------------------------------

    await _validateConversationParticipant(
      conversationId: conversationId,
      uid: uid,
    );

    // ---------------------------------------------------
    // VALIDASI TEXT
    // ---------------------------------------------------

    final messageText = text.trim();

    if (messageText.length > 4000) {
      throw ArgumentError('Pesan maksimal 4000 karakter.');
    }

    // ---------------------------------------------------
    // MESSAGE PREVIEW
    // ---------------------------------------------------

    final lastMessage = messageText.isNotEmpty
        ? messageText
        : media.type == 'image'
        ? '[Foto]'
        : '[Dokumen] ${media.name}';

    // ---------------------------------------------------
    // SIMPAN MESSAGE DAN UPDATE CONVERSATION
    // ---------------------------------------------------

    final batch = _firestore.batch();

    final messageRef = conversationRef.collection('messages').doc();

    batch.set(messageRef, {
      'senderId': uid,
      'text': messageText,
      'type': media.type,
      'attachment': {
        'name': media.name,
        'url': media.url,
        'path': media.storagePath,
        'mimeType': media.mimeType,
        'size': media.size,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.update(conversationRef, {
      'lastMessage': lastMessage,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    debugPrint('========== MEDIA MESSAGE SENT ==========');
    debugPrint('CONVERSATION ID: $conversationId');
    debugPrint('SENDER ID: $uid');
    debugPrint('MEDIA TYPE: ${media.type}');
    debugPrint('MEDIA NAME: ${media.name}');
    debugPrint('MEDIA SIZE: ${media.size}');
    debugPrint('STORAGE PATH: ${media.storagePath}');
    debugPrint('========================================');
  }

  // =====================================================
  // SEND GALLERY MESSAGE
  // =====================================================

  Future<void> sendGalleryMessage({
    required String conversationId,
    required List<UploadedMedia> mediaList,
    String text = '',
  }) async {
    final uid = currentUid;
    final conversationRef = _conversationRef(conversationId);

    // ---------------------------------------------------
    // VALIDASI JUMLAH FOTO
    // ---------------------------------------------------

    if (mediaList.isEmpty) {
      throw ArgumentError('Pilih minimal satu foto.');
    }

    if (mediaList.length > MediaService.maxGalleryImages) {
      throw ArgumentError(
        'Maksimal ${MediaService.maxGalleryImages} foto dalam satu galeri.',
      );
    }

    // ---------------------------------------------------
    // VALIDASI CAPTION
    // ---------------------------------------------------

    final messageText = text.trim();

    if (messageText.length > 4000) {
      throw ArgumentError('Pesan maksimal 4000 karakter.');
    }

    // ---------------------------------------------------
    // VALIDASI SETIAP FOTO DAN TOTAL UKURAN
    // ---------------------------------------------------

    int totalSize = 0;

    final List<Map<String, dynamic>> attachments = [];

    const allowedImageMimeTypes = ['image/jpeg', 'image/png', 'image/webp'];

    for (final media in mediaList) {
      if (media.type != 'image') {
        throw ArgumentError('Galeri hanya boleh berisi file gambar.');
      }

      if (!allowedImageMimeTypes.contains(media.mimeType)) {
        throw ArgumentError('Format foto ${media.name} tidak didukung.');
      }

      if (media.size <= 0) {
        throw ArgumentError('Ukuran foto ${media.name} tidak valid.');
      }

      if (media.size > MediaService.maxImageSize) {
        throw ArgumentError('Ukuran foto ${media.name} maksimal 10 MB.');
      }

      if (media.url.trim().isEmpty ||
          media.storagePath.trim().isEmpty ||
          media.name.trim().isEmpty) {
        throw ArgumentError('Informasi foto ${media.name} tidak lengkap.');
      }

      // Pastikan file berasal dari folder percakapan dan pengguna ini.
      final expectedPathPrefix = 'conversations/$conversationId/$uid/';

      if (!media.storagePath.startsWith(expectedPathPrefix)) {
        throw ArgumentError('Lokasi penyimpanan foto tidak valid.');
      }

      totalSize += media.size;

      attachments.add({
        'name': media.name,
        'url': media.url,
        'path': media.storagePath,
        'mimeType': media.mimeType,
        'size': media.size,
      });
    }

    if (totalSize > MediaService.maxGallerySize) {
      throw ArgumentError('Total ukuran galeri maksimal 100 MB.');
    }

    // ---------------------------------------------------
    // VALIDASI PESERTA CONVERSATION
    // ---------------------------------------------------

    await _validateConversationParticipant(
      conversationId: conversationId,
      uid: uid,
    );

    // ---------------------------------------------------
    // MESSAGE PREVIEW
    // ---------------------------------------------------

    final lastMessage = messageText.isNotEmpty
        ? messageText
        : '[Galeri Foto] ${mediaList.length} foto';

    // ---------------------------------------------------
    // SIMPAN SATU DOKUMEN GALLERY MESSAGE
    // ---------------------------------------------------

    final batch = _firestore.batch();

    final messageRef = conversationRef.collection('messages').doc();

    batch.set(messageRef, {
      'senderId': uid,
      'text': messageText,
      'type': 'image_gallery',
      'attachments': attachments,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.update(conversationRef, {
      'lastMessage': lastMessage,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // ---------------------------------------------------
    // DEBUG LOG
    // ---------------------------------------------------

    debugPrint('========== GALLERY MESSAGE SENT ==========');
    debugPrint('CONVERSATION ID: $conversationId');
    debugPrint('SENDER ID: $uid');
    debugPrint('TOTAL PHOTOS: ${mediaList.length}');
    debugPrint('TOTAL SIZE: $totalSize');
    debugPrint('CAPTION: $messageText');

    for (int i = 0; i < mediaList.length; i++) {
      final media = mediaList[i];

      debugPrint('--- PHOTO ${i + 1} ---');
      debugPrint('NAME: ${media.name}');
      debugPrint('SIZE: ${media.size}');
      debugPrint('MIME TYPE: ${media.mimeType}');
      debugPrint('STORAGE PATH: ${media.storagePath}');
    }

    debugPrint('==========================================');
  }
}
