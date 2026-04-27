// Wave 7.4 part 2.3 — Sign-in gate before onboarding.
//
// First-launch routing: HomeScreen → (no live session) → SignInScreen →
// (Sign in OR Skip) → OnboardingArrivalRitualScreen → Dashboard.
// Returning users with a refresh-token in secure storage bypass this
// screen. Wave 8 (legacy drop): Skip is no longer "guest mode" — it
// performs a silent stub-login under a stable per-install subject so
// every subsequent request, including server-owned lesson sessions,
// carries an Authorization header. Real Apple Sign-In replaces the
// stub later without a contract change.
//
// Design tone: Editorial Notebook, matching the shipped onboarding
// (`docs/plans/arrival-ritual.md`) — mono eyebrow, Fraunces-italic
// wordmark, calm body, two clear actions stacked.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_client.dart';
import '../theme/mastery_theme.dart';

/// Outcome of the sign-in screen, surfaced to HomeScreen so it can
/// route appropriately and (in the signed-in case) trigger the
/// device-state bulk migration before clearing local stores.
enum SignInOutcome {
  /// Apple Sign In succeeded, refresh token persisted in secure
  /// storage. HomeScreen should now run the bulk-migration of any
  /// existing device-scoped state and then proceed to onboarding (if
  /// not seen) or the dashboard.
  signedIn,

  /// Skip pressed. No session created. Existing device-scoped state
  /// stays as-is. HomeScreen proceeds to onboarding (if not seen) or
  /// the dashboard.
  skipped,
}

class SignInScreen extends StatefulWidget {
  /// AuthClient injected so the screen does not need to know how
  /// secure storage is configured. Tests pass a fake.
  final AuthClient authClient;

  /// Called once the screen has produced an outcome. HomeScreen
  /// pops back to itself and routes from there.
  final ValueChanged<SignInOutcome> onResolved;

  const SignInScreen({
    super.key,
    required this.authClient,
    required this.onResolved,
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Stub flow: send a stable per-install subject so repeat sign-ins
      // on the same device land on the same backend user. The real
      // Sign-In-with-Apple integration replaces this with the
      // identityToken Apple returns after the native sheet.
      // The stub is gated server-side by APPLE_STUB_ENABLED in
      // production — see docs/plans/auth-server-state-wave7.md.
      final subject = await _stableStubSubject();
      await widget.authClient.signInWithAppleStub(subject: subject);
      if (!mounted) return;
      widget.onResolved(SignInOutcome.signedIn);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Sign-in failed. Check connection or skip for now.';
      });
    }
  }

  static const _stubSubjectKey = 'mastery_stub_subject_v1';

  Future<String> _stableStubSubject() async {
    // Wave 8: persisted per-install id so repeat sign-ins on the same
    // device land on the same backend user. Used by both the explicit
    // Sign-in path and the silent Skip-for-now path so a learner who
    // skipped today and signs in tomorrow keeps their progress.
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_stubSubjectKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final fresh = 'stub-$now';
    await prefs.setString(_stubSubjectKey, fresh);
    return fresh;
  }

  /// Wave 8 (legacy drop): Skip is now a silent stub-login. The unauth'd
  /// `/lessons/:id/answers` and `/lessons/:id/result` routes are gone so
  /// every learner needs a session before submitting answers. Skip uses
  /// the same persistent subject as Sign in, so the user can re-enter
  /// "real" sign-in later without losing progress (server idempotency
  /// merges the records).
  Future<void> _skip() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final subject = await _stableStubSubject();
      await widget.authClient.signInWithAppleStub(subject: subject);
      if (!mounted) return;
      widget.onResolved(SignInOutcome.skipped);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not start a session. Check your connection and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Scaffold(
      backgroundColor: tokens.bgApp,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                tokens.bgPrimarySoft.withAlpha(80),
                tokens.bgApp,
              ],
              stops: const [0.0, 0.7],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  MasterySpacing.lg, 28, MasterySpacing.lg, 36),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'WELCOME',
                        style: MasteryTextStyles.mono(
                          size: 11,
                          lineHeight: 14,
                          weight: FontWeight.w600,
                          color: tokens.textTertiary,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: MasterySpacing.xl),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mastery',
                              style: MasteryTextStyles.displayItalic(
                                size: 56,
                                lineHeight: 60,
                              ),
                            ),
                            const SizedBox(height: MasterySpacing.sm),
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 340),
                              child: Text(
                                'Sign in to keep your progress across devices. The lesson flow stays the same either way.',
                                style: MasteryTextStyles.bodyMd.copyWith(
                                  color: MasteryColors.textSecondary,
                                  height: 1.55,
                                ),
                              ),
                            ),
                            const SizedBox(height: MasterySpacing.lg),
                            Container(
                              width: 36,
                              height: 1,
                              color: tokens.accentGold.withAlpha(140),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: MasterySpacing.lg),
                              Text(
                                _error!,
                                style: MasteryTextStyles.bodySm.copyWith(
                                  color: MasteryColors.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _SignInActions(
                        busy: _busy,
                        onSignIn: _signIn,
                        onSkip: _skip,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInActions extends StatelessWidget {
  final bool busy;
  final VoidCallback onSignIn;
  final VoidCallback onSkip;

  const _SignInActions({
    required this.busy,
    required this.onSignIn,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Padding(
      padding: const EdgeInsets.only(top: MasterySpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: busy ? null : onSignIn,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Sign in with Apple'),
          ),
          const SizedBox(height: MasterySpacing.sm),
          TextButton(
            onPressed: busy ? null : onSkip,
            child: Text(
              'Skip for now',
              style: MasteryTextStyles.labelMd.copyWith(
                color: tokens.textTertiary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
