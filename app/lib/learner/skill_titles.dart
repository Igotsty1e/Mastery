/// V0 skill-title resolver per `docs/plans/wave4-transparency-layer.md
/// §2.2`. Embedded for the shipped B2 skills; new skills must be added
/// here in lockstep with `backend/data/skills.json` until a dedicated
/// `GET /skills` endpoint lands (deferred to a later wave).
///
/// Falls back to the raw `skill_id` when no title is registered, so a
/// missing entry degrades to a readable-enough label rather than a
/// crash. The Wave 4 panels show this fallback verbatim, which is the
/// signal the methodologist track owes a sync of this map.
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

String skillTitleFor(String skillId) =>
    _shippedSkillTitles[skillId] ?? skillId;
