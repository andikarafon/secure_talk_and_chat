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

  String? _activeUserId;
  bool _showingDialog = false;

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return widget.child;
    }

    if (_activeUserId != user.uid) {
      _activeUserId = user.uid;
      _handledCallIds.clear();
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
    if (!mounted || _showingDialog) {
      return;
    }

    for (final callDoc in calls) {
      final Map<String, dynamic> data = callDoc.data();

      final String? callerId = data['callerId'] as String?;
      final String? calleeId = data['calleeId'] as String?;
      final String? conversationId = data['conversationId'] as String?;
      final String? status = data['status'] as String?;

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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _showingDialog = false;
          return;
        }

        _handleIncomingCall(
          callId: callDoc.id,
          callerId: callerId,
          conversationId: conversationId,
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
      final String callerName = await _getCallerName(callerId);

      if (!mounted) {
        return;
      }

      final callSnapshot = await _firestore
          .collection('calls')
          .doc(callId)
          .get();

      if (!callSnapshot.exists || callSnapshot.data()?['status'] != 'ringing') {
        return;
      }

      if (!mounted) {
        return;
      }

      final String? action = await showDialog<String>(
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

      if (!mounted || action == null) {
        return;
      }

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
      _showingDialog = false;
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
        final dynamic displayName = data?['displayName'];

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

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => ChatPage(
            conversationId: conversationId,
            otherUserId: callerId,
            otherUserName: callerName,
            openCallOnStart: true,
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Gagal menerima panggilan: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
