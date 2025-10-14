import '../models/exercise_config.dart';
import 'base_exercise_classifier.dart';

/// Classifier specifically for squat exercises
/// Extends the base classifier with squat specific logic
class SquatClassifier extends BaseExerciseClassifier {
  SquatClassifier({super.logEveryXFrames = 1})
      : super(
          config: ExerciseConfig.squat,
        );

  // Squats are performed in a standing position
  // No horizontal position requirement
}
