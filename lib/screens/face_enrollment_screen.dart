import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/face_service.dart';
import '../services/supabase_service.dart';

class FaceEnrollmentScreen extends StatefulWidget {
  const FaceEnrollmentScreen({super.key});

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  CameraController? _controller;
  bool _busy = false;

  final List<String> _steps = const ['front', 'left', 'right', 'smile'];
  int _stepIndex = 0;
  final Map<String, XFile?> _captures = { 'front': null, 'left': null, 'right': null, 'smile': null };

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
    _controller?.dispose();
    super.dispose();
  }

  String get _instruction {
    switch (_steps[_stepIndex]) {
      case 'front':
        return 'Look straight at the camera';
      case 'left':
        return 'Turn your head to the left';
      case 'right':
        return 'Turn your head to the right';
      case 'smile':
        return 'Smile naturally';
      default:
        return 'Position your face as instructed';
    }
  }

  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final shot = await ctrl.takePicture();
      _captures[_steps[_stepIndex]] = shot;
      if (_stepIndex < _steps.length - 1) {
        setState(() => _stepIndex++);
      } else {
        await _processAndRegister();
      }
    } catch (e) {
      _show('Capture failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _processAndRegister() async {
    try {
      setState(() => _busy = true);
      // Process each capture to embedding via face service
      final face = FaceService();
      final embeddings = <List<double>>[];
      for (final key in _steps) {
        final xf = _captures[key];
        if (xf == null) throw 'Missing capture for $key';
        final bytes = await File(xf.path).readAsBytes();
        final processed = await face.processFace(imageBytes: bytes, liveness: false);
        if (!processed.faceDetected) {
          throw 'No face detected in $key capture';
        }
        if ((processed.qualityScore ?? 1.0) < 0.3) {
          throw '$key capture quality too low. Try again.';
        }
        final emb = processed.embedding;
        if (emb.isEmpty) throw 'No embedding returned for $key';
        embeddings.add(emb);
      }
      // Average embeddings
      final length = embeddings.first.length;
      final sum = List<double>.filled(length, 0);
      for (final emb in embeddings) {
        for (var i = 0; i < length; i++) sum[i] += emb[i];
      }
      final avg = [for (var i = 0; i < length; i++) sum[i] / embeddings.length];

      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) throw 'Not authenticated';
      await face.registerFace(embedding: avg, userId: userId);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Success'),
          content: const Text('Face registered successfully.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _show('Registration failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Registration')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Column(
              children: [
                Text(_instruction, style: const TextStyle(fontSize: 16, color: Color(0xFF666666))),
                Text('Step ${_stepIndex + 1} of ${_steps.length}', style: const TextStyle(fontSize: 14, color: Color(0xFFdc2626), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_controller?.value.isInitialized == true)
                  CameraPreview(_controller!)
                else
                  const Center(child: CircularProgressIndicator()),
                // circular face guide overlay
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(130),
                          border: Border.all(color: Colors.white.withOpacity(0.5), width: 3, style: BorderStyle.solid),
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
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF4b5563), fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _capture,
                    child: Text(_stepIndex < _steps.length - 1 ? 'Capture' : 'Finish'),
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
