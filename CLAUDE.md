# GetFit - Exercise Tracking & App Blocker

## Project Overview

GetFit is a Flutter Android app that uses computer vision to count exercise repetitions and converts them into screen time minutes for blocked apps. The app uses Google ML Kit for pose detection and a K-Nearest Neighbors (KNN) classifier to recognize and count exercise reps in real-time.

**Core Concept**: Perform exercises → Earn minutes → Spend minutes on blocked apps

## Architecture

### Tech Stack
- **Frontend**: Flutter/Dart
- **Backend**: Native Android (Kotlin) for app blocking & time tracking
- **ML**: Google ML Kit Pose Detection + KNN classifier (ml_algo package)
- **State Management**: ValueNotifiers
- **Storage**: SharedPreferences (cross-platform storage between Flutter & Android)

### Key Components

#### 1. Flutter Layer (`lib/`)

**Models** ([lib/models/](lib/models/))
- [`exercise_config.dart`](lib/models/exercise_config.dart): Defines exercise types and configurations
  - `ExerciseType` enum: pushup, squat, situp, pullup, jumpingJack
  - `ExerciseConfig` class: Contains display info, colors, thresholds, position requirements
  - Predefined configs for all 5 exercises

**Classifiers** ([lib/classifiers/](lib/classifiers/))
- [`base_exercise_classifier.dart`](lib/classifiers/base_exercise_classifier.dart): Core ML logic (511 lines)
  - Loads KNN model from CSV training data
  - Extracts 23 pose features (distances & angles)
  - MediaPipe-style normalization (centered on hips, scaled by torso)
  - Repetition counting with enter/exit thresholds
  - EMA smoothing for confidence scores
  - Horizontal position validation for push-ups
  - Calibration controls (adjust sensitivity)

- Exercise-specific classifiers extend base:
  - [`pushup_classifier.dart`](lib/classifiers/pushup_classifier.dart)
  - [`squat_classifier.dart`](lib/classifiers/squat_classifier.dart)
  - [`situp_classifier.dart`](lib/classifiers/situp_classifier.dart)
  - [`pullup_classifier.dart`](lib/classifiers/pullup_classifier.dart)
  - [`jumpingjack_classifier.dart`](lib/classifiers/jumpingjack_classifier.dart)

- [`exercise_classifier_factory.dart`](lib/classifiers/exercise_classifier_factory.dart): Creates appropriate classifier based on exercise type

**Services** ([lib/services/](lib/services/))
- [`app_blocker_service.dart`](lib/services/app_blocker_service.dart): Flutter side of app blocking
  - Method channel communication with Android service
  - Manages blocked app list
  - Controls blocking enable/disable state
  - Saves/restores settings via SharedPreferences

- [`time_tracking_service.dart`](lib/services/time_tracking_service.dart): Manages earned/spent time
  - Stores time in **seconds** (precise tracking)
  - Reads time updated by native Android service
  - Uses `prefs.reload()` to get latest native updates
  - Converts to minutes for display

**Screens** ([lib/screens/](lib/screens/))
- [`main_menu_screen.dart`](lib/screens/main_menu_screen.dart): Home screen
  - Shows time circle widget
  - Lists all exercises
  - Timer refreshes every second to show real-time updates

- [`exercise_screen.dart`](lib/screens/exercise_screen.dart): Exercise tracking (973 lines)
  - Camera preview with pose overlay
  - Real-time rep counting
  - Confidence visualization
  - Calibration panel (slide-out drawer)
  - Form feedback (elbow angle, body position)
  - Awards earned minutes on exit

- [`app_blocker_settings_screen.dart`](lib/screens/app_blocker_settings_screen.dart):
  - Select apps to block
  - Enable/disable blocking toggle
  - Shows installed apps list

- [`settings_menu_screen.dart`](lib/screens/settings_menu_screen.dart): Settings hub

- [`setup_permissions_screen.dart`](lib/screens/setup_permissions_screen.dart): Initial setup
  - Requests Accessibility Service permission
  - Requests Usage Stats permission
  - Requests Battery Optimization exemption
  - Requests Notification permission
  - Auto-navigates when all granted

**Widgets** ([lib/widgets/](lib/widgets/))
- [`pose_painter_mlkit.dart`](lib/widgets/pose_painter_mlkit.dart): Draws skeleton overlay on camera
- [`time_circle_widget.dart`](lib/widgets/time_circle_widget.dart): Circular progress showing earned/spent/available time

**Entry Point**
- [`main.dart`](lib/main.dart): App initialization
  - Restores saved app blocker settings on startup
  - Routes to setup or main menu based on completion state

#### 2. Native Android Layer (`android/app/src/main/kotlin/`)

**MainActivity** ([MainActivity.kt](android/app/src/main/kotlin/com/example/getfit/MainActivity.kt))
- Method channel handler for Flutter ↔ Android communication
- Permission checks and requests:
  - Accessibility Service
  - Usage Stats
  - Battery Optimization
  - Notifications
- Returns list of installed apps
- Updates service settings via companion object

**AppBlockerService** ([AppBlockerService.kt](android/app/src/main/kotlin/com/example/getfit/AppBlockerService.kt)) - 609 lines
- **AccessibilityService** that monitors foreground apps
- **Time Tracking**:
  - Deducts time every second while using blocked apps
  - Stores to SharedPreferences (`FlutterSharedPreferences`)
  - Keys: `flutter.earned_seconds`, `flutter.spent_seconds`, `flutter.last_deduction_at`
  - Session-based tracking with live deduction

- **Blocking Logic**:
  1. Polls foreground app every 500ms via UsageStatsManager
  2. Checks if app is in blocked list
  3. If blocked app has available time → show notification, track usage
  4. If no time → show fullscreen overlay, block app
  5. When time expires → immediately save and show block

- **Foreground Service**: Runs as foreground service to prevent being killed
- **Notifications**: Shows live countdown of remaining time
- **Overlay**: Custom blocking screen with "Return to Home" button

#### 3. ML Training Data (`assets/`)

CSV files with 23 features + 1 label column (`pose`):
- `pushup_features_binary.csv`
- `squat_features_binary.csv`
- `situp_features_binary.csv`
- `pullup_features_binary.csv`
- `jumpingjack_features_binary.csv`

**Features** (normalized distances and angles):
- 16 distance features (e.g., `left_shoulder_left_wrist`, `left_hip_left_ankle`)
- 7 angle features (e.g., `right_wrist_right_elbow_right_shoulder`)
- Binary labels: `0` = down/closed position, `1` = up/open position

## Data Flow

### Exercise → Time Earning Flow
1. User opens exercise screen
2. Camera captures frames → ML Kit detects pose
3. Classifier extracts features → KNN predicts pose
4. Rep counted when confidence crosses enter/exit thresholds
5. On screen exit: `TimeTrackingService.addEarnedMinutes(repCount)`
6. Saves to SharedPreferences: `flutter.earned_seconds += repCount * 60`

### App Blocking & Time Spending Flow
1. Native `AppBlockerService` polls foreground app every 500ms
2. If blocked app detected:
   - Check available time: `earned_seconds - spent_seconds`
   - If time available: Start session tracking, show notification
   - Every second: `spent_seconds++`, update notification
   - When time expires: Save session, show block overlay
3. If non-blocked app or home: Stop tracking, hide notification
4. Flutter reads updated time via `prefs.reload()` every second

## Key Features

### Pose Detection
- Uses Google ML Kit Pose Detection (stream mode)
- 33 landmark points (MediaPipe format)
- 3D coordinates (x, y, z)
- Camera: Front-facing, low resolution, NV21/BGRA8888 format

### Exercise Counting Algorithm
1. **Normalization**: Center on hip average, scale by torso length
2. **Feature Extraction**: Calculate 23 distances + angles
3. **Classification**: KNN with k=3, Gaussian kernel, Euclidean distance
4. **Smoothing**: EMA filter (α=0.3) to reduce jitter
5. **Counting**: MediaPipe-style state machine
   - Enter state: confidence > enterThreshold (default 6.0)
   - Exit state: confidence < exitThreshold (default 4.0)
   - Rep counted on exit

### Calibration
- Users can adjust enter/exit thresholds per exercise
- Presets: Beginner (4.0/2.0), Normal (6.0/4.0), Strict (7.5/5.5)
- Live feedback: elbow angle, body position, confidence bars

### App Blocking
- Uses Android AccessibilityService for app detection
- UsageStatsManager for reliable foreground app detection
- Fullscreen overlay blocks access when time runs out
- Persistent notification shows remaining time
- Session-based tracking prevents time manipulation

## Time Tracking Details

**Storage Format**: All time stored in **seconds** for precision

**SharedPreferences Keys** (shared between Flutter & Android):
- `flutter.earned_seconds`: Total seconds earned from exercises
- `flutter.spent_seconds`: Total seconds spent in blocked apps
- `flutter.last_deduction_at`: Timestamp of last deduction (for session continuity)

**Conversion**: 1 rep = 60 seconds = 1 minute of screen time

**Session Tracking**:
- Starts when user opens blocked app
- Deducts 1 second per second of usage
- Saves session on app close or time expiration
- Prevents double-counting via `last_deduction_at` timestamp

## Permissions Required

1. **Camera**: For pose detection during exercises
2. **Accessibility Service**: To detect foreground apps and show block overlay
3. **Usage Stats**: Reliable foreground app detection
4. **Battery Optimization Exemption**: Keep service running in background
5. **Notifications**: Show time tracking notifications

## Code Organization

```
lib/
├── models/           # Data models (exercise config)
├── classifiers/      # ML logic (base + 5 exercise classifiers)
├── services/         # Business logic (app blocker, time tracking)
├── screens/          # UI screens (6 screens)
├── widgets/          # Reusable UI components (pose painter, time circle)
└── main.dart         # Entry point

android/app/src/main/kotlin/com/example/getfit/
├── MainActivity.kt          # Flutter bridge
└── AppBlockerService.kt     # Background service

assets/
└── *_features_binary.csv    # ML training data (5 files)
```

## Important Implementation Notes

### Pose Detection Performance
- Model loaded in compute isolate to avoid UI blocking
- Processes every frame (logEveryXFrames=1)
- Uses low camera resolution for better FPS
- Skips frames if previous detection still processing

### Cross-Platform Data Sync
- Flutter writes: `earned_seconds` (when exercises complete)
- Android writes: `spent_seconds`, `last_deduction_at` (during blocking)
- Flutter reads both: Uses `prefs.reload()` before reading
- Refresh interval: 1 second on main menu

### Blocking Robustness
- Polls every 500ms (not event-based) to catch quick app switches
- Overlay has `TYPE_ACCESSIBILITY_OVERLAY` flag (covers all apps)
- Foreground service prevents Android from killing the service
- Battery optimization exemption ensures 24/7 operation

### Time Tracking Precision
- Deducts every 1 second (not every minute)
- Session-based to handle app switches
- Checks available time before each deduction
- Immediately blocks when time hits 0

## Development Tips

### Testing Exercises
1. Adjust thresholds in calibration panel for easier counting
2. Check confidence bars to see if pose is recognized
3. Use form feedback to ensure proper body position
4. Push-ups require horizontal position (0-45° from ground)

### Testing App Blocking
1. Enable blocking in settings
2. Select an app to block
3. Earn time by doing exercises
4. Open blocked app to see notification
5. Wait for time to expire to see block overlay

### Debugging
- Flutter: Standard `debugPrint()` statements in classifier
- Android: `Log.d(TAG, ...)` in AppBlockerService
- Check logcat for native service logs
- Use calibration panel to see live confidence scores

## Exercise State Labels

Each exercise has custom labels for enter/exit states:
- **Push-ups**: DOWN (arms bent) / UP (arms straight)
- **Squats**: DOWN (low squat) / UP (standing)
- **Sit-ups**: UP (torso raised) / DOWN (lying)
- **Pull-ups**: UP (chin above bar) / DOWN (hanging)
- **Jumping Jacks**: OPEN (arms/legs spread) / CLOSED (standing)

## Recent Optimizations (from git history)

- **Robust timer**: Second-based deduction with session tracking
- **Second counting**: Changed from minute to second precision
- **Pre-optimization**: Baseline before performance tuning
- **Robust counting 2**: Improved repetition counting accuracy
- **Time reduction**: Optimized time deduction algorithm
