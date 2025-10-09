import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:ml_algo/ml_algo.dart';
import 'package:ml_dataframe/ml_dataframe.dart';

class PoseClassifier {
  int _frameCount = 0;
  final int logEveryXFrames;
  KnnClassifier? _classifier;
  bool _isModelLoaded = false;

  // MediaPipe-style repetition counter
  bool _poseEntered = false;
  int _pushupCount = 0;
  final ValueNotifier<int> pushupCounter = ValueNotifier<int>(0);
  final ValueNotifier<String> currentPose = ValueNotifier<String>('unknown');
  final ValueNotifier<double> confidence = ValueNotifier<double>(0.0);
  
  // Threshold calibration - these are confidence thresholds (not probabilities)
  final ValueNotifier<double> enterThreshold = ValueNotifier<double>(6.0);
  final ValueNotifier<double> exitThreshold = ValueNotifier<double>(4.0);
  
  // Track classification confidence for visualization
  final ValueNotifier<double> downConfidence = ValueNotifier<double>(0.0);
  final ValueNotifier<double> upConfidence = ValueNotifier<double>(0.0);
  
  // Track raw elbow angle for calibration feedback
  final ValueNotifier<double> currentElbowAngle = ValueNotifier<double>(0.0);
  
  // EMA smoothing for confidence scores
  double _smoothedDownConf = 0.0;
  double _smoothedUpConf = 0.0;
  final double _emaAlpha = 0.3; // Smoothing factor

  PoseClassifier({this.logEveryXFrames = 1});

  /// Load the trained KNN model from CSV training data
  Future<void> loadModel() async {
    try {
      debugPrint('🔄 Loading KNN model...');
      
      final csvContent = await rootBundle.loadString('assets/pushup_features_binary.csv');
      final trainData = DataFrame.fromRawCsv(
        csvContent,
        headerExists: true,
        fieldDelimiter: ',',
      );

      debugPrint('✅ Training data loaded: ${trainData.rows.length} samples');
      
      _classifier = KnnClassifier(
        trainData,
        'pose',
        3,
        kernel: KernelType.gaussian,
        distance: Distance.euclidean,
      );

      _isModelLoaded = true;
      debugPrint('✅ KNN model trained and ready!');
    } catch (e) {
      debugPrint('❌ Error loading model: $e');
      _isModelLoaded = false;
    }
  }

  // --- Core 3D helpers --------------------------------------------------------

  PoseLandmark _avgLandmarks(List<PoseLandmark> list) {
    final x = list.map((e) => e.x).reduce((a, b) => a + b) / list.length;
    final y = list.map((e) => e.y).reduce((a, b) => a + b) / list.length;
    final z = list.map((e) => e.z).reduce((a, b) => a + b) / list.length;
    return PoseLandmark(
      type: PoseLandmarkType.nose,
      x: x, y: y, z: z, likelihood: 1.0,
    );
  }

  double _distance3D(PoseLandmark a, PoseLandmark b) {
    return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2) + pow(a.z - b.z, 2));
  }

  double _angle3D(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final ab = [a.x - b.x, a.y - b.y, a.z - b.z];
    final cb = [c.x - b.x, c.y - b.y, c.z - b.z];
    final dot = ab[0] * cb[0] + ab[1] * cb[1] + ab[2] * cb[2];
    final magAB = sqrt(ab[0]*ab[0] + ab[1]*ab[1] + ab[2]*ab[2]);
    final magCB = sqrt(cb[0]*cb[0] + cb[1]*cb[1] + cb[2]*cb[2]);
    if (magAB == 0 || magCB == 0) return 0;
    return acos((dot / (magAB * magCB)).clamp(-1.0, 1.0)) * 180 / pi;
  }

  // --- MediaPipe-style normalization -----------------------------------------

  Map<PoseLandmarkType, PoseLandmark> _normalizeLandmarks(
    Map<PoseLandmarkType, PoseLandmark> lms,
  ) {
    final center = _avgLandmarks([
      lms[PoseLandmarkType.leftHip]!,
      lms[PoseLandmarkType.rightHip]!,
    ]);
    final centered = <PoseLandmarkType, PoseLandmark>{};
    for (final e in lms.entries) {
      centered[e.key] = PoseLandmark(
        type: e.key,
        x: e.value.x - center.x,
        y: e.value.y - center.y,
        z: e.value.z - center.z,
        likelihood: e.value.likelihood,
      );
    }

    final leftShoulder = centered[PoseLandmarkType.leftShoulder]!;
    final rightShoulder = centered[PoseLandmarkType.rightShoulder]!;
    final leftHip = centered[PoseLandmarkType.leftHip]!;
    final rightHip = centered[PoseLandmarkType.rightHip]!;

    final torsoLen = _distance3D(
      _avgLandmarks([leftShoulder, rightShoulder]),
      _avgLandmarks([leftHip, rightHip]),
    );
    final scale = torsoLen == 0 ? 1.0 : torsoLen;

    final normalized = <PoseLandmarkType, PoseLandmark>{};
    for (final e in centered.entries) {
      normalized[e.key] = PoseLandmark(
        type: e.key,
        x: e.value.x / scale,
        y: e.value.y / scale,
        z: e.value.z / scale,
        likelihood: e.value.likelihood,
      );
    }
    return normalized;
  }

  // --- Feature extraction ----------------------------------------------------

  Map<String, double> extractFeatures(Pose pose) {
    final lms = _normalizeLandmarks(pose.landmarks);
    PoseLandmark get(PoseLandmarkType t) => lms[t]!;

    final leftElbowAngle = _angle3D(
      get(PoseLandmarkType.leftWrist),
      get(PoseLandmarkType.leftElbow),
      get(PoseLandmarkType.leftShoulder)
    );
    final rightElbowAngle = _angle3D(
      get(PoseLandmarkType.rightWrist),
      get(PoseLandmarkType.rightElbow),
      get(PoseLandmarkType.rightShoulder)
    );
    currentElbowAngle.value = (leftElbowAngle + rightElbowAngle) / 2;

    final distances = {
      'left_shoulder_left_wrist':
          _distance3D(get(PoseLandmarkType.leftShoulder), get(PoseLandmarkType.leftWrist)),
      'right_shoulder_right_wrist':
          _distance3D(get(PoseLandmarkType.rightShoulder), get(PoseLandmarkType.rightWrist)),
      'left_hip_left_ankle':
          _distance3D(get(PoseLandmarkType.leftHip), get(PoseLandmarkType.leftAnkle)),
      'right_hip_right_ankle':
          _distance3D(get(PoseLandmarkType.rightHip), get(PoseLandmarkType.rightAnkle)),
      'left_hip_left_wrist':
          _distance3D(get(PoseLandmarkType.leftHip), get(PoseLandmarkType.leftWrist)),
      'right_hip_right_wrist':
          _distance3D(get(PoseLandmarkType.rightHip), get(PoseLandmarkType.rightWrist)),
      'left_shoulder_left_ankle':
          _distance3D(get(PoseLandmarkType.leftShoulder), get(PoseLandmarkType.leftAnkle)),
      'right_shoulder_right_ankle':
          _distance3D(get(PoseLandmarkType.rightShoulder), get(PoseLandmarkType.rightAnkle)),
      'left_hip_right_wrist':
          _distance3D(get(PoseLandmarkType.leftHip), get(PoseLandmarkType.rightWrist)),
      'right_hip_left_wrist':
          _distance3D(get(PoseLandmarkType.rightHip), get(PoseLandmarkType.leftWrist)),
      'left_elbow_right_elbow':
          _distance3D(get(PoseLandmarkType.leftElbow), get(PoseLandmarkType.rightElbow)),
      'left_knee_right_knee':
          _distance3D(get(PoseLandmarkType.leftKnee), get(PoseLandmarkType.rightKnee)),
      'left_wrist_right_wrist':
          _distance3D(get(PoseLandmarkType.leftWrist), get(PoseLandmarkType.rightWrist)),
      'left_ankle_right_ankle':
          _distance3D(get(PoseLandmarkType.leftAnkle), get(PoseLandmarkType.rightAnkle)),
      'left_hip_avg_left_wrist_left_ankle': _distance3D(
        get(PoseLandmarkType.leftHip),
        _avgLandmarks([get(PoseLandmarkType.leftWrist), get(PoseLandmarkType.leftAnkle)]),
      ),
      'right_hip_avg_right_wrist_right_ankle': _distance3D(
        get(PoseLandmarkType.rightHip),
        _avgLandmarks([get(PoseLandmarkType.rightWrist), get(PoseLandmarkType.rightAnkle)]),
      ),
    };

    final angles = {
      'right_elbow_right_shoulder_right_hip':
          _angle3D(get(PoseLandmarkType.rightElbow), get(PoseLandmarkType.rightShoulder), get(PoseLandmarkType.rightHip)),
      'left_elbow_left_shoulder_left_hip':
          _angle3D(get(PoseLandmarkType.leftElbow), get(PoseLandmarkType.leftShoulder), get(PoseLandmarkType.leftHip)),
      'right_knee_mid_hip_left_knee': _angle3D(
        get(PoseLandmarkType.rightKnee),
        _avgLandmarks([get(PoseLandmarkType.leftHip), get(PoseLandmarkType.rightHip)]),
        get(PoseLandmarkType.leftKnee),
      ),
      'right_hip_right_knee_right_ankle':
          _angle3D(get(PoseLandmarkType.rightHip), get(PoseLandmarkType.rightKnee), get(PoseLandmarkType.rightAnkle)),
      'left_hip_left_knee_left_ankle':
          _angle3D(get(PoseLandmarkType.leftHip), get(PoseLandmarkType.leftKnee), get(PoseLandmarkType.leftAnkle)),
      'right_wrist_right_elbow_right_shoulder':
          _angle3D(get(PoseLandmarkType.rightWrist), get(PoseLandmarkType.rightElbow), get(PoseLandmarkType.rightShoulder)),
      'left_wrist_left_elbow_left_shoulder':
          _angle3D(get(PoseLandmarkType.leftWrist), get(PoseLandmarkType.leftElbow), get(PoseLandmarkType.leftShoulder)),
    };

    return {...distances, ...angles};
  }

  // --- Classification with MediaPipe-style confidence -------------------------

  Future<Map<String, dynamic>> classifyPose(Pose pose) async {
    if (!_isModelLoaded || _classifier == null) {
      return {
        'pose': 'unknown',
        'confidence': 0.0,
        'error': 'Model not loaded',
      };
    }

    try {
      final features = extractFeatures(pose);
      
      final featureList = [
        features['left_shoulder_left_wrist']!,
        features['right_shoulder_right_wrist']!,
        features['left_hip_left_ankle']!,
        features['right_hip_right_ankle']!,
        features['left_hip_left_wrist']!,
        features['right_hip_right_wrist']!,
        features['left_shoulder_left_ankle']!,
        features['right_shoulder_right_ankle']!,
        features['left_hip_right_wrist']!,
        features['right_hip_left_wrist']!,
        features['left_elbow_right_elbow']!,
        features['left_knee_right_knee']!,
        features['left_wrist_right_wrist']!,
        features['left_ankle_right_ankle']!,
        features['left_hip_avg_left_wrist_left_ankle']!,
        features['right_hip_avg_right_wrist_right_ankle']!,
        features['right_elbow_right_shoulder_right_hip']!,
        features['left_elbow_left_shoulder_left_hip']!,
        features['right_knee_mid_hip_left_knee']!,
        features['right_hip_right_knee_right_ankle']!,
        features['left_hip_left_knee_left_ankle']!,
        features['right_wrist_right_elbow_right_shoulder']!,
        features['left_wrist_left_elbow_left_shoulder']!,
      ];

      final testData = DataFrame([featureList], headerExists: false);
      final probabilities = _classifier!.predictProbabilities(testData);
      final probRow = probabilities.rows.first.toList();
      
      double downProb = 0.0;
      double upProb = 0.0;
      
      for (var i = 0; i < probRow.length; i++) {
        final prob = (probRow[i] as num).toDouble();
        if (i == 0) {
          downProb = prob;
        } else {
          upProb = prob;
        }
      }
      
      // Convert probabilities to confidence scores (0-10 scale like MediaPipe)
      // Higher probability = higher confidence score
      final rawDownConf = downProb * 10.0;
      final rawUpConf = upProb * 10.0;
      
      // Apply EMA smoothing to reduce jitter
      _smoothedDownConf = _emaAlpha * rawDownConf + (1 - _emaAlpha) * _smoothedDownConf;
      _smoothedUpConf = _emaAlpha * rawUpConf + (1 - _emaAlpha) * _smoothedUpConf;
      
      // Update notifiers for visualization
      downConfidence.value = _smoothedDownConf;
      upConfidence.value = _smoothedUpConf;
      
      // Determine current pose based on which confidence is higher
      String poseName;
      double displayConfidence;
      
      if (_smoothedDownConf > _smoothedUpConf) {
        poseName = 'pushups_down';
        displayConfidence = downProb;
      } else {
        poseName = 'pushups_up';
        displayConfidence = upProb;
      }
      
      // Update the repetition counter (MediaPipe style)
      _updateRepetitionCounter(_smoothedDownConf);
      
      // Update notifiers
      currentPose.value = _poseEntered ? 'pushups_down' : 'pushups_up';
      confidence.value = displayConfidence;

      return {
        'pose': poseName,
        'confidence': displayConfidence,
        'down_confidence': _smoothedDownConf,
        'up_confidence': _smoothedUpConf,
      };
    } catch (e) {
      debugPrint('❌ Classification error: $e');
      return {
        'pose': 'error',
        'confidence': 0.0,
        'error': e.toString(),
      };
    }
  }

  // MediaPipe-style repetition counter
  void _updateRepetitionCounter(double downConfidence) {
    // If we're not in the pose, check if we're entering it
    if (!_poseEntered) {
      if (downConfidence > enterThreshold.value) {
        _poseEntered = true;
        debugPrint('⬇️ Entered DOWN position (conf: ${downConfidence.toStringAsFixed(1)})');
      }
      return;
    }
    
    // If we're in the pose, check if we're exiting it
    if (downConfidence < exitThreshold.value) {
      _pushupCount++;
      pushupCounter.value = _pushupCount;
      _poseEntered = false;
      debugPrint('💪 Pushup #$_pushupCount completed! (conf: ${downConfidence.toStringAsFixed(1)})');
    }
  }

  void resetCounter() {
    _pushupCount = 0;
    pushupCounter.value = 0;
    _poseEntered = false;
    _smoothedDownConf = 0.0;
    _smoothedUpConf = 0.0;
    debugPrint('🔄 Counter reset');
  }
  
  void adjustEnterThreshold(double value) {
    enterThreshold.value = value.clamp(1.0, 9.5);
    // Ensure exit is always lower than enter
    if (exitThreshold.value >= enterThreshold.value) {
      exitThreshold.value = enterThreshold.value - 0.5;
    }
    debugPrint('🎚️ Enter threshold: ${enterThreshold.value.toStringAsFixed(1)}');
  }
  
  void adjustExitThreshold(double value) {
    exitThreshold.value = value.clamp(0.5, 9.0);
    // Ensure exit is always lower than enter
    if (exitThreshold.value >= enterThreshold.value) {
      enterThreshold.value = exitThreshold.value + 0.5;
    }
    debugPrint('🎚️ Exit threshold: ${exitThreshold.value.toStringAsFixed(1)}');
  }

  Future<void> processAndClassify(Pose pose) async {
    _frameCount++;
    if (_frameCount % logEveryXFrames != 0) return;

    await classifyPose(pose);
  }

  void dispose() {
    pushupCounter.dispose();
    currentPose.dispose();
    confidence.dispose();
    enterThreshold.dispose();
    exitThreshold.dispose();
    downConfidence.dispose();
    upConfidence.dispose();
    currentElbowAngle.dispose();
  }
}