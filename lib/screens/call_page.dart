import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../services/call_signaling_service.dart';
import '../services/livekit_service.dart';

class CallPage extends StatefulWidget {
  final String? userId;
  final String conversationId;
  final String otherUserName;
  final String? callId;

  const CallPage({
    super.key,
    this.userId,
    required this.conversationId,
    required this.otherUserName,
    this.callId,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final LiveKitService _liveKitService = LiveKitService();
  final CallSignalingService _callSignalingService = CallSignalingService();

  final lk.Room _room = lk.Room(
    roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
  );

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;

  bool _connecting = false;
  bool _connected = false;
  bool _muted = false;
  bool _ending = false;
  bool _disposed = false;
  bool _finishedRemotely = false;

  String _status = 'Siap menghubungkan panggilan';
  String? _error;

  void _debugLog(String message) {
    debugPrint('[LIVEKIT DEBUG] $message');
  }

  @override
  void initState() {
    super.initState();

    _room.addListener(_onRoomChanged);

    _debugLog('========== CALL PAGE STARTED ==========');
    _debugLog('Conversation ID: ${widget.conversationId}');
    _debugLog('Call ID: ${widget.callId}');
    _debugLog('User ID: ${widget.userId}');

    _startCallStatusListener();
    _connectToRoom();
  }

  // ============================================================
  // FIRESTORE CALL STATUS
  // ============================================================

  void _startCallStatusListener() {
    final callId = widget.callId;

    if (callId == null || callId.trim().isEmpty) {
      _debugLog('ERROR: Call ID kosong; listener status tidak diaktifkan.');
      return;
    }

    _debugLog('Memulai listener status untuk Call ID: $callId');

    _callSubscription = _callSignalingService
        .watchCall(callId: callId)
        .listen(
          (snapshot) {
            if (!mounted || _disposed || _ending) return;

            if (!snapshot.exists) {
              _debugLog('Dokumen panggilan tidak ditemukan.');
              unawaited(_finishFromRemote('Data panggilan tidak ditemukan.'));
              return;
            }

            final status = snapshot.data()?['status'] as String?;

            _debugLog('Status panggilan Firestore: $status');

            if (status == 'ended' || status == 'rejected') {
              unawaited(
                _finishFromRemote(
                  status == 'rejected'
                      ? 'Panggilan ditolak.'
                      : 'Panggilan telah berakhir.',
                ),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _debugLog('Call status listener error: $error');
            _debugLog('$stackTrace');
          },
        );
  }

  Future<void> _finishFromRemote(String message) async {
    if (_ending || _disposed || _finishedRemotely) return;

    _finishedRemotely = true;
    _ending = true;

    _debugLog('Mengakhiri panggilan dari perangkat lawan: $message');

    if (mounted) {
      setState(() {
        _status = message;
        _connected = false;
        _connecting = false;
      });
    }

    try {
      await _room.disconnect();
      _debugLog('LiveKit berhasil diputus dari perangkat ini.');
    } catch (e) {
      _debugLog('Remote disconnect error: $e');
    }

    if (!mounted || _disposed) return;

    Navigator.of(context).pop();
  }

  // ============================================================
  // LIVEKIT ROOM LISTENER
  // ============================================================

  void _onRoomChanged() {
    if (!mounted || _disposed) return;

    final connected = _room.connectionState == lk.ConnectionState.connected;
    final remoteParticipants = _room.remoteParticipants;

    setState(() {
      _connected = connected;

      if (_connecting || _ending) return;

      if (!connected) {
        _status = 'Koneksi terputus';
      } else if (remoteParticipants.isEmpty) {
        _status = 'Terhubung — menunggu lawan bicara';
      } else {
        _status = 'Terhubung — lawan bicara sudah masuk';
      }
    });
  }

  // ============================================================
  // CONNECT TO LIVEKIT
  // ============================================================

  Future<void> _connectToRoom() async {
    if (_connecting || _ending || _disposed || !mounted) return;

    setState(() {
      _connecting = true;
      _connected = false;
      _error = null;
      _status = 'Meminta token LiveKit...';
    });

    try {
      final credentials = await _liveKitService.getCallToken(
        roomName: widget.conversationId,
      );

      final expectedRoom = widget.conversationId;
      final tokenRoom = credentials['roomName'];
      final serverUrl = credentials['serverUrl'];
      final token = credentials['token'];

      _debugLog('Expected room: $expectedRoom');
      _debugLog('Token room: $tokenRoom');
      _debugLog('Server URL: $serverUrl');

      if (tokenRoom != expectedRoom) {
        throw Exception('Room dari token tidak cocok dengan conversationId.');
      }

      if (serverUrl is! String ||
          token is! String ||
          serverUrl.isEmpty ||
          token.isEmpty) {
        throw Exception('Server URL atau token tidak valid.');
      }

      if (!mounted || _disposed || _ending) return;

      setState(() {
        _status = 'Menghubungkan ke room LiveKit...';
      });

      await _room.connect(serverUrl, token);

      if (!mounted || _disposed || _ending) {
        await _room.disconnect();
        return;
      }

      final participant = _room.localParticipant;

      if (participant == null) {
        throw Exception('Peserta lokal tidak tersedia.');
      }

      await participant.setMicrophoneEnabled(true);

      if (!mounted || _disposed || _ending) {
        await _room.disconnect();
        return;
      }

      setState(() {
        _connecting = false;
        _connected = _room.connectionState == lk.ConnectionState.connected;
        _muted = false;
        _status = _room.remoteParticipants.isEmpty
            ? 'Terhubung — menunggu lawan bicara'
            : 'Terhubung — lawan bicara sudah masuk';
      });

      _debugLog('LiveKit berhasil terhubung.');
      _debugLog('Local identity: ${participant.identity}');
    } catch (e, stackTrace) {
      _debugLog('CONNECTION ERROR: $e');
      _debugLog('$stackTrace');

      try {
        await _room.disconnect();
      } catch (disconnectError) {
        _debugLog('Disconnect error: $disconnectError');
      }

      if (!mounted || _disposed || _ending) return;

      setState(() {
        _connecting = false;
        _connected = false;
        _error = e.toString();
        _status = 'Gagal menghubungkan panggilan';
      });
    } finally {
      if (mounted && !_disposed && _connecting && !_ending) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  // ============================================================
  // MUTE / UNMUTE
  // ============================================================

  Future<void> _toggleMicrophone() async {
    if (!_connected || _ending || _disposed) return;

    final participant = _room.localParticipant;

    if (participant == null) {
      _showMessage('Peserta lokal tidak tersedia.');
      return;
    }

    final newMuted = !_muted;

    try {
      await participant.setMicrophoneEnabled(!newMuted);

      if (!mounted || _disposed || _ending) return;

      setState(() {
        _muted = newMuted;
        _status = newMuted ? 'Mikrofon dimatikan' : 'Mikrofon aktif';
      });
    } catch (e) {
      _debugLog('MICROPHONE ERROR: $e');
      _showMessage('Gagal mengubah mikrofon: $e');
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted || _disposed) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // END CALL
  // ============================================================

  Future<void> _endCall() async {
    if (_ending || _disposed) return;

    setState(() {
      _ending = true;
      _status = 'Mengakhiri panggilan...';
    });

    final callId = widget.callId;

    _debugLog('Mengakhiri panggilan. Call ID: $callId');

    if (callId != null && callId.trim().isNotEmpty) {
      try {
        await _callSignalingService.updateCallStatus(
          callId: callId,
          status: 'ended',
        );

        _debugLog('Status panggilan berhasil diubah menjadi ended.');

        final snapshot = await FirebaseFirestore.instance
            .collection('calls')
            .doc(callId)
            .get();

        _debugLog(
          'Status Firestore setelah update: '
          '${snapshot.data()?['status']}',
        );
      } catch (e, stackTrace) {
        _debugLog('Gagal memperbarui status panggilan: $e');
        _debugLog('$stackTrace');
      }
    } else {
      _debugLog('ERROR: Call ID kosong; status tidak diperbarui.');
    }

    try {
      await _room.disconnect();
      _debugLog('LiveKit berhasil diputus.');
    } catch (e) {
      _debugLog('Room disconnect error: $e');
    }

    if (!mounted || _disposed) return;

    Navigator.of(context).pop();
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  Future<void> _cleanup() async {
    try {
      await _callSubscription?.cancel();
    } catch (e) {
      _debugLog('Subscription cleanup error: $e');
    }

    _room.removeListener(_onRoomChanged);

    try {
      await _room.disconnect();
    } catch (e) {
      _debugLog('Room disconnect cleanup error: $e');
    }

    try {
      await _room.dispose();
    } catch (e) {
      _debugLog('Room dispose error: $e');
    }

    _liveKitService.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_cleanup());
    super.dispose();
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final participantCount =
        _room.remoteParticipants.length + (_connected ? 1 : 0);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111318),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text('Phone Call'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.people_alt_outlined, size: 20),
                const SizedBox(width: 5),
                Text('$participantCount'),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 55,
                  backgroundColor: Color(0xFF34558A),
                  child: Icon(Icons.person, size: 60, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.otherUserName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Secure Talk and Chat',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 28),
                if (_connecting)
                  const CircularProgressIndicator()
                else
                  Icon(
                    _connected ? Icons.check_circle : Icons.error_outline,
                    color: _connected ? Colors.greenAccent : Colors.redAccent,
                    size: 32,
                  ),
                const SizedBox(height: 14),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _connecting || _ending ? null : _connectToRoom,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba Lagi'),
                  ),
                ],
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        IconButton.filled(
                          onPressed: _connected && !_ending
                              ? _toggleMicrophone
                              : null,
                          style: IconButton.styleFrom(
                            backgroundColor: _muted
                                ? Colors.orange
                                : const Color(0xFF34558A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(20),
                          ),
                          icon: Icon(
                            _muted ? Icons.mic_off : Icons.mic,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _muted ? 'Unmute' : 'Mute',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 36),
                    Column(
                      children: [
                        IconButton.filled(
                          onPressed: _connecting || _ending ? null : _endCall,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(20),
                          ),
                          icon: const Icon(Icons.call_end, size: 30),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Akhiri',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SelectableText(
                  'Room: ${widget.conversationId}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
