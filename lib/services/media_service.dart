import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class UploadedMedia {
  final String name;
  final String url;
  final String storagePath;
  final String mimeType;
  final int size;
  final String type;

  const UploadedMedia({
    required this.name,
    required this.url,
    required this.storagePath,
    required this.mimeType,
    required this.size,
    required this.type,
  });
}

class MediaService {
  MediaService({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    ImagePicker? imagePicker,
  }) : _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _imagePicker = imagePicker ?? ImagePicker();

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final ImagePicker _imagePicker;

  static const int maxImageSize = 10 * 1024 * 1024;
  static const int maxDocumentSize = 20 * 1024 * 1024;

  static const List<String> allowedImageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  static const List<String> allowedDocumentExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
  ];

  String get _currentUid {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      throw StateError('Pengguna belum login.');
    }

    return uid;
  }

  // ============================================================
  // PICK AND UPLOAD IMAGE
  // ============================================================

  Future<UploadedMedia?> pickAndUploadImage({
    required String conversationId,
    ValueChanged<double>? onProgress,
  }) async {
    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile == null) return null;

    final fileName = pickedFile.name;
    final extension = _getExtension(fileName);

    if (!allowedImageExtensions.contains(extension)) {
      throw ArgumentError('Format foto tidak didukung.');
    }

    final fileSize = await pickedFile.length();

    if (fileSize <= 0 || fileSize > maxImageSize) {
      throw ArgumentError('Ukuran foto maksimal 10 MB.');
    }

    final bytes = await pickedFile.readAsBytes();

    final mimeType = _getImageMimeType(extension);

    return _upload(
      conversationId: conversationId,
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      fileSize: fileSize,
      type: 'image',
      onProgress: onProgress,
    );
  }

  // ============================================================
  // PICK AND UPLOAD DOCUMENT
  // ============================================================

  Future<UploadedMedia?> pickAndUploadDocument({
    required String conversationId,
    ValueChanged<double>? onProgress,
  }) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedDocumentExtensions,
    );

    if (files.isEmpty) return null;

    final file = files.first;
    final fileName = file.name;
    final extension = _getExtension(fileName);

    if (!allowedDocumentExtensions.contains(extension)) {
      throw ArgumentError('Format dokumen tidak didukung.');
    }

    final fileSize = file.lengthSync() ?? await file.length();

    if (fileSize == null || fileSize <= 0) {
      throw ArgumentError('File tidak dapat dibaca.');
    }

    if (fileSize > maxDocumentSize) {
      throw ArgumentError('Ukuran dokumen maksimal 20 MB.');
    }

    final bytes = await file.readAsBytes();
    final mimeType = _getDocumentMimeType(extension);

    return _upload(
      conversationId: conversationId,
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      fileSize: fileSize,
      type: 'document',
      onProgress: onProgress,
    );
  }

  // ============================================================
  // UPLOAD TO FIREBASE STORAGE
  // ============================================================

  Future<UploadedMedia> _upload({
    required String conversationId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    required int fileSize,
    required String type,
    ValueChanged<double>? onProgress,
  }) async {
    final uid = _currentUid;

    if (conversationId.trim().isEmpty) {
      throw ArgumentError('Conversation ID tidak valid.');
    }

    final safeName = _sanitizeFileName(fileName);
    final uniqueName = '${DateTime.now().microsecondsSinceEpoch}_$safeName';

    final storagePath = 'conversations/$conversationId/$uid/$uniqueName';

    final storageRef = _storage.ref().child(storagePath);

    final metadata = SettableMetadata(
      contentType: mimeType,
      customMetadata: {
        'senderId': uid,
        'conversationId': conversationId,
        'originalFileName': fileName,
        'type': type,
      },
    );

    debugPrint('========== MEDIA UPLOAD START ==========');
    debugPrint('CONVERSATION: $conversationId');
    debugPrint('SENDER: $uid');
    debugPrint('FILE: $fileName');
    debugPrint('SIZE: $fileSize');
    debugPrint('TYPE: $type');
    debugPrint('STORAGE PATH: $storagePath');

    try {
      final uploadTask = storageRef.putData(bytes, metadata);

      await for (final snapshot in uploadTask.snapshotEvents) {
        final total = snapshot.totalBytes;

        final progress = total > 0 ? snapshot.bytesTransferred / total : 0.0;

        onProgress?.call(progress);

        debugPrint('UPLOAD PROGRESS: ${(progress * 100).toStringAsFixed(1)}%');
      }

      final downloadUrl = await storageRef.getDownloadURL();

      debugPrint('UPLOAD SUCCESS');
      debugPrint('DOWNLOAD URL: $downloadUrl');
      debugPrint('========================================');

      return UploadedMedia(
        name: fileName,
        url: downloadUrl,
        storagePath: storagePath,
        mimeType: mimeType,
        size: fileSize,
        type: type,
      );
    } catch (e, stackTrace) {
      debugPrint('UPLOAD FAILED: $e');
      debugPrint('$stackTrace');
      debugPrint('========================================');

      rethrow;
    }
  }

  // ============================================================
  // FILE HELPERS
  // ============================================================

  String _getExtension(String fileName) {
    final parts = fileName.split('.');

    if (parts.length < 2) return '';

    return parts.last.toLowerCase();
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _getImageMimeType(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        throw ArgumentError('Format foto tidak didukung.');
    }
  }

  String _getDocumentMimeType(String extension) {
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':
        return 'text/plain';
      default:
        throw ArgumentError('Format dokumen tidak didukung.');
    }
  }
}
