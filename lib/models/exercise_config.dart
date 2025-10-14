import 'package:flutter/material.dart';

/// Defines the type of exercise being performed
enum ExerciseType {
  pushup,
  squat,
  situp,
  pullup,
  jumpingJack,
}

/// Configuration for a specific exercise type
class ExerciseConfig {
  final ExerciseType type;
  final String name;
  final String displayName;
  final String description;
  final IconData icon;
  final Color primaryColor;
  final Color secondaryColor;
  final String assetPath;

  // Exercise-specific validation rules
  final bool requiresHorizontalPosition;
  final double? horizontalAngleMin;
  final double? horizontalAngleMax;

  // Default threshold values
  final double defaultEnterThreshold;
  final double defaultExitThreshold;

  // Display labels for up/down states
  final String enterStateLabel;
  final String exitStateLabel;

  const ExerciseConfig({
    required this.type,
    required this.name,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.primaryColor,
    required this.secondaryColor,
    required this.assetPath,
    this.requiresHorizontalPosition = false,
    this.horizontalAngleMin,
    this.horizontalAngleMax,
    this.defaultEnterThreshold = 6.0,
    this.defaultExitThreshold = 4.0,
    this.enterStateLabel = 'DOWN',
    this.exitStateLabel = 'UP',
  });

  // Predefined configurations for each exercise type
  static const ExerciseConfig pushup = ExerciseConfig(
    type: ExerciseType.pushup,
    name: 'pushup',
    displayName: 'Push-ups',
    description: 'Upper body strength exercise',
    icon: Icons.fitness_center,
    primaryColor: Colors.orangeAccent,
    secondaryColor: Colors.greenAccent,
    assetPath: 'assets/pushup_features_binary.csv',
    requiresHorizontalPosition: true,
    horizontalAngleMin: 0.0,
    horizontalAngleMax: 45.0,
    defaultEnterThreshold: 6.0,
    defaultExitThreshold: 4.0,
    enterStateLabel: 'DOWN',
    exitStateLabel: 'UP',
  );

  static const ExerciseConfig squat = ExerciseConfig(
    type: ExerciseType.squat,
    name: 'squat',
    displayName: 'Squats',
    description: 'Lower body strength exercise',
    icon: Icons.accessibility_new,
    primaryColor: Colors.blueAccent,
    secondaryColor: Colors.lightBlueAccent,
    assetPath: 'assets/squat_features_binary.csv',
    requiresHorizontalPosition: false,
    defaultEnterThreshold: 6.0,
    defaultExitThreshold: 4.0,
    enterStateLabel: 'DOWN',
    exitStateLabel: 'UP',
  );

  static const ExerciseConfig situp = ExerciseConfig(
    type: ExerciseType.situp,
    name: 'situp',
    displayName: 'Sit-ups',
    description: 'Core strengthening exercise',
    icon: Icons.airline_seat_recline_normal,
    primaryColor: Colors.purpleAccent,
    secondaryColor: Colors.pinkAccent,
    assetPath: 'assets/situp_features_binary.csv',
    requiresHorizontalPosition: false,
    defaultEnterThreshold: 6.0,
    defaultExitThreshold: 4.0,
    enterStateLabel: 'UP',
    exitStateLabel: 'DOWN',
  );

  static const ExerciseConfig pullup = ExerciseConfig(
    type: ExerciseType.pullup,
    name: 'pullup',
    displayName: 'Pull-ups',
    description: 'Upper body pulling exercise',
    icon: Icons.arrow_upward_rounded,
    primaryColor: Colors.tealAccent,
    secondaryColor: Colors.cyanAccent,
    assetPath: 'assets/pullup_features_binary.csv',
    requiresHorizontalPosition: false,
    defaultEnterThreshold: 6.0,
    defaultExitThreshold: 4.0,
    enterStateLabel: 'UP',
    exitStateLabel: 'DOWN',
  );

  static const ExerciseConfig jumpingJack = ExerciseConfig(
    type: ExerciseType.jumpingJack,
    name: 'jumpingJack',
    displayName: 'Jumping Jacks',
    description: 'Full body cardio exercise',
    icon: Icons.local_fire_department,
    primaryColor: Colors.redAccent,
    secondaryColor: Colors.amberAccent,
    assetPath: 'assets/jumpingjack_features_binary.csv',
    requiresHorizontalPosition: false,
    defaultEnterThreshold: 6.0,
    defaultExitThreshold: 4.0,
    enterStateLabel: 'OPEN',
    exitStateLabel: 'CLOSED',
  );

  // Get all available exercises
  static List<ExerciseConfig> get allExercises => [
    pushup,
    squat,
    situp,
    pullup,
    jumpingJack,
  ];

  // Get exercise by type
  static ExerciseConfig fromType(ExerciseType type) {
    switch (type) {
      case ExerciseType.pushup:
        return pushup;
      case ExerciseType.squat:
        return squat;
      case ExerciseType.situp:
        return situp;
      case ExerciseType.pullup:
        return pullup;
      case ExerciseType.jumpingJack:
        return jumpingJack;
    }
  }
}
