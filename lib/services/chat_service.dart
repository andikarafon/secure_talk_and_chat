import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';

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
  // SEND MESSAGE
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
    final conversationRef = _conversationRef(conversationId);

    // Memastikan percakapan tersedia di server.
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
}
