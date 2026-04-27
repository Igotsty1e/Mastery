import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_client.dart';
import 'learner_skill_store.dart';
import 'review_scheduler.dart';

/// Wave 7.4 part 2B — pushes the device-scoped learner state to the
/// auth-protected backend on first sign-in, then switches the
/// `LearnerSkillStore` and `ReviewScheduler` facades to their remote
/// backends.
///
/// The server's `/me/state/bulk-import` endpoint is idempotent: any
/// `(user, skill)` row that already exists server-side is preserved and
/// returned in the `skipped_*` arrays, so a second sign-in from a
/// different device that also has progress on the same account does
/// not clobber the first. The migrator therefore does not delete
/// anything locally — the local rows simply become inert once both
/// facades are pointed at the remote backend.
class LearnerStateMigrationResult {
  final List<String> importedSkills;
  final List<String> skippedSkills;
  final List<String> importedSchedules;
  final List<String> skippedSchedules;

  /// Set on a hard failure (network error, 4xx/5xx). The migrator does
  /// not throw — the caller logs and decides whether to flip the
  /// facades anyway. In V0 we flip to remote regardless: a signed-in
  /// learner expects their writes to land on the server even if the
  /// initial migration failed.
  final String? failureReason;

  const LearnerStateMigrationResult({
    required this.importedSkills,
    required this.skippedSkills,
    required this.importedSchedules,
    required this.skippedSchedules,
    this.failureReason,
  });

  bool get isFailure => failureReason != null;

  factory LearnerStateMigrationResult.fromResponse(
      Map<String, dynamic> body) {
    List<String> coerce(dynamic v) {
      if (v is! List) return const [];
      return v.whereType<String>().toList();
    }

    return LearnerStateMigrationResult(
      importedSkills: coerce(body['imported_skill_ids']),
      skippedSkills: coerce(body['skipped_skill_ids']),
      importedSchedules: coerce(body['imported_schedule_skill_ids']),
      skippedSchedules: coerce(body['skipped_schedule_skill_ids']),
    );
  }

  factory LearnerStateMigrationResult.failure(String reason) =>
      LearnerStateMigrationResult(
        importedSkills: const [],
        skippedSkills: const [],
        importedSchedules: const [],
        skippedSchedules: const [],
        failureReason: reason,
      );
}

class LearnerStateMigrator {
  final AuthClient authClient;
  final String baseUrl;

  /// Override hook for tests so a fake `LearnerSkillStore.allRecords` /
  /// `ReviewScheduler.all` source can drive the migration. Default
  /// reads via the static facades.
  final Future<List<LearnerSkillRecord>> Function()? skillsSource;
  final Future<List<ReviewSchedule>> Function()? schedulesSource;

  const LearnerStateMigrator({
    required this.authClient,
    required this.baseUrl,
    this.skillsSource,
    this.schedulesSource,
  });

  Future<LearnerStateMigrationResult> migrate() async {
    // Always read the local snapshot through a fresh local backend
    // instance — the static facade may already have been pointed at the
    // remote backend by an earlier sign-in attempt within the same
    // process. The local SharedPreferences keys are still around either
    // way (we never delete them in V0), so this gives us a clean source
    // of truth for the bulk import.
    final localSkills = LocalLearnerSkillBackend();
    final localSchedules = LocalReviewSchedulerBackend();
    final skills = await (skillsSource?.call() ?? localSkills.allRecords());
    final schedules =
        await (schedulesSource?.call() ?? localSchedules.all());

    if (skills.isEmpty && schedules.isEmpty) {
      // Nothing to migrate — first launch on this device after sign-in.
      // Still flip the facades to remote so subsequent writes hit the
      // server.
      _flipFacades();
      return const LearnerStateMigrationResult(
        importedSkills: [],
        skippedSkills: [],
        importedSchedules: [],
        skippedSchedules: [],
      );
    }

    final body = <String, dynamic>{
      'learner_skills': skills.map(_skillToPayload).toList(),
      'review_schedules': schedules.map(_scheduleToPayload).toList(),
    };

    http.Response resp;
    try {
      resp = await authClient.send(
        'POST',
        Uri.parse('$baseUrl/me/state/bulk-import'),
        body: body,
      );
    } catch (e) {
      _flipFacades();
      return LearnerStateMigrationResult.failure('network_$e');
    }

    if (resp.statusCode != 200) {
      _flipFacades();
      return LearnerStateMigrationResult.failure('http_${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      _flipFacades();
      return LearnerStateMigrationResult.failure('malformed_response');
    }

    _flipFacades();
    return LearnerStateMigrationResult.fromResponse(decoded);
  }

  void _flipFacades() {
    LearnerSkillStore.useRemote(authClient: authClient, baseUrl: baseUrl);
    ReviewScheduler.useRemote(authClient: authClient, baseUrl: baseUrl);
  }

  static Map<String, dynamic> _skillToPayload(LearnerSkillRecord r) {
    final j = r.toJson();
    j.remove('skill_id');
    return {
      'skill_id': r.skillId,
      ...j,
    };
  }

  static Map<String, dynamic> _scheduleToPayload(ReviewSchedule s) {
    final j = s.toJson();
    j.remove('skill_id');
    return {
      'skill_id': s.skillId,
      ...j,
    };
  }
}
