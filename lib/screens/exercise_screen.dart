import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import '../models/exercise_config.dart';
import '../classifiers/base_exercise_classifier.dart';
import '../classifiers/exercise_classifier_factory.dart';
import '../widgets/pose_painter_mlkit.dart';
import '../services/time_tracking_service.dart';

class ExerciseScreen extends StatefulWidget {
  final ExerciseConfig exerciseConfig;

  const ExerciseScreen({
    super.key,
    required this.exerciseConfig,
  });

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  CameraController? _controller;
  late final PoseDetector _detector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream));
  bool _isDetecting = false;
  bool _isModelLoading = true;
  bool _showCalibrator = false;

  final ValueNotifier<List<Map<String, dynamic>>> _keyPoints =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  late final BaseExerciseClassifier _classifier;

  @override
  void initState() {
    super.initState();
    _classifier = ExerciseClassifierFactory.createClassifier(
      widget.exerciseConfig,
      logEveryXFrames: 1,
    );
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _classifier.loadModel();
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

      await _classifier.processAndClassify(poses.first);

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
        rotationCompensation = (sensor - rotationCompensation + 360) % 360;
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
    _classifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isModelLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.exerciseConfig.displayName}计数器')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载 KNN 模型...'),
            ],
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.exerciseConfig.displayName}计数器')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        // Award earned minutes when user navigates back
        final repCount = _classifier.repetitionCounter.value;
        if (repCount > 0) {
          await TimeTrackingService().addEarnedMinutes(repCount);
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.exerciseConfig.displayName}计数器'),
          actions: [
          IconButton(
            icon: Icon(_showCalibrator ? Icons.tune : Icons.tune_outlined),
            onPressed: () {
              setState(() {
                _showCalibrator = !_showCalibrator;
              });
            },
            tooltip: '校准灵敏度',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _classifier.resetCounter();
            },
            tooltip: '重置计数',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: _classifier.repetitionCounter,
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
                    Text(
                      widget.exerciseConfig.displayName,
                      style: const TextStyle(
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
                    '置信度',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Down confidence
                  ValueListenableBuilder<double>(
                    valueListenable: _classifier.downConfidence,
                    builder: (context, downConf, _) {
                      return ValueListenableBuilder<double>(
                        valueListenable: _classifier.enterThreshold,
                        builder: (context, enterThresh, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '↓ ${widget.exerciseConfig.enterStateLabel}',
                                    style: TextStyle(
                                      color: widget.exerciseConfig.primaryColor,
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
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        downConf >= enterThresh
                                            ? widget.exerciseConfig.secondaryColor
                                            : widget.exerciseConfig.primaryColor,
                                      ),
                                      minHeight: 8,
                                    ),
                                  ),
                                  // Threshold indicator
                                  Positioned(
                                    left: (enterThresh / 10 * 136)
                                        .clamp(0.0, 136.0),
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
                    valueListenable: _classifier.upConfidence,
                    builder: (context, upConf, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '↑ ${widget.exerciseConfig.exitStateLabel}',
                                style: TextStyle(
                                  color: widget.exerciseConfig.secondaryColor,
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                widget.exerciseConfig.secondaryColor,
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
                        '校准',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '调整计数阈值',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Enter threshold
                      ValueListenableBuilder<double>(
                        valueListenable: _classifier.enterThreshold,
                        builder: (context, threshold, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '进入阈值',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '进入${widget.exerciseConfig.enterStateLabel}',
                                        style: const TextStyle(
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
                                      color: widget.exerciseConfig.primaryColor
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      threshold.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: widget.exerciseConfig.primaryColor,
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
                                  activeTrackColor:
                                      widget.exerciseConfig.primaryColor,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: widget.exerciseConfig.primaryColor,
                                  overlayColor: widget.exerciseConfig.primaryColor
                                      .withOpacity(0.2),
                                ),
                                child: Slider(
                                  value: threshold,
                                  min: 1.0,
                                  max: 9.5,
                                  divisions: 17,
                                  onChanged: (value) {
                                    _classifier.adjustEnterThreshold(value);
                                  },
                                ),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '简单 (1.0)',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    '困难 (9.5)',
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
                        valueListenable: _classifier.exitThreshold,
                        builder: (context, threshold, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '退出阈值',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '退出${widget.exerciseConfig.exitStateLabel}',
                                        style: const TextStyle(
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
                                      color: widget.exerciseConfig.secondaryColor
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      threshold.toStringAsFixed(1),
                                      style: TextStyle(
                                        color:
                                            widget.exerciseConfig.secondaryColor,
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
                                  activeTrackColor:
                                      widget.exerciseConfig.secondaryColor,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor:
                                      widget.exerciseConfig.secondaryColor,
                                  overlayColor: widget
                                      .exerciseConfig.secondaryColor
                                      .withOpacity(0.2),
                                ),
                                child: Slider(
                                  value: threshold,
                                  min: 0.5,
                                  max: 9.0,
                                  divisions: 17,
                                  onChanged: (value) {
                                    _classifier.adjustExitThreshold(value);
                                  },
                                ),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '快速 (0.5)',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    '缓慢 (9.0)',
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
                        '姿势反馈',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),

                      ValueListenableBuilder<double>(
                        valueListenable: _classifier.currentElbowAngle,
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      '手肘角度',
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
                        '快速预设',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _PresetButton(
                        label: '初级',
                        description: '进入：4.0 | 退出：2.0',
                        onTap: () {
                          _classifier.adjustEnterThreshold(4.0);
                          _classifier.adjustExitThreshold(2.0);
                        },
                      ),
                      const SizedBox(height: 8),
                      _PresetButton(
                        label: '标准',
                        description: '进入：6.0 | 退出：4.0',
                        onTap: () {
                          _classifier.adjustEnterThreshold(6.0);
                          _classifier.adjustExitThreshold(4.0);
                        },
                      ),
                      const SizedBox(height: 8),
                      _PresetButton(
                        label: '严格',
                        description: '进入：7.5 | 退出：5.5',
                        onTap: () {
                          _classifier.adjustEnterThreshold(7.5);
                          _classifier.adjustExitThreshold(5.5);
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
                                  '工作原理',
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
                              '• 进入：需超过此值才能进入目标姿势\n'
                              '• 退出：需低于此值才算完成一次\n'
                              '• 间隔越大，计数越稳定',
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
                valueListenable: _classifier.currentPose,
                builder: (context, pose, _) {
                  final isDown = pose == '${widget.exerciseConfig.name}_down';
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDown ? Icons.arrow_downward : Icons.arrow_upward,
                        color: isDown
                            ? widget.exerciseConfig.primaryColor
                            : widget.exerciseConfig.secondaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isDown
                            ? widget.exerciseConfig.enterStateLabel
                            : widget.exerciseConfig.exitStateLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDown
                              ? widget.exerciseConfig.primaryColor
                              : widget.exerciseConfig.secondaryColor,
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
