import '../models/exercise_config.dart';
import 'base_multistate_classifier.dart';

/// 108拜分类器
///
/// 多状态有序流程：站立(0) → 合掌(1) → 趴下(2) → 站立(0，计数+1)
/// 计数与状态机逻辑由 [BaseMultiStateClassifier] 实现，本类仅绑定配置。
class Bai108Classifier extends BaseMultiStateClassifier {
  Bai108Classifier({super.logEveryXFrames = 1})
      : super(config: ExerciseConfig.bai108);
}
