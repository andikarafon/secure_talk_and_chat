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

  // Stream profil pengguna selain pengguna yang sedang login.
  Stream<List<AppUser>> watchOtherUsers() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      return snapshot.docs
          .where((doc) => doc.id != currentUid)
          .map((doc) => AppUser.fromMap(doc.id, doc.data()))
          .where((user) => user.displayName.isNotEmpty)
          .toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
    });
  }

  // ID deterministik untuk satu pasangan pengguna.
  String conversationIdFor(String otherUid) {
    if (otherUid == currentUid) {
      throw ArgumentError('Tidak dapat membuat chat dengan diri sendiri.');
    }

    final ids = [currentUid, otherUid]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  // Mengambil percakapan yang sudah ada atau membuat yang baru.
  Future<String> getOrCreateConversation(String otherUid) async {
    final myUid = currentUid;

    if (otherUid == myUid) {
      throw ArgumentError('Tidak dapat membuat chat dengan diri sendiri.');
    }

    final ids = [myUid, otherUid]..sort();
    final conversationId = '${ids[0]}_${ids[1]}';

    final conversationRef = _firestore
        .collection('conversations')
        .doc(conversationId);

    final existing = await conversationRef.get();

    if (existing.exists) {
      final data = existing.data()!;
      final participants = List<String>.from(data['participants'] ?? const []);

      if (!participants.contains(myUid) || !participants.contains(otherUid)) {
        throw StateError('Data percakapan tidak valid.');
      }

      return conversationId;
    }

    await conversationRef.set({
      'participants': ids,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    return conversationId;
  }
}
