import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/services.dart';   // DeviceOrientation
import 'pose_painter_mlkit.dart';
import 'package:collection/collection.dart'; // firstWhereOrNull

class PoseScreen extends StatefulWidget {
  const PoseScreen({super.key});

  @override
  State<PoseScreen> createState() => _PoseScreenState();
}

class _PoseScreenState extends State<PoseScreen> {
  CameraController? _controller;
  late final PoseDetector _detector = PoseDetector(options: PoseDetectorOptions());
  bool _isDetecting = false;
  List<Map<String, dynamic>> _keyPoints = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final front = cameras.firstWhereOrNull(
        (c) => c.lensDirection == CameraLensDirection.front);

    _controller = CameraController(
      front ?? cameras.first,
      ResolutionPreset.medium,          // ← more pixels → wider field
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

      final List<Map<String, dynamic>> list = [];
      for (final lm in poses.first.landmarks.values) {
        list.add({
          'label': lm.type.name,
          'x': lm.x,   // keep raw pixels
          'y': lm.y,
          'confidence': lm.likelihood,
        });
      }


      setState(() => _keyPoints = list);
    } catch (e) {
      debugPrint('pose error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _controller!.description;
    final sensor = camera.sensorOrientation;

    // map Flutter orientation → degrees
    final orientations = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    int rotationCompensation = orientations[_controller!.value.deviceOrientation] ?? 0;

    if (Platform.isAndroid) {
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensor + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensor - rotationCompensation + 360) % 360;
      }
    } else {
      rotationCompensation = sensor;
    }

    final rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Pose Tracking')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Camera preview dimensions (note: width and height are swapped for portrait orientation)
          final previewW = _controller!.value.previewSize!.height;
          final previewH = _controller!.value.previewSize!.width;
          
          // Container dimensions
          final boxW = constraints.maxWidth;
          final boxH = constraints.maxHeight;

          // Calculate scale factor for BoxFit.cover
          // (takes the larger scale to ensure full coverage)
          final scaleX = boxW / previewW;
          final scaleY = boxH / previewH;
          final scale = scaleX > scaleY ? scaleX : scaleY;
          
          // Calculate the actual painted dimensions
          final paintedW = previewW * scale;
          final paintedH = previewH * scale;
          
          // Calculate offsets for centering the cropped preview
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
                child: CustomPaint(
                  size: Size(paintedW, paintedH),
                  painter: PosePainterMlKit(
                    _keyPoints,
                    _controller!.description.lensDirection,
                    imageWidth: previewW,
                    imageHeight: previewH,
                  ),
                ),
              ),
            ],
          );

        },
      ),
    );
  }
}