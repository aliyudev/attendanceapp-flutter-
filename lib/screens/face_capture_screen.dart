import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/face_service.dart';
import '../services/supabase_service.dart';

class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({super.key});

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  CameraController? _controller;
  bool _busy = false;

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

  Future<void> _captureAndVerify() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final xfile = await ctrl.takePicture();
      final bytes = await File(xfile.path).readAsBytes();
      final email = SupabaseService.instance.currentUser?.email ?? '';
      if (email.isEmpty) {
        _show('Not authenticated');
        return;
      }
      final result = await FaceService().verifyFace(imageBytes: bytes, email: email);
      if (!result.success) {
        _show(result.message ?? 'Face not verified');
        return;
      }
      final nowUtc = DateTime.now().toUtc();
      await SupabaseService.instance.recordAttendance(clockInTimeUtc: nowUtc);
      _show('Face clock-in recorded at ${DateFormat.Hm().format(nowUtc.toLocal())}');
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      _show('Verification failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Clock-in')),
      body: Column(
        children: [
          Expanded(
            child: _controller?.value.isInitialized == true
                ? CameraPreview(_controller!)
                : const Center(child: CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _captureAndVerify,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Capture & Verify'),
              ),
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
