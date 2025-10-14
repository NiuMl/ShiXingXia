import '../models/exercise_config.dart';
import 'base_exercise_classifier.dart';

/// Classifier specifically for sit-up exercises
/// Extends the base classifier with sit-up specific logic
class SitupClassifier extends BaseExerciseClassifier {
  SitupClassifier({super.logEveryXFrames = 1})
      : super(
          config: ExerciseConfig.situp,
        );

  // Sit-ups are performed lying down
  // No horizontal position requirement like push-ups
}
