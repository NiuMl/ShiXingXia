import '../models/exercise_config.dart';
import 'base_exercise_classifier.dart';

/// Classifier specifically for push-up exercises
/// Extends the base classifier with push-up specific logic
class PushupClassifier extends BaseExerciseClassifier {
  PushupClassifier({super.logEveryXFrames = 1})
      : super(
          config: ExerciseConfig.pushup,
        );

  // Push-ups have the horizontal position requirement built into the config
  // No additional custom logic needed for now, but this class can be extended
  // with push-up specific features in the future (e.g., form checks, etc.)
}
