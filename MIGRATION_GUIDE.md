# Migration Guide - Modular Exercise Structure

## Overview
Your Flutter app has been successfully modularized to support multiple exercise types with their specific configurations.

## New Project Structure

```
lib/
├── main.dart                          # Entry point (updated)
├── models/
│   └── exercise_config.dart          # Exercise configuration model
├── classifiers/
│   ├── base_exercise_classifier.dart # Abstract base classifier
│   ├── exercise_classifier_factory.dart # Factory for creating classifiers
│   ├── pushup_classifier.dart        # Push-up specific classifier
│   ├── squat_classifier.dart         # Squat specific classifier
│   ├── situp_classifier.dart         # Sit-up specific classifier
│   ├── pullup_classifier.dart        # Pull-up specific classifier
│   └── jumpingjack_classifier.dart   # Jumping jack specific classifier
├── screens/
│   ├── main_menu_screen.dart         # Main menu with exercise cards
│   └── exercise_screen.dart          # Generic exercise tracking screen
└── widgets/
    └── pose_painter_mlkit.dart       # Pose visualization widget

Old files (can be archived or deleted):
├── pose_screen.dart                   # Replaced by exercise_screen.dart
└── pose_classifier.dart               # Replaced by classifier classes
```

## Key Changes

### 1. Exercise Configuration System
- **File**: `models/exercise_config.dart`
- Each exercise has its own configuration with:
  - Display name, description, icon, colors
  - Specific requirements (e.g., horizontal position for push-ups)
  - Default thresholds
  - State labels (UP/DOWN, OPEN/CLOSED, etc.)

### 2. Modular Classifier Architecture
- **Base class**: `base_exercise_classifier.dart`
  - Contains all shared logic for pose classification
  - Handles repetition counting
  - Manages confidence scoring
  - Implements position validation

- **Exercise-specific classifiers**: Each exercise extends the base class
  - Easy to add custom logic for specific exercises
  - Inherits all common functionality

- **Factory pattern**: `exercise_classifier_factory.dart`
  - Creates the appropriate classifier based on exercise type

### 3. Generic Exercise Screen
- **File**: `screens/exercise_screen.dart`
- Single screen that works with any exercise type
- Automatically adapts colors, labels, and validation rules
- Maintains all features: calibration, confidence display, form feedback

### 4. Main Menu with Exercise Cards
- **File**: `screens/main_menu_screen.dart`
- Beautiful grid layout with cards for each exercise
- Color-coded by exercise type
- Easy navigation to any exercise

## Exercise-Specific Features

### Push-ups
- **Horizontal position requirement**: YES (0-45 degrees)
- **Labels**: DOWN / UP
- **Colors**: Orange / Green

### Squats
- **Horizontal position requirement**: NO
- **Labels**: DOWN / UP
- **Colors**: Blue / Light Blue

### Sit-ups
- **Horizontal position requirement**: NO
- **Labels**: UP / DOWN (reversed)
- **Colors**: Purple / Pink

### Pull-ups
- **Horizontal position requirement**: NO
- **Labels**: UP / DOWN (reversed)
- **Colors**: Teal / Cyan

### Jumping Jacks
- **Horizontal position requirement**: NO
- **Labels**: OPEN / CLOSED
- **Colors**: Red / Amber

## Required CSV Assets

Place these CSV files in the `assets/` directory:
- `pushup_features_binary.csv` ✓ (already present)
- `squat_features_binary.csv`
- `situp_features_binary.csv`
- `pullup_features_binary.csv`
- `jumpingjack_features_binary.csv`

All CSV files should follow the same format as your pushup data.

## How to Add a New Exercise

1. **Add configuration** in `models/exercise_config.dart`:
```dart
static const ExerciseConfig myExercise = ExerciseConfig(
  type: ExerciseType.myExercise,
  name: 'myExercise',
  displayName: 'My Exercise',
  description: 'Description here',
  icon: Icons.icon_name,
  primaryColor: Colors.blue,
  secondaryColor: Colors.lightBlue,
  assetPath: 'assets/myexercise_features_binary.csv',
  requiresHorizontalPosition: false,
  defaultEnterThreshold: 6.0,
  defaultExitThreshold: 4.0,
  enterStateLabel: 'DOWN',
  exitStateLabel: 'UP',
);
```

2. **Create classifier** in `classifiers/myexercise_classifier.dart`:
```dart
class MyExerciseClassifier extends BaseExerciseClassifier {
  MyExerciseClassifier({super.logEveryXFrames = 1})
      : super(config: ExerciseConfig.myExercise);
}
```

3. **Update factory** in `classifiers/exercise_classifier_factory.dart`

4. **Add CSV asset** to `pubspec.yaml`

5. Done! The exercise will automatically appear in the main menu.

## Benefits of This Architecture

1. **Separation of Concerns**: Each component has a single, clear responsibility
2. **Reusability**: Common logic is shared across all exercises
3. **Extensibility**: Easy to add new exercises or modify existing ones
4. **Maintainability**: Changes to one exercise don't affect others
5. **Type Safety**: Compile-time checks prevent configuration errors
6. **Flutter Best Practices**: Follows official Flutter architecture guidelines
7. **Scalability**: Can easily grow to support dozens of exercise types

## Testing Recommendations

1. Test each exercise individually from the main menu
2. Verify that exercise-specific features work correctly:
   - Push-ups: Horizontal position check
   - Other exercises: No position restrictions
3. Test calibration settings persist correctly
4. Verify counter resets work for each exercise
5. Check that back navigation preserves state

## Next Steps

1. Create/collect CSV training data for the 4 new exercises
2. Place CSV files in the `assets/` directory
3. Run `flutter pub get` to update dependencies
4. Test the app with each exercise type
5. Fine-tune default thresholds based on testing
6. Consider adding exercise history/statistics tracking
7. Add tutorial screens for first-time users
