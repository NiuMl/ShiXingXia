# GetFit - AI-Powered Exercise Tracker

A Flutter application that uses AI-powered pose detection to track and count exercise repetitions for multiple exercise types.

## Features

- **Multi-Exercise Support**: Track push-ups, squats, sit-ups, pull-ups, and jumping jacks
- **Real-time Pose Detection**: Uses Google ML Kit for accurate pose tracking
- **KNN Classification**: Machine learning-based exercise classification
- **Adaptive Thresholds**: Calibrate sensitivity for different fitness levels
- **Form Feedback**: Real-time elbow angle and body position monitoring
- **Beautiful UI**: Color-coded exercise cards with smooth animations
- **Exercise-Specific Validation**: Push-ups require horizontal body position

## Architecture

### Modular Design
The app follows Flutter best practices with a clean, modular architecture:

```
lib/
├── models/              # Data models and configurations
├── classifiers/         # Exercise classification logic
├── screens/            # UI screens
└── widgets/            # Reusable widgets
```

### Key Components

1. **Exercise Configuration System** ([models/exercise_config.dart](lib/models/exercise_config.dart))
   - Centralized exercise definitions
   - Type-safe configuration
   - Easy to extend with new exercises

2. **Base Classifier** ([classifiers/base_exercise_classifier.dart](lib/classifiers/base_exercise_classifier.dart))
   - Shared pose detection logic
   - MediaPipe-style repetition counting
   - Confidence scoring and smoothing

3. **Exercise-Specific Classifiers**
   - Inherit from base classifier
   - Can override for custom behavior
   - Automatic factory creation

4. **Generic Exercise Screen** ([screens/exercise_screen.dart](lib/screens/exercise_screen.dart))
   - Single screen for all exercises
   - Dynamically adapts to exercise type
   - Full feature set: camera, calibration, stats

## Getting Started

### Prerequisites
- Flutter SDK (3.9.2 or higher)
- Android Studio / Xcode for mobile development
- Training CSV files for each exercise

### Installation

1. Clone the repository
```bash
git clone <your-repo-url>
cd getfit
```

2. Install dependencies
```bash
flutter pub get
```

3. Add CSV training data
Place your CSV files in the `assets/` directory:
- `pushup_features_binary.csv` (already present)
- `squat_features_binary.csv`
- `situp_features_binary.csv`
- `pullup_features_binary.csv`
- `jumpingjack_features_binary.csv`

4. Run the app
```bash
flutter run
```

## Exercise Specifications

### Push-ups
- **Body Position**: Must be horizontal (0-45° from ground)
- **Tracking**: DOWN (arms bent) → UP (arms extended)
- **Colors**: Orange (down) / Green (up)

### Squats
- **Body Position**: Standing, no restrictions
- **Tracking**: DOWN (deep squat) → UP (standing)
- **Colors**: Blue / Light Blue

### Sit-ups
- **Body Position**: Lying down, no restrictions
- **Tracking**: UP (torso raised) → DOWN (lying flat)
- **Colors**: Purple / Pink

### Pull-ups
- **Body Position**: Hanging, no restrictions
- **Tracking**: UP (chin over bar) → DOWN (arms extended)
- **Colors**: Teal / Cyan

### Jumping Jacks
- **Body Position**: Standing, no restrictions
- **Tracking**: OPEN (arms/legs spread) → CLOSED (arms/legs together)
- **Colors**: Red / Amber

## Usage

1. **Main Menu**: Select an exercise from the grid
2. **Camera View**: Position yourself in front of the camera
3. **Start Exercising**: The app automatically detects and counts reps
4. **Calibrate** (optional): Tap the tune icon to adjust sensitivity
5. **Reset**: Tap the refresh icon to start over

### Calibration Tips

- **Enter Threshold**: Higher = harder to enter "down" position
- **Exit Threshold**: Higher = need more confidence to count rep
- **Presets Available**: Beginner (4.0/2.0), Normal (6.0/4.0), Strict (7.5/5.5)

## Adding New Exercises

1. Define configuration in [models/exercise_config.dart](lib/models/exercise_config.dart)
2. Create classifier in `classifiers/yourexercise_classifier.dart`
3. Update factory in [classifiers/exercise_classifier_factory.dart](lib/classifiers/exercise_classifier_factory.dart)
4. Add CSV asset to [pubspec.yaml](pubspec.yaml)
5. Place training data in `assets/` directory

See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) for detailed instructions.

## Training Data Format

CSV files should contain:
- 23 feature columns (distances and angles between pose landmarks)
- 1 target column named 'pose' with values: `{exercise}_down` or `{exercise}_up`
- Header row required

## Technologies Used

- **Flutter**: Cross-platform UI framework
- **Google ML Kit**: Pose detection
- **KNN Classifier**: Exercise state classification
- **Camera Plugin**: Real-time video processing

## Project Status

✅ Core functionality complete
✅ Multi-exercise support
✅ Modular architecture
⚠️ Training data needed for 4 exercises (squat, situp, pullup, jumping jack)
🔮 Future: Exercise history, statistics, workout plans

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Follow Flutter style guidelines
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see LICENSE file for details.

## Acknowledgments

- Google ML Kit team for pose detection
- MediaPipe for inspiration on repetition counting
- Flutter community for excellent packages

## Support

For issues, questions, or suggestions, please open an issue on GitHub.

---

**Note**: This app requires CSV training data for each exercise. The push-up model is included as a reference. You'll need to collect and format training data for the other exercises following the same structure.
