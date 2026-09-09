/// Number formatting for every displayed statistic.
///
/// Pure and Flutter-free so the rules can be tested without a widget, and so
/// there is exactly one place where a `double` becomes text. A screen that
/// formats its own doubles is how `0.3333333333333333` reaches a player.
///
/// Digits are locale-independent here: the app renders Western digits in both
/// languages (see `AppStrings.decksValue`), so only the surrounding labels are
/// localized, not the numerals.
abstract final class MatchStatisticsFormat {
  /// Decimal places shown for every statistic.
  static const decimals = 1;

  /// Rendered in place of a statistic that has no value.
  ///
  /// An unavailable rate is not zero, so it must not render as `0.0%`.
  static const unavailable = '—';

  /// Formats a 0-to-1 [rate] as a percentage, or [unavailable] when null.
  ///
  /// `1 / 3` renders `33.3%`, never `33.33333333333333%`.
  static String percent(double? rate) {
    if (!_isPresentable(rate)) {
      return unavailable;
    }
    return '${_fixed(rate! * 100)}%';
  }

  /// Formats an [average] to one decimal, or [unavailable] when null.
  static String average(double? average) {
    if (!_isPresentable(average)) {
      return unavailable;
    }
    return _fixed(average!);
  }

  /// Formats a scoring [margin] with an explicit sign, or [unavailable].
  ///
  /// A positive margin favours the player. The sign is meaningless without
  /// that statement, so the caller must render this beside a label saying so.
  static String signedMargin(double? margin) {
    if (!_isPresentable(margin)) {
      return unavailable;
    }

    final text = _fixed(margin!);
    if (text.startsWith('-')) {
      return text;
    }
    // Zero carries no sign: "+0.0" would imply a slight edge that is not there.
    return _isZero(text) ? text : '+$text';
  }

  /// Formats a plain count.
  static String count(int value) => '$value';

  /// Whether [value] can be turned into a number a player should read.
  ///
  /// A non-finite value cannot reach here from the domain layer — every metric
  /// is a ratio of ints behind a zero-denominator guard — but `NaN` and
  /// `Infinity` both survive `toStringAsFixed` and would render literally.
  /// Treating them as unavailable keeps that impossible.
  static bool _isPresentable(double? value) => value != null && value.isFinite;

  static String _fixed(double value) {
    final text = value.toStringAsFixed(decimals);
    // `(-0.04).toStringAsFixed(1)` is "-0.0". A negative zero is a rounding
    // artefact, not a result, and rendering it would read as a loss.
    return _isZero(text) ? 0.toStringAsFixed(decimals) : text;
  }

  static bool _isZero(String fixed) {
    return double.parse(fixed) == 0;
  }
}
