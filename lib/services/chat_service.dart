import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get currentUid {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      throw StateError('Pengguna belum login.');
    }

    return uid;
  }

  Stream<List<AppUser>> watchOtherUsers() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      final users = snapshot.docs
          .where((doc) => doc.id != currentUid)
          .map((doc) => AppUser.fromMap(doc.id, doc.data()))
          .toList();

      users.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

      return users;
    });
  }

  String conversationIdFor(String otherUid) {
    if (otherUid == currentUid) {
      throw ArgumentError('Tidak dapat chat dengan diri sendiri.');
    }

    final ids = [currentUid, otherUid]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  DocumentReference<Map<String, dynamic>> _conversationRef(
    String conversationId,
  ) {
    return _firestore.collection('conversations').doc(conversationId);
  }

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

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(
    String conversationId,
  ) {
    return _conversationRef(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

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

    // Memastikan pengguna merupakan peserta percakapan.
    final conversation = await conversationRef.get();

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
