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

  /// Wave 7.4 — feature flag for the auth surface. **Off by default.**
  /// When enabled at build time via
  /// `--dart-define=MASTERY_AUTH_ENABLED=true`, the AuthClient is wired
  /// into `ApiClient` and the future sign-in screen will gate first
  /// launch. Until the per-screen design call lands (see
  /// `docs/plans/auth-server-state-wave7.md` part 2), shipping this flag
  /// would change first-launch UX and is therefore behind a build flag,
  /// not a runtime toggle. Wave 7.4 part 1 (this commit) only ships
  /// dormant infra — the flag stays false in every build until part 2.
  static const bool authEnabled = bool.fromEnvironment(
    'MASTERY_AUTH_ENABLED',
    defaultValue: false,
  );
}
