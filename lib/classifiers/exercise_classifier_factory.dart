import '../models/exercise_config.dart';
import 'base_exercise_classifier.dart';
import 'pushup_classifier.dart';
import 'squat_classifier.dart';
import 'situp_classifier.dart';
import 'pullup_classifier.dart';
import 'jumpingjack_classifier.dart';
import 'bai108_classifier.dart';

/// Factory class for creating exercise classifiers
class ExerciseClassifierFactory {
  /// Creates a classifier based on the exercise configuration
  static BaseExerciseClassifier createClassifier(
    ExerciseConfig config, {
    int logEveryXFrames = 1,
  }) {
    switch (config.type) {
      case ExerciseType.pushup:
        return PushupClassifier(logEveryXFrames: logEveryXFrames);
      case ExerciseType.squat:
        return SquatClassifier(logEveryXFrames: logEveryXFrames);
      case ExerciseType.situp:
        return SitupClassifier(logEveryXFrames: logEveryXFrames);
      case ExerciseType.pullup:
        return PullupClassifier(logEveryXFrames: logEveryXFrames);
      case ExerciseType.jumpingJack:
        return JumpingJackClassifier(logEveryXFrames: logEveryXFrames);
      case ExerciseType.bai108:
        return Bai108Classifier(logEveryXFrames: logEveryXFrames);
    }
  }
}
