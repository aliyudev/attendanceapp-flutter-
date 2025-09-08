import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/api.dart';

class FaceService {
  final Dio _dio = Dio(BaseOptions(baseUrl: ApiConfig.faceServiceBaseUrl, connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30)));

  // Verify by sending an image and email (simple flow)
  Future<FaceVerifyResult> verifyFace({required Uint8List imageBytes, required String email}) async {
    try {
      final formData = FormData.fromMap({
        'email': email,
        'image': MultipartFile.fromBytes(
          imageBytes,
          filename: 'capture.jpg',
        ),
      });
      final resp = await _dio.post('/verify', data: formData);
      final data = resp.data as Map<String, dynamic>;
      return FaceVerifyResult(
        success: data['success'] == true,
        score: (data['score'] as num?)?.toDouble(),
        message: data['message']?.toString(),
        matched: data['matched'] == true,
        confidence: (data['confidence'] as num?)?.toDouble(),
        templateId: data['template_id']?.toString(),
        userId: data['user_id']?.toString(),
      );
    } catch (e) {
      return FaceVerifyResult(success: false, message: 'Face verification failed: $e');
    }
  }

  // Process a face image to generate an embedding and quality report
  Future<FaceProcessResult> processFace({required Uint8List imageBytes, required bool liveness}) async {
    try {
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(imageBytes, filename: 'capture.jpg'),
        'liveness': liveness,
      });
      final resp = await _dio.post('/process', data: formData);
      final data = resp.data as Map<String, dynamic>;
      return FaceProcessResult(
        faceDetected: data['face_detected'] == true,
        qualityScore: (data['quality_score'] as num?)?.toDouble(),
        embedding: (data['embedding'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? const [],
      );
    } catch (e) {
      return FaceProcessResult(faceDetected: false, message: 'Face processing failed: $e');
    }
  }

  // Register a face embedding to a user id
  Future<bool> registerFace({required List<double> embedding, required String userId}) async {
    try {
      final resp = await _dio.post('/register', data: {
        'user_id': userId,
        'embedding': embedding,
      });
      final data = resp.data as Map<String, dynamic>;
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }
}

class FaceVerifyResult {
  final bool success;
  final bool? matched;
  final double? score; // legacy
  final String? message;
  final double? confidence;
  final String? templateId;
  final String? userId;
  FaceVerifyResult({
    required this.success,
    this.matched,
    this.score,
    this.message,
    this.confidence,
    this.templateId,
    this.userId,
  });
}

class FaceProcessResult {
  final bool faceDetected;
  final double? qualityScore;
  final List<double> embedding;
  final String? message;
  FaceProcessResult({required this.faceDetected, this.qualityScore, this.embedding = const [], this.message});
}
