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
  int _currentState = 0; // 当前所处状态（0 ~ stateCount-1），只前进不回退
  int _pendingCount = 0; // 下一预期状态的累积命中数（衰减式，不因其他动作清零）
  int _stateStableFrames = 0; // 当前状态已停留帧数（用于强制等待期，防止跳步）

  /// 每个状态的最小停留帧数（约 0.67 秒，30fps），
  /// 强制要求用户在每个姿势上保持一段时间，防止 KNN 波动导致连续跳步。
  final int minDwellFrames;

  /// 最小置信度阈值（0.0 ~ 1.0），只有当预测置信度超过此值时，
  /// 才允许累积或衰减状态计数。低置信度的预测被视为"不确定"。
  final double minConfidence;

  BaseMultiStateClassifier({
    required ExerciseConfig config,
    super.logEveryXFrames = 1,
    this.stableFrames = 4,
    this.minDwellFrames = 20,
    this.minConfidence = 0.5,
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
      _updateState(predicted, maxProb);

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
  ///
  /// 三重防抖机制：
  /// 1. **置信度阈值**：只有当预测置信度超过 [minConfidence] 时，才认为该预测有效。
  ///    低置信度的预测被视为"不确定"，不会推动状态转移，也不会衰减累积数。
  /// 2. **最小停留时间**：每个状态必须停留至少 [minDwellFrames] 帧后，
  ///    才允许检查并推进到下一状态。防止 KNN 分类波动导致连续跳步。
  /// 3. **累积衰减**：在允许推进的窗口期内，预测为下一状态 → 累积 +1；
  ///    预测为其他状态 → 累积 -1（不低于 0）。累积达 [stableFrames] 才推进。
  ///
  /// 状态只前进不后退：一旦推进到某状态就锁定，仅监控下一个动作。
  void _updateState(int predicted, double confidence) {
    final int nextState = (_currentState + 1) % stateCount;

    // 累加当前状态的停留帧数
    _stateStableFrames++;

    // 如果还在最小停留期内，禁止推进，直接返回
    if (_stateStableFrames < minDwellFrames) {
      return;
    }

    // 置信度门限：如果预测置信度太低，视为不确定，不影响累积数
    if (confidence < minConfidence) {
      return;
    }

    // 停留期过后 + 置信度足够 → 允许根据累积数推进
    if (predicted == nextState) {
      _pendingCount++;
    } else {
      if (_pendingCount > 0) {
        _pendingCount--;
      }
    }

    if (_pendingCount >= stableFrames) {
      final int prevState = _currentState;
      _currentState = nextState;
      _pendingCount = 0;
      _stateStableFrames = 0; // 状态转移后，重新开始计算停留时间

      // 从末状态回到起始状态 = 完成一次完整循环
      if (prevState == stateCount - 1 && _currentState == 0) {
        repetitionCounter.value = repetitionCounter.value + 1;
      }
    }
  }

  @override
  void resetCounter() {
    super.resetCounter(); // 重置 repetitionCounter 等
    _currentState = 0;
    _pendingCount = 0;
    _stateStableFrames = 0;
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
