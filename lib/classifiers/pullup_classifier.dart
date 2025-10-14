import '../models/exercise_config.dart';
import 'base_exercise_classifier.dart';

/// Classifier specifically for pull-up exercises
/// Extends the base classifier with pull-up specific logic
class PullupClassifier extends BaseExerciseClassifier {
  PullupClassifier({super.logEveryXFrames = 1})
      : super(
          config: ExerciseConfig.pullup,
        );

  // Pull-ups are performed hanging from a bar
  // No horizontal position requirement
}
