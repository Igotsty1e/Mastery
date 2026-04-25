abstract final class AppConfig {
  // Override for device testing: use 10.0.2.2 on Android emulator.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  // Hardcoded for MVP. Points at U02_L01 so the dashboard CTA opens the
  // lesson that exercises the audio + image runtime end-to-end. U01_L01
  // remains in the manifest and is reachable by id.
  static const String defaultLessonId =
      'a1b2c3d4-0002-4000-8000-000000000001';
}
