import 'skill_catalog.dart';

/// Skill-title resolver. Wave 12.7 made the [SkillCatalog] (fed by
/// `GET /skills`) the source of truth, but we keep this hardcoded
/// fallback table for two reasons:
///
/// 1. **First frame after cold launch.** The catalog is empty until
///    `HomeScreen` triggers `SkillCatalog.refresh()`; in those few
///    frames any `SkillStateCard` that reads a title would otherwise
///    flash the raw `skill_id`.
/// 2. **Offline / network failure.** `SkillCatalog.refresh()` swallows
///    fetch errors and leaves the cache stale; the fallback keeps
///    titles readable.
///
/// New skills should be added here in lockstep with
/// `backend/data/skills.json` so the cold-start UX never shows raw
/// `skill_id`. The catalog still wins when populated.
const Map<String, String> _shippedSkillTitles = {
  'verb-ing-after-gerund-verbs': 'Verbs followed by -ing',
  'verb-to-inf-after-aspirational-verbs':
      'Verbs followed by to + infinitive',
  'verb-both-forms-meaning-change':
      'Verbs with a change in meaning: -ing vs to + infinitive',
  'verb-both-forms-little-change':
      'Verbs with both forms: little or no change',
  'present-perfect-continuous-vs-simple':
      'Present perfect continuous vs simple',
};

String skillTitleFor(String skillId) {
  final catalog = SkillCatalog.instance.entryFor(skillId);
  if (catalog != null) return catalog.title;
  return _shippedSkillTitles[skillId] ?? skillId;
}
