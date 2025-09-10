import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/face_service.dart';
import '../services/supabase_service.dart';
import '../config/constants.dart';

class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({super.key});

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  CameraController? _controller;
  bool _busy = false;
  String _message = 'Position your face in the guide';
  bool _captured = false;
  Timer? _stabilityTimer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    final n = a.length;
    if (b.length != n || n == 0) return 0.0;
    double dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < n; i++) {
      final x = a[i];
      final y = b[i];
      dot += x * y;
      na += x * x;
      nb += y * y;
    }
    if (na == 0 || nb == 0) return 0.0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      _controller = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      _show('Camera init failed: $e');
    }
  }

  @override
  void dispose() {
    _stabilityTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndVerify() async {
    if (_busy || _captured) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    setState(() { _busy = true; _captured = true; _message = 'Starting liveness check...'; });
    try {
      // Ensure logged in
      final email = SupabaseService.instance.currentUser?.email ?? '';
      if (email.isEmpty) {
        _show('Not authenticated');
        Navigator.of(context).pop(false);
        return;
      }

      final face = FaceService();

      // Step 1: Ask for LEFT head turn
      setState(() => _message = 'Liveness: Turn your head LEFT');
      await Future.delayed(const Duration(milliseconds: 400));
      final leftFrame = await _captureAndProcess(face);
      _ensureValidFrame(leftFrame);
      final dxLeft = (leftFrame.centerOffset != null && leftFrame.centerOffset!.length >= 1) ? leftFrame.centerOffset![0] : 0.0;
      const dxThreshold = FaceConstants.livenessDxThreshold; // movement threshold
      if (!(dxLeft < -dxThreshold)) {
        throw 'Please turn your head more to the LEFT.';
      }

      // Step 2: Ask for RIGHT head turn
      setState(() => _message = 'Liveness: Turn your head RIGHT');
      await Future.delayed(const Duration(milliseconds: 400));
      final rightFrame = await _captureAndProcess(face);
      _ensureValidFrame(rightFrame);
      final dxRight = (rightFrame.centerOffset != null && rightFrame.centerOffset!.length >= 1) ? rightFrame.centerOffset![0] : 0.0;
      if (!(dxRight > dxThreshold)) {
        throw 'Please turn your head more to the RIGHT.';
      }

      // Proceed with verification using the right frame embedding (more frontal after motion is acceptable too)
      if (rightFrame.embedding.isEmpty) {
        throw 'Unable to extract face embedding from the frame. Try again.';
      }

      // Fetch stored embedding from Supabase
      final registered = await SupabaseService.instance.fetchFaceEmbedding();
      if (registered == null || registered.isEmpty) {
        throw 'No face registered for this account. Please enroll first.';
      }

      setState(() => _message = 'Verifying identity...');
      final sim = _cosineSimilarity(rightFrame.embedding, registered);
      const threshold = FaceConstants.verificationSimilarityMin;
      if (sim >= threshold) {
        setState(() => _message = 'Face verified (similarity ${(sim * 100).toStringAsFixed(1)}%).');
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        throw 'Face does not match (similarity ${(sim * 100).toStringAsFixed(1)}%).';
      }
    } catch (e) {
      _show(e.toString());
      if (mounted) {
        setState(() { _busy = false; _captured = false; _message = 'Position your face in the guide'; });
      }
    }
  }

  Future<FaceProcessResult> _captureAndProcess(FaceService face) async {
    final ctrl = _controller!;
    final xfile = await ctrl.takePicture();
    final bytes = await File(xfile.path).readAsBytes();
    return await face.processFace(imageBytes: bytes, liveness: true);
  }

  void _ensureValidFrame(FaceProcessResult processed) {
    if (!(processed.faceDetected)) {
      throw 'No face detected. Ensure your face is clearly visible.';
    }
    if ((processed.qualityScore ?? 0.0) < FaceConstants.verificationQualityMin) {
      throw 'Face quality too low. Improve lighting and try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Verification')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Text('Face Verification', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF111111))),
                const SizedBox(height: 6),
                Text(_message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Color(0xFF666666))),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_controller?.value.isInitialized == true)
                  GestureDetector(
                    onTap: () {
                      // simple stability debounce: require a short dwell before capture
                      _stabilityTimer?.cancel();
                      _stabilityTimer = Timer(const Duration(milliseconds: 400), _captureAndVerify);
                    },
                    child: CameraPreview(_controller!),
                  )
                else
                  const Center(child: CircularProgressIndicator()),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(125),
                          border: Border.all(color: const Color(0xFF4CAF50), width: 3),
                        ),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFFdc2626))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _captureAndVerify,
                    child: Text(_busy ? 'Processing...' : 'Verify'),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  void _show(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
