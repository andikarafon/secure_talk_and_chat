import 'package:cloud_firestore/cloud_firestore.dart';

class CallSignalingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _calls =>
      _firestore.collection('calls');

  /// Membuat panggilan suara baru.
  ///
  /// Status awal panggilan adalah "ringing".
  /// Mengembalikan ID dokumen panggilan di Firestore.
  Future<String> createCall({
    required String conversationId,
    required String callerId,
    required String calleeId,
  }) async {
    if (callerId.trim().isEmpty || calleeId.trim().isEmpty) {
      throw ArgumentError('Caller ID dan Callee ID wajib diisi.');
    }

    if (callerId == calleeId) {
      throw ArgumentError('Tidak dapat menelepon akun sendiri.');
    }

    if (conversationId.trim().isEmpty) {
      throw ArgumentError('Conversation ID wajib diisi.');
    }

    final DocumentReference<Map<String, dynamic>> callRef = await _calls.add({
      'conversationId': conversationId,
      'callerId': callerId,
      'calleeId': calleeId,
      'status': 'ringing',
      'type': 'audio',
      'createdAt': FieldValue.serverTimestamp(),
      'answeredAt': null,
      'endedAt': null,
    });

    return callRef.id;
  }

  /// Memantau panggilan masuk untuk pengguna yang sedang login.
  ///
  /// Digunakan oleh IncomingCallListener agar panggilan
  /// dapat terdeteksi meskipun pengguna sedang berada
  /// di halaman utama, daftar pengguna, atau halaman chat.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchIncomingCalls({
    required String userId,
  }) {
    return _calls
        .where('calleeId', isEqualTo: userId)
        .where('status', isEqualTo: 'ringing')
        .snapshots();
  }

  /// Memantau satu panggilan berdasarkan ID dokumen.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchCall({
    required String callId,
  }) {
    return _calls.doc(callId).snapshots();
  }

  /// Mengambil data satu panggilan.
  Future<DocumentSnapshot<Map<String, dynamic>>> getCall({
    required String callId,
  }) {
    return _calls.doc(callId).get();
  }

  /// Memperbarui status panggilan.
  ///
  /// Status yang digunakan:
  /// - ringing
  /// - accepted
  /// - rejected
  /// - ended
  Future<void> updateCallStatus({
    required String callId,
    required String status,
  }) async {
    const List<String> allowedStatuses = [
      'ringing',
      'accepted',
      'rejected',
      'ended',
    ];

    if (!allowedStatuses.contains(status)) {
      throw ArgumentError('Status panggilan tidak valid: $status');
    }

    final Map<String, dynamic> updates = {'status': status};

    if (status == 'accepted') {
      updates['answeredAt'] = FieldValue.serverTimestamp();
    }

    if (status == 'rejected' || status == 'ended') {
      updates['endedAt'] = FieldValue.serverTimestamp();
    }

    await _calls.doc(callId).update(updates);
  }

  /// Membatalkan panggilan yang masih berstatus ringing.
  Future<void> cancelCall({required String callId}) async {
    await updateCallStatus(callId: callId, status: 'ended');
  }
}
