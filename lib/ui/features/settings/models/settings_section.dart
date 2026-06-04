/// Named accordion sections on the Settings screen.
///
/// Used both for rendering and for deep-linking from the Start screen so the
/// user lands on the section they tapped through to.
enum SettingsSection {
  /// House rules left over from the Start screen (deck count, fifty timer).
  tableRules,

  /// Initial sort mode applied to the human hand at the start of each round.
  handSort,

  /// Strictness and coaching-tip controls.
  assistance,

  /// Visual identity: card theme and table surface.
  look,

  /// Sensory feedback: motion speed, haptics, sound.
  feel,

  /// Language selection.
  language,
}

/// Navigation arguments accepted by the Settings route.
class SettingsRouteArguments {
  /// Creates Settings arguments.
  const SettingsRouteArguments({this.initialSection});

  /// Section to expand on first frame. Null leaves every section collapsed.
  final SettingsSection? initialSection;
}
