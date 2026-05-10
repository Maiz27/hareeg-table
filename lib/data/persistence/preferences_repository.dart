/// Storage boundary for local user preferences.
///
/// Concrete implementations may use platform storage later, but callers should
/// depend on this pure interface.
abstract interface class PreferencesRepository {
  /// Loads the user's preferred rules preset identifier, if one was saved.
  Future<String?> loadPreferredRulePresetId();

  /// Persists the user's preferred rules preset identifier.
  Future<void> savePreferredRulePresetId(String presetId);
}
