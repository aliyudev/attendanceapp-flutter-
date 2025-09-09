import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/api.dart';

class FaceService {
  final Dio _dio = Dio(BaseOptions(baseUrl: ApiConfig.faceServiceBaseUrl, connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30)));

  FaceService() {
    // Enable basic logging to confirm traffic to the face-processing service
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestBody: true,
      responseBody: true,
      responseHeader: false,
      error: true,
      requestHeader: false,
    ));
  }

  // Verify: call the face processing endpoint to get an embedding.
  // The Flask service does not implement /verify; instead we use /process-face.
  // We treat detection as success; matched/confidence are left null for now.
  Future<FaceVerifyResult> verifyFace({required Uint8List imageBytes, required String email}) async {
    try {
      final b64 = base64Encode(imageBytes);
      final resp = await _dio.post(
        '/process-face',
        data: {
          'imageData': b64,
          'returnFaceImage': false,
        },
      );
      final data = resp.data as Map<String, dynamic>;
      final faceDetected = data['face_detected'] == true;
      return FaceVerifyResult(
        success: faceDetected,
        message: faceDetected ? 'Face captured' : (data['error']?.toString() ?? 'No face detected'),
        matched: null,
        confidence: null,
        templateId: null,
        userId: null,
        score: null,
      );
    } catch (e) {
      return FaceVerifyResult(success: false, message: 'Face verification failed: $e');
    }
  }

  // Process a face image to generate an embedding and quality report
  Future<FaceProcessResult> processFace({required Uint8List imageBytes, required bool liveness}) async {
    try {
      final b64 = base64Encode(imageBytes);
      final resp = await _dio.post(
        '/process-face',
        data: {
          'imageData': b64,
          'returnFaceImage': false,
        },
      );
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

  // Register a face embedding to a user id via the same /process-face endpoint (mock)
  Future<bool> registerFace({required List<double> embedding, required String userId}) async {
    try {
      final resp = await _dio.post(
        '/process-face',
        data: {
          'action': 'register',
          'userId': userId,
          'embedding': embedding,
        },
      );
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
  final List<int>? bbox; // [x, y, w, h]
  final List<int>? imageSize; // [w, h]
  final List<double>? centerOffset; // [dx, dy] normalized offsets
  final double? boxRatio; // face box area / image area
  FaceProcessResult({
    required this.faceDetected,
    this.qualityScore,
    this.embedding = const [],
    this.message,
    this.bbox,
    this.imageSize,
    this.centerOffset,
    this.boxRatio,
  });
}
