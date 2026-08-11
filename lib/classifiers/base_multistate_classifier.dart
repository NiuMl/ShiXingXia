import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:ml_dataframe/ml_dataframe.dart';
import '../models/exercise_config.dart';
import 'base_exercise_classifier.dart';

/// 多状态有序流程运动分类器基类
///
/// 支持 N 个状态的有序循环计数（如 108拜：站立→合掌→趴下→站立）。
/// 与 [BaseExerciseClassifier] 的2状态计数不同，本类按状态顺序推进，
/// 完成完整循环 0→1→...→(N-1)→0 时计数 +1。
///
/// 继承自 [BaseExerciseClassifier] 以复用特征提取（[extractFeatures]）、
/// KNN 模型加载（[loadModel]）等基础设施，仅重写分类与计数逻辑。
class BaseMultiStateClassifier extends BaseExerciseClassifier {
  final int stateCount;

  /// 防抖：连续多少帧预测为同一预期状态才确认状态转移
  final int stableFrames;

  // ---- 多状态 UI 字段 ----
  final ValueNotifier<int> currentStateIndex = ValueNotifier<int>(0);
  final ValueNotifier<List<double>> stateConfidences =
      ValueNotifier<List<double>>([]);

  // ---- 状态机内部状态 ----
  int _currentState = 0; // 当前所处状态（0 ~ stateCount-1）
  int _pendingState = -1; // 待确认的下一个状态
  int _pendingCount = 0; // 连续命中待确认状态的帧数

  BaseMultiStateClassifier({
    required ExerciseConfig config,
    super.logEveryXFrames = 1,
    this.stableFrames = 4,
  })  : stateCount = config.stateLabels!.length,
        super(config: config);

  @override
  Future<Map<String, dynamic>> classifyPose(Pose pose) async {
    if (!isModelLoaded || classifier == null) {
      return {
        'pose': 'unknown',
        'confidence': 0.0,
        'error': 'Model not loaded',
      };
    }

    try {
      final features = extractFeatures(pose);

      // 按与训练数据 CSV 一致的顺序构建特征向量（23 个特征）
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
      final probabilities = classifier!.predictProbabilities(testData);
      final probRow = probabilities.rows.first.toList();

      // N 个状态的置信度（0-10 刻度，与2状态体系保持一致）
      final confs =
          probRow.map((p) => (p as num).toDouble() * 10.0).toList();
      stateConfidences.value = confs;

      // 取概率最高的状态作为当前预测
      int predicted = 0;
      double maxProb = -1;
      for (int i = 0; i < confs.length; i++) {
        if (confs[i] > maxProb) {
          maxProb = confs[i];
          predicted = i;
        }
      }

      // 有序状态机计数（带防抖）
      _updateState(predicted);

      currentStateIndex.value = _currentState;
      currentPose.value = config.stateLabels![_currentState];
      confidence.value = maxProb / 10.0;

      return {
        'pose': config.stateLabels![predicted],
        'confidence': maxProb / 10.0,
        'current_state': _currentState,
        'state_confidences': confs,
      };
    } catch (e) {
      return {
        'pose': 'error',
        'confidence': 0.0,
        'error': e.toString(),
      };
    }
  }

  /// 有序状态机：必须按 0→1→...→(N-1)→0 顺序推进，回到 0 时计数 +1。
  /// 预测为非顺序状态时忽略，等待用户回到正确节奏。
  void _updateState(int predicted) {
    final int nextState = (_currentState + 1) % stateCount;

    if (predicted == nextState) {
      // 预测为下一个预期状态 —— 累计防抖帧数
      if (predicted == _pendingState) {
        _pendingCount++;
      } else {
        _pendingState = predicted;
        _pendingCount = 1;
      }

      if (_pendingCount >= stableFrames) {
        // 连续命中达阈值，确认状态转移
        final int prevState = _currentState;
        _currentState = nextState;
        _pendingCount = 0;
        _pendingState = -1;

        // 从末状态回到起始状态 = 完成一次完整循环
        if (prevState == stateCount - 1 && _currentState == 0) {
          repetitionCounter.value = repetitionCounter.value + 1;
        }
      }
    } else if (predicted == _currentState) {
      // 停留在当前状态，重置待确认
      _pendingCount = 0;
      _pendingState = -1;
    }
    // 预测为其他非顺序状态：忽略
  }

  @override
  void resetCounter() {
    super.resetCounter(); // 重置 repetitionCounter 等
    _currentState = 0;
    _pendingState = -1;
    _pendingCount = 0;
    currentStateIndex.value = 0;
    stateConfidences.value = [];
  }

  @override
  void dispose() {
    currentStateIndex.dispose();
    stateConfidences.dispose();
    super.dispose();
  }
}
