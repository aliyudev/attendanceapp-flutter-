import 'dart:io';
import 'dart:async';

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
  bool _processingStep = false; // whether we are auto-capturing frames for current step

  final List<String> _steps = const ['front', 'left', 'right', 'smile'];
  int _stepIndex = 0;
  // Accumulate embeddings per step; we will take the last good embedding for the step
  final Map<String, List<double>> _stepEmbeddings = { 'front': [], 'left': [], 'right': [], 'smile': [] };

  // Progress/quality gating
  double _progress = 0.0; // 0..1 for current step
  int _goodStreak = 0; // consecutive good frames
  final int _targetGoodStreak = 3; // require N consecutive good frames to accept a step
  final double _qualityThreshold = 0.35; // minimum quality per frame
  bool _captureInFlight = false; // guard re-entrancy
  bool _disposed = false;

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
      if (mounted) {
        setState(() {});
        // Auto-start processing for the first step
        // Delay slightly to ensure preview is shown
        // and avoid re-entrancy during build
        unawaited(Future.delayed(const Duration(milliseconds: 200), () async {
          if (mounted && !_processingStep) {
            await _startStepProcessing();
          }
        }));
      }
    } catch (e) {
      _show('Camera init failed: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _disposed = true;
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

  Future<void> _startStepProcessing() async {
    if (_processingStep) return;
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _processingStep = true;
      _progress = 0.0;
      _goodStreak = 0;
    });
    // Process frames sequentially in a loop until criteria met or widget disposed
    while (!_disposed && _processingStep) {
      await _processOneFrame();
      if (_goodStreak >= _targetGoodStreak) {
        // Accept step
        setState(() {
          _processingStep = false;
        });
        if (_stepIndex < _steps.length - 1) {
          setState(() {
            _stepIndex++;
            _progress = 0.0;
            _goodStreak = 0;
          });
          // auto-start next step for smoother UX
          // Give user a brief moment to reposition
          await Future.delayed(const Duration(milliseconds: 600));
          // Start next step automatically
          if (mounted) {
            // Continue to next step
            await _startStepProcessing();
          }
        } else {
          // All steps done -> register
          await _processAndRegister();
        }
        break;
      }
      // Pace the loop a bit to avoid hammering the camera/service
      await Future.delayed(const Duration(milliseconds: 700));
    }
  }

  Future<void> _processOneFrame() async {
    if (_captureInFlight) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    _captureInFlight = true;
    try {
      final xfile = await ctrl.takePicture();
      final bytes = await File(xfile.path).readAsBytes();
      final face = FaceService();
      final processed = await face.processFace(imageBytes: bytes, liveness: false);
      if (!processed.faceDetected) {
        // reset streak if no face
        setState(() {
          _goodStreak = 0;
          _progress = 0.0;
        });
        return;
      }
      final quality = processed.qualityScore ?? 0.0;
      if (quality >= _qualityThreshold && processed.embedding.isNotEmpty) {
        _goodStreak += 1;
        _stepEmbeddings[_steps[_stepIndex]] = processed.embedding; // keep last good embedding
      } else {
        _goodStreak = 0; // fail quality -> reset streak
      }
      setState(() {
        _progress = (_goodStreak / _targetGoodStreak).clamp(0.0, 1.0);
      });
    } catch (e) {
      // transient errors: do not break the loop, but notify lightweight
      // Optionally show toast once
    } finally {
      _captureInFlight = false;
    }
  }

  Future<void> _processAndRegister() async {
    try {
      setState(() => _busy = true);
      // Ensure each step has a captured good embedding
      final embeddings = <List<double>>[];
      for (final key in _steps) {
        final emb = _stepEmbeddings[key] ?? [];
        if (emb.isEmpty) {
          throw 'Step "$key" did not reach sufficient quality. Please try again.';
        }
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
      final face = FaceService();
      await face.registerFace(embedding: avg, userId: userId);
      // Persist embedding to Supabase for real verification later
      await SupabaseService.instance.saveFaceEmbedding(avg);
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
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 260,
                            height: 260,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(130),
                              border: Border.all(color: Colors.white.withOpacity(0.5), width: 3, style: BorderStyle.solid),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            height: 220,
                            child: CircularProgressIndicator(
                              value: _processingStep ? _progress : 0,
                              strokeWidth: 8,
                              color: const Color(0xFFdc2626),
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ],
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
                    onPressed: null,
                    child: Text(_processingStep ? 'Processing...' : 'Preparing...'),
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
