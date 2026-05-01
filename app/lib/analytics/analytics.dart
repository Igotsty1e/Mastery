import 'dart:async';

import '../api/api_client.dart';

/// Wave G4 — lightweight product analytics tracker.
///
/// Singleton facade so every screen / button can call
/// `Analytics.track(...)` without threading an instance through
/// constructors. Buffers events into a small in-memory queue and
/// flushes them in batches via `ApiClient.trackEvents`. Two flush
/// triggers:
///
///   1. timer-based: every `flushIntervalMs` (default 5s).
///   2. size-based: as soon as `flushAtCount` events accumulate
///      (default 10).
///
/// Flushing is best-effort. A failed batch (no auth attached, 4xx,
/// network blip) is simply dropped — analytics MUST NEVER block the
/// user. We accept the data loss in exchange for zero retry storms
/// and zero UI side effects.
///
/// Privacy: events carry the user_id from the access token (the
/// backend route picks it up via `requireAuth`); the client never
/// sends a raw user identifier. `metadata` is open-ended JSON; do
/// not put PII in it.
class Analytics {
  static const Duration _flushInterval = Duration(seconds: 5);
  static const int _flushAtCount = 10;
  static const int _maxQueueSize = 50;

  static ApiClient? _api;
  static final List<Map<String, dynamic>> _queue = [];
  static Timer? _flushTimer;
  static bool _isFlushing = false;

  /// Wire the tracker to the live `ApiClient`. Idempotent — calling
  /// it again with a different client just rebinds.
  static void bind(ApiClient api) {
    _api = api;
  }

  /// Drop the binding and clear the queue. Used on logout so a
  /// signed-out learner doesn't carry buffered events into the
  /// next sign-in.
  static void unbind() {
    _api = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _queue.clear();
  }

  /// Record a single event. `name` is freeform but the V1 surface
  /// uses two strings: `screen_view` and `button_click`. `screen`
  /// names the logical screen ('dashboard', 'exercise', 'summary',
  /// …). `metadata` carries anything else: button_id, skill_id,
  /// score, etc. Times are stamped with the local clock at call
  /// time — drift between client and server is acceptable for
  /// product analytics.
  static void track(
    String name, {
    String? screen,
    Map<String, dynamic>? metadata,
  }) {
    if (name.isEmpty) return;
    if (_queue.length >= _maxQueueSize) {
      // Hard cap: drop the oldest event so a runaway producer
      // can't blow memory.
      _queue.removeAt(0);
    }
    _queue.add({
      'name': name,
      if (screen != null) 'screen': screen,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (_queue.length >= _flushAtCount) {
      _flush();
    } else {
      _scheduleFlush();
    }
  }

  /// Convenience for the most common case — a screen view.
  static void trackScreen(String screen, {Map<String, dynamic>? metadata}) {
    track('screen_view', screen: screen, metadata: metadata);
  }

  /// Convenience for buttons — bundles `screen` and `button_id` into
  /// metadata so the dashboard query can group by surface + action.
  static void trackButton(
    String buttonId, {
    String? screen,
    Map<String, dynamic>? extra,
  }) {
    track(
      'button_click',
      screen: screen,
      metadata: {
        'button_id': buttonId,
        if (extra != null) ...extra,
      },
    );
  }

  /// Force flush. Used in tests and on screens that want to drain
  /// the queue before navigation.
  static Future<void> flushNow() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
  }

  static void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushInterval, _flush);
  }

  static Future<void> _flush() async {
    if (_isFlushing) return;
    final api = _api;
    if (api == null) return;
    if (_queue.isEmpty) return;
    _isFlushing = true;
    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();
    try {
      final ok = await api.trackEvents(batch);
      if (!ok) {
        // Drop the batch on failure. The alternative — pushing the
        // events back into the queue — risks an infinite retry loop
        // if the failure is permanent (e.g. auth not attached on a
        // pre-auth screen). Analytics is a nice-to-have, not a
        // contract.
      }
    } finally {
      _isFlushing = false;
    }
  }
}
