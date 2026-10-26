import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LiveKitService {
  LiveKitService({FirebaseAuth? auth, http.Client? client, String? baseUrl})
    : _auth = auth ?? FirebaseAuth.instance,
      _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _defaultBaseUrl;

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _baseUrl;

  // Chrome/Desktop: localhost mengarah ke komputer tempat backend berjalan.
  // Android fisik: gunakan IP LAN komputer, misalnya http://192.168.1.10:3000.
  static String get _defaultBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }

    // Ganti dengan IP LAN komputer Anda sebelum menguji di HP Android.
    return 'http://192.168.96.116:3000';
  }

  /// Meminta token LiveKit menggunakan identitas Firebase yang login.
  Future<Map<String, dynamic>> getCallToken({required String roomName}) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Silakan login terlebih dahulu.');
    }

    final firebaseIdToken = await user.getIdToken();

    if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
      throw Exception('Firebase ID token tidak tersedia.');
    }

    final uri = Uri.parse('$_baseUrl/api/livekit/token');

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $firebaseIdToken',
          },
          body: jsonEncode({'roomName': roomName}),
        )
        .timeout(const Duration(seconds: 20));

    final Map<String, dynamic> data;

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid response format.');
      }

      data = decoded;
    } on FormatException {
      throw Exception(
        'Backend memberikan respons yang tidak valid '
        '(HTTP ${response.statusCode}).',
      );
    }

    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(
        data['message']?.toString() ??
            'Gagal memperoleh token LiveKit '
                '(HTTP ${response.statusCode}).',
      );
    }

    final serverUrl = data['serverUrl'];
    final token = data['token'];
    final returnedRoom = data['roomName'];
    final identity = data['identity'];

    if (serverUrl is! String ||
        token is! String ||
        returnedRoom != roomName ||
        identity != user.uid) {
      throw Exception('Respons token LiveKit tidak sesuai.');
    }

    // Jangan mencetak token atau Firebase ID token ke log.
    debugPrint('LiveKit token berhasil diperoleh.');
    debugPrint('Room: $returnedRoom');
    debugPrint('Identity cocok dengan pengguna Firebase.');

    return {
      'serverUrl': serverUrl,
      'token': token,
      'roomName': returnedRoom,
      'identity': identity,
    };
  }

  void dispose() {
    _client.close();
  }
}
