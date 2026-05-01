// Wave H1 — rule card data model.
//
// Plain data classes parsed from the `rule_card` JSON object on a
// Lesson / SkillCatalogEntry / SkillRuleSnapshot. The textbook-style
// rendering lives in `app/lib/widgets/rule_card.dart` (`RuleCardView`).
// Schema: `docs/content-contract.md §1.2`.

class RuleCardExample {
  final String text;
  final String? highlight;

  const RuleCardExample({required this.text, this.highlight});

  factory RuleCardExample.fromJson(Map<String, dynamic> j) => RuleCardExample(
        text: j['text'] as String,
        highlight: j['highlight'] as String?,
      );
}

class RuleCardPatternList {
  final String label;
  final List<String> items;

  const RuleCardPatternList({required this.label, required this.items});

  factory RuleCardPatternList.fromJson(Map<String, dynamic> j) =>
      RuleCardPatternList(
        label: j['label'] as String,
        items: (j['items'] as List)
            .map((e) => e.toString())
            .toList(growable: false),
      );
}

class RuleCardWatchOut {
  final String text;
  final String? example;
  final String? highlight;

  const RuleCardWatchOut({required this.text, this.example, this.highlight});

  factory RuleCardWatchOut.fromJson(Map<String, dynamic> j) => RuleCardWatchOut(
        text: j['text'] as String,
        example: j['example'] as String?,
        highlight: j['highlight'] as String?,
      );
}

class RuleCardData {
  final String title;
  final String rule;
  final List<RuleCardExample> examples;
  final List<RuleCardPatternList> patternLists;
  final List<RuleCardWatchOut> watchOuts;

  const RuleCardData({
    required this.title,
    required this.rule,
    required this.examples,
    required this.patternLists,
    required this.watchOuts,
  });

  factory RuleCardData.fromJson(Map<String, dynamic> j) => RuleCardData(
        title: j['title'] as String,
        rule: j['rule'] as String,
        examples: (j['examples'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RuleCardExample.fromJson)
            .toList(growable: false),
        patternLists: (j['pattern_lists'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RuleCardPatternList.fromJson)
            .toList(growable: false),
        watchOuts: (j['watch_outs'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RuleCardWatchOut.fromJson)
            .toList(growable: false),
      );

  static RuleCardData? maybeFromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return RuleCardData.fromJson(j);
  }
}
