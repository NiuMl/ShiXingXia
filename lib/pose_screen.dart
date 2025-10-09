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
  bool _showCalibrator = false;

  final ValueNotifier<List<Map<String, dynamic>>> _keyPoints =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  final PoseClassifier _poseClassifier = PoseClassifier(logEveryXFrames: 1);

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _poseClassifier.loadModel();
    setState(() {
      _isModelLoading = false;
    });
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
            icon: Icon(_showCalibrator ? Icons.tune : Icons.tune_outlined),
            onPressed: () {
              setState(() {
                _showCalibrator = !_showCalibrator;
              });
            },
            tooltip: 'Calibrate Sensitivity',
          ),
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
          
          // Confidence visualization (bottom left)
          Positioned(
            bottom: 32,
            left: 16,
            child: Container(
              width: 160,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Confidence',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Down confidence
                  ValueListenableBuilder<double>(
                    valueListenable: _poseClassifier.downConfidence,
                    builder: (context, downConf, _) {
                      return ValueListenableBuilder<double>(
                        valueListenable: _poseClassifier.enterThreshold,
                        builder: (context, enterThresh, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '↓ DOWN',
                                    style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    downConf.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: (downConf / 10).clamp(0.0, 1.0),
                                      backgroundColor: Colors.white24,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        downConf >= enterThresh
                                            ? Colors.greenAccent
                                            : Colors.orangeAccent,
                                      ),
                                      minHeight: 8,
                                    ),
                                  ),
                                  // Threshold indicator
                                  Positioned(
                                    left: (enterThresh / 10 * 136).clamp(0.0, 136.0),
                                    child: Container(
                                      width: 2,
                                      height: 8,
                                      color: Colors.white.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Up confidence
                  ValueListenableBuilder<double>(
                    valueListenable: _poseClassifier.upConfidence,
                    builder: (context, upConf, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '↑ UP',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                upConf.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (upConf / 10).clamp(0.0, 1.0),
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.greenAccent,
                              ),
                              minHeight: 8,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // Calibrator panel
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            right: _showCalibrator ? 0 : -320,
            top: 0,
            bottom: 0,
            width: 300,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(-5, 0),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Calibration',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Adjust thresholds for counting',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Enter threshold
                      ValueListenableBuilder<double>(
                        valueListenable: _poseClassifier.enterThreshold,
                        builder: (context, threshold, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Enter Threshold',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Go down',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orangeAccent.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      threshold.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: Colors.orangeAccent,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.orangeAccent,
                                  overlayColor: Colors.orangeAccent.withOpacity(0.2),
                                ),
                                child: Slider(
                                  value: threshold,
                                  min: 1.0,
                                  max: 9.5,
                                  divisions: 17,
                                  onChanged: (value) {
                                    _poseClassifier.adjustEnterThreshold(value);
                                  },
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Easy (1.0)',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    'Hard (9.5)',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Exit threshold
                      ValueListenableBuilder<double>(
                        valueListenable: _poseClassifier.exitThreshold,
                        builder: (context, threshold, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Exit Threshold',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Push up',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      threshold.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: Colors.greenAccent,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.greenAccent,
                                  overlayColor: Colors.greenAccent.withOpacity(0.2),
                                ),
                                child: Slider(
                                  value: threshold,
                                  min: 0.5,
                                  max: 9.0,
                                  divisions: 17,
                                  onChanged: (value) {
                                    _poseClassifier.adjustExitThreshold(value);
                                  },
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Fast (0.5)',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    'Slow (9.0)',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      
                      const SizedBox(height: 24),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 16),
                      
                      // Elbow angle feedback
                      const Text(
                        'Form Feedback',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      ValueListenableBuilder<double>(
                        valueListenable: _poseClassifier.currentElbowAngle,
                        builder: (context, angle, _) {
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Elbow Angle',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '${angle.toStringAsFixed(0)}°',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (angle / 180).clamp(0.0, 1.0),
                                    backgroundColor: Colors.white24,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      angle < 90 
                                          ? Colors.greenAccent 
                                          : angle < 140 
                                              ? Colors.orangeAccent 
                                              : Colors.redAccent,
                                    ),
                                    minHeight: 8,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Quick presets
                      const Text(
                        'Quick Presets',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      _PresetButton(
                        label: 'Beginner',
                        description: 'Enter: 4.0 | Exit: 2.0',
                        onTap: () {
                          _poseClassifier.adjustEnterThreshold(4.0);
                          _poseClassifier.adjustExitThreshold(2.0);
                        },
                      ),
                      const SizedBox(height: 8),
                      _PresetButton(
                        label: 'Normal',
                        description: 'Enter: 6.0 | Exit: 4.0',
                        onTap: () {
                          _poseClassifier.adjustEnterThreshold(6.0);
                          _poseClassifier.adjustExitThreshold(4.0);
                        },
                      ),
                      const SizedBox(height: 8),
                      _PresetButton(
                        label: 'Strict',
                        description: 'Enter: 7.5 | Exit: 5.5',
                        onTap: () {
                          _poseClassifier.adjustEnterThreshold(7.5);
                          _poseClassifier.adjustExitThreshold(5.5);
                        },
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Help section
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.3),
                          ),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.lightBlueAccent,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'How it works',
                                  style: TextStyle(
                                    color: Colors.lightBlueAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              '• Enter: Must exceed to enter DOWN\n'
                              '• Exit: Must drop below to count rep\n'
                              '• Larger gap = more stable counting',
                              style: TextStyle(
                                color: Colors.lightBlue,
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Current pose indicator (bottom right)
          Positioned(
            bottom: 32,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: _poseClassifier.currentPose,
                builder: (context, pose, _) {
                  final isDown = pose == 'pushups_down';
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDown ? Icons.arrow_downward : Icons.arrow_upward,
                        color: isDown ? Colors.orangeAccent : Colors.greenAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isDown ? 'DOWN' : 'UP',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDown ? Colors.orangeAccent : Colors.greenAccent,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final String description;
  final VoidCallback onTap;

  const _PresetButton({
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}