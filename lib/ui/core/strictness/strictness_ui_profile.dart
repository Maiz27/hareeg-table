import '../../../domain/classic_hareeg/models/table_strictness.dart';
import '../cards/card_theme.dart';

/// Verbosity of the long-press card inspect overlay body.
enum InspectVerbosity {
  /// Coaching-style: includes guided phrasing and full context.
  coaching,

  /// Terse: card value and minimal facts, no learning prose.
  terse,
}

/// UI-layer derivations of [TableStrictness].
///
/// Lives in the UI layer because some derivations reference UI types
/// ([JokerDisplay], [Duration]) that the rules engine must never import.
/// Rules-relevant derivations live on [StrictnessRuleProfile] in the rules
/// layer.
extension StrictnessUiProfile on TableStrictness {
  /// Whether the table should surface proactive hint affordances (meld
  /// suggestions, opening guidance, etc.).
  ///
  /// Only [TableStrictness.coaching] shows proactive hints. Standard players
  /// still get rule validation but no unsolicited help.
  bool get showsProactiveHints => this == TableStrictness.coaching;

  /// Whether the long-press card inspect overlay surfaces the card's value.
  ///
  /// True in every tier except where hints are stripped to match real-table
  /// play — but since the inspect overlay is itself a deliberate gesture
  /// (long-press), all four tiers show card value. The previous "table mode
  /// hides value" behaviour is folded into the inspect-overlay-isn't-shown
  /// path rather than hiding value when shown.
  bool get showsCardValueInInspect => true;

  /// Tone and detail level used when generating inspect body text.
  InspectVerbosity get inspectVerbosity {
    return switch (this) {
      TableStrictness.coaching => InspectVerbosity.coaching,
      TableStrictness.standard ||
      TableStrictness.strict ||
      TableStrictness.table => InspectVerbosity.terse,
    };
  }

  /// Joker identity rendering mode used by [HareegCardView] / theme adapters.
  ///
  /// Coaching and Standard show the represented identity permanently
  /// ([JokerDisplay.assisted]). Strict and Table briefly reveal then quiet
  /// to plain joker ([JokerDisplay.memoryReveal]), forcing players to
  /// remember the declaration.
  JokerDisplay get jokerDisplay {
    return switch (this) {
      TableStrictness.coaching || TableStrictness.standard =>
        JokerDisplay.assisted,
      TableStrictness.strict || TableStrictness.table => JokerDisplay.memoryReveal,
    };
  }

  /// How long the joker identity badge stays visible after placement.
  ///
  /// Null means "persist forever" (Coaching/Standard). A finite duration
  /// means the badge fades in, holds for [Duration], then fades out and the
  /// card reverts to plain joker.
  Duration? get jokerCueDuration {
    return switch (this) {
      TableStrictness.coaching || TableStrictness.standard => null,
      TableStrictness.strict ||
      TableStrictness.table => const Duration(seconds: 3),
    };
  }

  /// Whether long-pressing a represented joker reveals its identity.
  ///
  /// Coaching and Standard keep the long-press helper. Strict and Table
  /// require the player to remember — long-press shows "Joker" only after
  /// the placement cue has faded.
  bool get longPressRevealsRepresented {
    return switch (this) {
      TableStrictness.coaching || TableStrictness.standard => true,
      TableStrictness.strict || TableStrictness.table => false,
    };
  }
}
