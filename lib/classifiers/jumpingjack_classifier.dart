import '../models/exercise_config.dart';
import 'base_exercise_classifier.dart';

/// Classifier specifically for jumping jack exercises
/// Extends the base classifier with jumping jack specific logic
class JumpingJackClassifier extends BaseExerciseClassifier {
  JumpingJackClassifier({super.logEveryXFrames = 1})
      : super(
          config: ExerciseConfig.jumpingJack,
        );

  // Jumping jacks are performed standing
  // No horizontal position requirement
}
