import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/chat_page.dart';
import '../services/call_signaling_service.dart';

class IncomingCallListener extends StatefulWidget {
  final Widget child;

  const IncomingCallListener({super.key, required this.child});

  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener> {
  final CallSignalingService _callSignalingService = CallSignalingService();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Set<String> _handledCallIds = <String>{};

  // Menyimpan daftar panggilan masuk terbaru dari Firestore.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestIncomingCalls = [];

  String? _activeUserId;
  String? _activeDialogCallId;
  bool _showingDialog = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _activeCallSubscription;

  @override
  void dispose() {
    _activeCallSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return widget.child;
    }

    if (_activeUserId != user.uid) {
      _activeUserId = user.uid;
      _handledCallIds.clear();
      _latestIncomingCalls = [];
      _activeDialogCallId = null;
      _showingDialog = false;
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _callSignalingService.watchIncomingCalls(userId: user.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Incoming call listener error: ${snapshot.error}');
        }

        if (snapshot.hasData) {
          _processIncomingCalls(snapshot.data!.docs, user.uid);
        }

        return widget.child;
      },
    );
  }

  void _processIncomingCalls(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> calls,
    String currentUserId,
  ) {
    // Simpan snapshot terbaru meskipun dialog sebelumnya aktif.
    _latestIncomingCalls = calls;

    if (!mounted || _showingDialog) return;

    for (final callDoc in calls) {
      final data = callDoc.data();

      final callerId = data['callerId'] as String?;
      final calleeId = data['calleeId'] as String?;
      final conversationId = data['conversationId'] as String?;
      final status = data['status'] as String?;

      if (callerId == null ||
          calleeId != currentUserId ||
          conversationId == null ||
          status != 'ringing') {
        continue;
      }

      if (_handledCallIds.contains(callDoc.id)) {
        continue;
      }

      _handledCallIds.add(callDoc.id);
      _showingDialog = true;
      _activeDialogCallId = callDoc.id;

      debugPrint('[INCOMING CALL] Panggilan masuk terdeteksi: ${callDoc.id}');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _showingDialog = false;
          _activeDialogCallId = null;
          return;
        }

        unawaited(
          _handleIncomingCall(
            callId: callDoc.id,
            callerId: callerId,
            conversationId: conversationId,
          ),
        );
      });

      return;
    }
  }

  Future<void> _handleIncomingCall({
    required String callId,
    required String callerId,
    required String conversationId,
  }) async {
    try {
      final callerName = await _getCallerName(callerId);

      if (!mounted) return;

      final callSnapshot = await _firestore
          .collection('calls')
          .doc(callId)
          .get();

      if (!callSnapshot.exists || callSnapshot.data()?['status'] != 'ringing') {
        debugPrint(
          '[INCOMING CALL] Panggilan tidak lagi berstatus ringing: $callId',
        );
        return;
      }

      if (!mounted) return;

      final action = await _showIncomingCallDialog(
        callId: callId,
        callerName: callerName,
      );

      if (!mounted || action == null) return;

      if (action == 'reject') {
        await _rejectCall(callId);
        return;
      }

      if (action == 'accept') {
        await _acceptCall(
          callId: callId,
          callerId: callerId,
          callerName: callerName,
          conversationId: conversationId,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Gagal menangani panggilan masuk: $e');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (_activeDialogCallId == callId) {
        _activeDialogCallId = null;
        _showingDialog = false;

        debugPrint('[INCOMING CALL] Penanganan panggilan selesai: $callId');

        // Periksa ulang daftar terbaru setelah dialog selesai.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          final userId = _activeUserId;
          if (userId == null) return;

          _processIncomingCalls(_latestIncomingCalls, userId);
        });
      }
    }
  }

  Future<String?> _showIncomingCallDialog({
    required String callId,
    required String callerName,
  }) async {
    final navigator = Navigator.of(context);

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    statusSubscription;

    bool dialogClosed = false;

    void closeDialogIfActive() {
      if (dialogClosed) return;

      dialogClosed = true;

      if (navigator.mounted && navigator.canPop()) {
        navigator.pop();
      }
    }

    statusSubscription = _callSignalingService
        .watchCall(callId: callId)
        .listen(
          (snapshot) {
            final data = snapshot.data();
            final status = data?['status'] as String?;

            debugPrint('[INCOMING CALL] Status $callId: $status');

            if (!snapshot.exists ||
                (status != null &&
                    status != 'ringing' &&
                    status != 'accepted')) {
              closeDialogIfActive();
            }
          },
          onError: (Object error) {
            debugPrint('Gagal memantau status panggilan: $error');
          },
        );

    _activeCallSubscription = statusSubscription;

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              icon: const Icon(Icons.call, color: Colors.green, size: 48),
              title: const Text('Panggilan Masuk'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    callerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Panggilan suara masuk dari pengguna ini.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.spaceEvenly,
              actions: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop('reject');
                  },
                  icon: const Icon(Icons.call_end, color: Colors.red),
                  label: const Text(
                    'Tolak',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop('accept');
                  },
                  icon: const Icon(Icons.call),
                  label: const Text('Terima'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      await statusSubscription.cancel();

      if (identical(_activeCallSubscription, statusSubscription)) {
        _activeCallSubscription = null;
      }
    }
  }

  Future<String> _getCallerName(String callerId) async {
    try {
      final userSnapshot = await _firestore
          .collection('users')
          .doc(callerId)
          .get();

      if (userSnapshot.exists) {
        final data = userSnapshot.data();
        final displayName = data?['displayName'];

        if (displayName is String && displayName.trim().isNotEmpty) {
          return displayName.trim();
        }
      }
    } catch (e) {
      debugPrint('Gagal mengambil profil penelepon: $e');
    }

    return 'Pengguna';
  }

  Future<void> _rejectCall(String callId) async {
    try {
      await _callSignalingService.updateCallStatus(
        callId: callId,
        status: 'rejected',
      );

      debugPrint('[INCOMING CALL] Panggilan ditolak: $callId');
    } catch (e) {
      debugPrint('Gagal menolak panggilan: $e');
    }
  }

  Future<void> _acceptCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String conversationId,
  }) async {
    try {
      await _callSignalingService.updateCallStatus(
        callId: callId,
        status: 'accepted',
      );

      debugPrint('[INCOMING CALL] Panggilan diterima: $callId');

      if (!mounted) return;

      // Buka ChatPage tanpa menunggu sampai halaman ditutup.
      // Dengan begitu, proses listener tidak tertahan oleh
      // halaman percakapan yang dibuka.
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ChatPage(
              conversationId: conversationId,
              otherUserId: callerId,
              otherUserName: callerName,
              openCallOnStart: true,
              callId: callId,
            ),
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Gagal menerima panggilan: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
