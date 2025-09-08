import 'dart:io';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/face_service.dart';
import '../services/supabase_service.dart';

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
    setState(() { _busy = true; _captured = true; _message = 'Capturing...'; });
    try {
      final xfile = await ctrl.takePicture();
      final bytes = await File(xfile.path).readAsBytes();
      final email = SupabaseService.instance.currentUser?.email ?? '';
      if (email.isEmpty) {
        _show('Not authenticated');
        Navigator.of(context).pop(false);
        return;
      }
      setState(() => _message = 'Verifying identity...');
      final face = FaceService();
      // Optional: quality check
      final processed = await face.processFace(imageBytes: bytes, liveness: false);
      if (!(processed.faceDetected)) {
        throw 'No face detected. Ensure your face is clearly visible.';
      }
      if ((processed.qualityScore ?? 0.0) < 0.3) {
        throw 'Face quality too low. Improve lighting and try again.';
      }
      final result = await face.verifyFace(imageBytes: bytes, email: email);
      if (result.success && (result.matched ?? true)) {
        setState(() => _message = 'Face verified successfully!');
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        throw result.message ?? 'Face verification failed';
      }
    } catch (e) {
      _show(e.toString());
      if (mounted) {
        setState(() { _busy = false; _captured = false; _message = 'Position your face in the guide'; });
      }
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
