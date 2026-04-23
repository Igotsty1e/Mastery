abstract final class AppConfig {
  // Override for device testing: use 10.0.2.2 on Android emulator.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  // Hardcoded for MVP — single fixture lesson.
  static const String defaultLessonId =
      'a1b2c3d4-0001-4000-8000-000000000001';
}
