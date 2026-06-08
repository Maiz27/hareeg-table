import '../practice/practice_lesson_script.dart';

/// How a practice lesson is delivered to the player.
enum PracticeLessonDeliveryKind {
  /// A deterministic lesson script hosted by the real table in practice mode.
  scriptedTable,

  /// A reading panel that completes from its own screen.
  readingPanel,

  /// A catalog lesson whose delivery is not registered.
  unavailable,
}

/// Delivery description for one practice lesson.
class PracticeLessonDelivery {
  const PracticeLessonDelivery._({
    required this.kind,
    PracticeLessonScript Function()? buildScript,
  }) : _buildScript = buildScript;

  /// Scripted table lesson delivery.
  const PracticeLessonDelivery.scriptedTable(
    PracticeLessonScript Function() buildScript,
  ) : this._(
        kind: PracticeLessonDeliveryKind.scriptedTable,
        buildScript: buildScript,
      );

  /// Reading-panel lesson delivery.
  const PracticeLessonDelivery.readingPanel()
    : this._(kind: PracticeLessonDeliveryKind.readingPanel);

  /// Missing delivery.
  const PracticeLessonDelivery.unavailable()
    : this._(kind: PracticeLessonDeliveryKind.unavailable);

  /// Delivery kind.
  final PracticeLessonDeliveryKind kind;

  final PracticeLessonScript Function()? _buildScript;

  /// Whether this lesson can be opened by the player.
  bool get isAvailable => kind != PracticeLessonDeliveryKind.unavailable;

  /// Whether this lesson should route to the strictness reading panel.
  bool get isReadingPanel => kind == PracticeLessonDeliveryKind.readingPanel;

  /// Builds the table script, if this delivery is scripted.
  PracticeLessonScript? buildScript() => _buildScript?.call();
}
