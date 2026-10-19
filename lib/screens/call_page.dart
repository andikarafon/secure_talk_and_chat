import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../services/livekit_service.dart';

class CallPage extends StatefulWidget {
  final String conversationId;
  final String otherUserName;

  const CallPage({
    super.key,
    required this.conversationId,
    required this.otherUserName,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final LiveKitService _liveKitService = LiveKitService();
  final lk.Room _room = lk.Room();

  bool _connecting = false;
  bool _connected = false;
  bool _muted = false;
  bool _ending = false;
  bool _disposed = false;

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
    _connectToRoom();
  }

  void _onRoomChanged() {
    final state = _room.connectionState;
    final connected = state == lk.ConnectionState.connected;
    final remoteParticipants = _room.remoteParticipants;

    _debugLog('========== ROOM CHANGED ==========');
    _debugLog('Room name: ${_room.name}');
    _debugLog('Connection state: $state');
    _debugLog('Remote count: ${remoteParticipants.length}');
    _debugLog('Remote identities: ${remoteParticipants.keys.toList()}');
    _debugLog('==================================');

    if (!mounted || _disposed) return;

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

  Future<void> _connectToRoom() async {
    // Mencegah koneksi dimulai berkali-kali secara bersamaan.
    if (_connecting || _ending || _disposed) {
      _debugLog('Koneksi diabaikan: proses sedang berjalan.');
      return;
    }

    setState(() {
      _connecting = true;
      _connected = false;
      _error = null;
      _status = 'Meminta token LiveKit...';
    });

    try {
      _debugLog('STEP 1: Meminta token dari backend.');

      final credentials = await _liveKitService.getCallToken(
        roomName: widget.conversationId,
      );

      final expectedRoom = widget.conversationId;
      final tokenRoom = credentials['roomName'];
      final identity = credentials['identity'];
      final serverUrl = credentials['serverUrl'];
      final token = credentials['token'];

      _debugLog('========== TOKEN DEBUG ==========');
      _debugLog('Expected room: $expectedRoom');
      _debugLog('Token room: $tokenRoom');
      _debugLog('Token identity: $identity');
      _debugLog('Server URL: $serverUrl');
      _debugLog('Room matches: ${expectedRoom == tokenRoom}');
      _debugLog('Token present: ${token is String && token.isNotEmpty}');
      _debugLog('=================================');

      if (expectedRoom != tokenRoom) {
        throw Exception('Room dari token tidak cocok dengan conversationId.');
      }

      if (serverUrl is! String ||
          token is! String ||
          serverUrl.isEmpty ||
          token.isEmpty) {
        throw Exception('Server URL atau token tidak valid.');
      }

      if (!mounted || _disposed) return;

      setState(() {
        _status = 'Menghubungkan ke room LiveKit...';
      });

      _debugLog('STEP 2: Memulai Room.connect().');

      await _room.connect(
        serverUrl,
        token,
        roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
      );

      _debugLog('STEP 3: Room.connect() BERHASIL.');
      _debugLog('Connected room: ${_room.name}');
      _debugLog('Connection state: ${_room.connectionState}');
      _debugLog('Remote participants: ${_room.remoteParticipants.length}');

      final participant = _room.localParticipant;

      if (participant == null) {
        throw Exception('Peserta lokal tidak tersedia setelah koneksi.');
      }

      _debugLog('STEP 4: Mengaktifkan mikrofon.');

      await participant.setMicrophoneEnabled(true);

      _debugLog('Mikrofon berhasil diaktifkan.');
      _debugLog('Local identity: ${participant.identity}');

      if (!mounted || _disposed) {
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

      _debugLog('========== CONNECTION RESULT ==========');
      _debugLog('Expected room: $expectedRoom');
      _debugLog('Connected room: ${_room.name}');
      _debugLog('Connected: $_connected');
      _debugLog('Remote count: ${_room.remoteParticipants.length}');
      _debugLog('Remote identities: ${_room.remoteParticipants.keys.toList()}');
      _debugLog('========================================');
    } catch (e, stackTrace) {
      _debugLog('CONNECTION ERROR: $e');
      _debugLog('CONNECTION STACK TRACE:\n$stackTrace');

      try {
        await _room.disconnect();
      } catch (disconnectError) {
        _debugLog('Disconnect error: $disconnectError');
      }

      if (!mounted || _disposed) return;

      setState(() {
        _connecting = false;
        _connected = false;
        _error = e.toString();
        _status = 'Gagal menghubungkan panggilan';
      });
    } finally {
      if (mounted && !_disposed && _connecting) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

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

      _debugLog('Microphone muted: $newMuted');

      if (!mounted || _disposed) return;

      setState(() {
        _muted = newMuted;
        _status = newMuted ? 'Mikrofon dimatikan' : 'Mikrofon aktif';
      });
    } catch (e, stackTrace) {
      _debugLog('MICROPHONE ERROR: $e');
      _debugLog('$stackTrace');
      _showMessage('Gagal mengubah mikrofon: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted || _disposed) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _endCall() async {
    if (_ending || _disposed) return;

    setState(() {
      _ending = true;
      _status = 'Mengakhiri panggilan...';
    });

    _debugLog('Mengakhiri panggilan.');

    try {
      await _room.disconnect();
    } catch (e) {
      _debugLog('Error disconnecting room: $e');
    }

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  Future<void> _cleanup() async {
    _room.removeListener(_onRoomChanged);

    try {
      await _room.disconnect();
      await _room.dispose();
    } catch (e) {
      _debugLog('Cleanup error: $e');
    }

    _liveKitService.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_cleanup());
    super.dispose();
  }

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
