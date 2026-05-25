/// Shared JSON coercion primitives and a schema-version dispatcher used by
/// every domain model that persists itself.
///
/// Before this module existed, every persistable model shipped its own
/// private copy of `_asInt`/`_asMap`/`_asList`/`_asString` — six near-
/// identical implementations whose drift potential outweighed the cost of a
/// single shared helper module. Architecture review NEW #2 (2026-05-25)
/// flagged the duplication; consolidating here keeps the rules engine
/// Flutter-free (ADR-0001) while eliminating the copies.
///
/// The dispatcher entry-points ([decodeWithSchemaVersion],
/// [migrateLegacyMap]) carry the schema-evolution logic — readers ask for a
/// decoded value and the codec routes through legacy migration steps before
/// handing the cleaned map to the current decoder. New schema versions plug
/// in by adding a named migration step.
library;

/// Coerces a dynamic JSON value into a `Map<String, Object?>` when possible.
///
/// Returns `null` for non-map values so callers can distinguish a missing
/// field from an invalid one. String-keyed entries in the source map are
/// preserved; non-string keys are dropped silently because persisted JSON
/// can only have produced string keys legally.
Map<String, Object?>? asJsonMap(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  return null;
}

/// Coerces a dynamic JSON value into a `List<Object?>` when possible.
///
/// Returns `null` for non-list values so callers can distinguish "missing
/// list" from "empty list" and from "wrong shape".
List<Object?>? asJsonList(Object? value) {
  if (value is List) {
    return value;
  }

  return null;
}

/// Coerces a dynamic JSON value into an `int` when possible.
///
/// Accepts:
/// - native `int`
/// - finite whole-number `num` (handles older JSON encoders that wrote ints
///   as floats)
/// - decimal `String` (defends against legacy preference blobs)
///
/// Returns `null` for any other shape so callers can fall back to defaults.
int? asJsonInt(Object? value) {
  return switch (value) {
    int() => value,
    num() when value.isFinite && value % 1 == 0 => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };
}

/// Coerces a dynamic JSON value into a `String` when possible.
///
/// Returns `null` for any non-string value so callers can branch on missing
/// versus invalid.
String? asJsonString(Object? value) {
  return value is String ? value : null;
}

/// Coerces a dynamic JSON value into a `bool` when possible.
///
/// Returns `null` for any non-bool value.
bool? asJsonBool(Object? value) {
  return value is bool ? value : null;
}

/// Named migration step applied to a legacy JSON map before the current
/// decoder runs.
///
/// Each step inspects the map, optionally mutates a copy, and returns the
/// upgraded map plus a flag indicating whether it actually changed shape.
/// The flag exists so the dispatcher can log/trace which migrations fired
/// without re-comparing maps.
class JsonMigrationStep {
  /// Creates a migration step.
  const JsonMigrationStep({required this.name, required this.apply});

  /// Stable identifier used in diagnostics and tests.
  final String name;

  /// Migration transformation. Implementations should return the original
  /// map when no migration applies, or a new map with the upgraded shape.
  final Map<String, Object?> Function(Map<String, Object?> source) apply;
}

/// Runs [steps] in order over [source], returning the upgraded map.
///
/// Steps are applied unconditionally — each step is responsible for being a
/// no-op when its trigger isn't present. This matches the existing legacy-
/// `tableStrictness` migration shape and keeps the dispatcher simple.
Map<String, Object?> migrateLegacyMap(
  Map<String, Object?> source, {
  required List<JsonMigrationStep> steps,
}) {
  var current = source;
  for (final step in steps) {
    current = step.apply(current);
  }
  return current;
}

/// Dispatches a JSON map to the right decoder based on its embedded
/// `version` field.
///
/// [decoders] is keyed by schema version; legacy maps without a `version`
/// field fall back to [fallbackVersion] when provided. Migrations run
/// before version detection so legacy maps can be normalized to a known
/// shape first.
///
/// Throws [FormatException] when no decoder is registered for the version
/// found in the map, or when neither a version nor a fallback is available.
T decodeWithSchemaVersion<T>(
  Map<String, Object?> source, {
  required Map<int, T Function(Map<String, Object?> json)> decoders,
  int? fallbackVersion,
  List<JsonMigrationStep> migrations = const [],
}) {
  final migrated = migrations.isEmpty
      ? source
      : migrateLegacyMap(source, steps: migrations);
  final declared = asJsonInt(migrated['version']);
  final version = declared ?? fallbackVersion;
  if (version == null) {
    throw const FormatException('Missing schema version.');
  }
  final decoder = decoders[version];
  if (decoder == null) {
    throw FormatException('Unsupported schema version $version.');
  }
  return decoder(migrated);
}
