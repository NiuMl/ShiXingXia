import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/services.dart';
import 'pose_painter_mlkit.dart';
import 'package:collection/collection.dart';
import 'pose_classifier.dart';

class PoseScreen extends StatefulWidget {
  const PoseScreen({super.key});

  @override
  State<PoseScreen> createState() => _PoseScreenState();
}

class _PoseScreenState extends State<PoseScreen> {
  CameraController? _controller;
  late final PoseDetector _detector =
      PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream));
  bool _isDetecting = false;
  bool _isModelLoading = true;

  final ValueNotifier<List<Map<String, dynamic>>> _keyPoints =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  final PoseClassifier _poseClassifier = PoseClassifier(logEveryXFrames: 15);

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Load KNN model first
    await _poseClassifier.loadModel();
    setState(() {
      _isModelLoading = false;
    });
    
    // Then initialize camera
    await _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final front = cameras.firstWhereOrNull(
        (c) => c.lensDirection == CameraLensDirection.front);

    _controller = CameraController(
      front ?? cameras.first,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});
    _controller!.startImageStream(_process);
  }

  Future<void> _process(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final input = _toInputImage(image);
      if (input == null) {
        _isDetecting = false;
        return;
      }

      final poses = await _detector.processImage(input);
      if (poses.isEmpty) {
        _isDetecting = false;
        return;
      }

      // 🧠 Classify pose using KNN
      await _poseClassifier.processAndClassify(poses.first);

      final List<Map<String, dynamic>> list = [];
      for (final lm in poses.first.landmarks.values) {
        list.add({
          'label': lm.type.name,
          'x': lm.x,
          'y': lm.y,
          'confidence': lm.likelihood,
        });
      }

      _keyPoints.value = list;
    } catch (e) {
      debugPrint('pose error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _controller!.description;
    final sensor = camera.sensorOrientation;

    final orientations = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    int rotationCompensation =
        orientations[_controller!.value.deviceOrientation] ?? 0;

    if (Platform.isAndroid) {
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensor + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensor - rotationCompensation + 360) % 360;
      }
    } else {
      rotationCompensation = sensor;
    }

    final rotation =
        InputImageRotationValue.fromRawValue(rotationCompensation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detector.close();
    _keyPoints.dispose();
    _poseClassifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isModelLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pushup Counter')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading KNN model...'),
            ],
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pushup Counter')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pushup Counter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _poseClassifier.resetCounter();
            },
            tooltip: 'Reset Counter',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview with pose overlay
          LayoutBuilder(
            builder: (context, constraints) {
              final previewW = _controller!.value.previewSize!.height;
              final previewH = _controller!.value.previewSize!.width;

              final boxW = constraints.maxWidth;
              final boxH = constraints.maxHeight;

              final scaleX = boxW / previewW;
              final scaleY = boxH / previewH;
              final scale = scaleX > scaleY ? scaleX : scaleY;

              final paintedW = previewW * scale;
              final paintedH = previewH * scale;

              final offsetX = (paintedW - boxW) / 2;
              final offsetY = (paintedH - boxH) / 2;

              return Stack(
                children: [
                  SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: previewW,
                        height: previewH,
                        child: CameraPreview(_controller!),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -offsetX,
                    top: -offsetY,
                    child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                      valueListenable: _keyPoints,
                      builder: (context, points, _) {
                        return CustomPaint(
                          size: Size(paintedW, paintedH),
                          painter: PosePainterMlKit(
                            points,
                            _controller!.description.lensDirection,
                            imageWidth: previewW,
                            imageHeight: previewH,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          
          // Stats overlay
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: _poseClassifier.pushupCounter,
                      builder: (context, count, _) {
                        return Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                    const Text(
                      'PUSHUPS',
                      style: TextStyle(
                        fontSize: 18,
                        letterSpacing: 2,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Current pose indicator
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: _poseClassifier.currentPose,
                      builder: (context, pose, _) {
                        final isUp = pose == 'pushups_up';
                        final isDown = pose == 'pushups_down';
                        return Row(
                          children: [
                            Icon(
                              isUp ? Icons.arrow_upward : 
                              isDown ? Icons.arrow_downward : 
                              Icons.help_outline,
                              color: isUp ? Colors.greenAccent : 
                                     isDown ? Colors.orangeAccent : 
                                     Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              pose == 'pushups_up' ? 'UP' :
                              pose == 'pushups_down' ? 'DOWN' :
                              pose.toUpperCase(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isUp ? Colors.greenAccent : 
                                       isDown ? Colors.orangeAccent : 
                                       Colors.white70,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    ValueListenableBuilder<double>(
                      valueListenable: _poseClassifier.confidence,
                      builder: (context, conf, _) {
                        return Text(
                          '${(conf * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}