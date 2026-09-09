import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/ui/features/history/match_statistics_format.dart';

void main() {
  group('percent', () {
    test('one third renders to one decimal, never the raw double', () {
      final text = MatchStatisticsFormat.percent(1 / 3);

      expect(text, '33.3%');
      expect(text, isNot(contains('33.33333')));
    });

    test('whole values still carry their decimal', () {
      expect(MatchStatisticsFormat.percent(1.0), '100.0%');
      expect(MatchStatisticsFormat.percent(0.0), '0.0%');
      expect(MatchStatisticsFormat.percent(0.5), '50.0%');
    });

    test('null renders unavailable rather than zero', () {
      // A rate with no denominator is not a rate of zero.
      expect(MatchStatisticsFormat.percent(null), MatchStatisticsFormat.unavailable);
      expect(MatchStatisticsFormat.percent(null), isNot(contains('0')));
    });
  });

  group('average', () {
    test('renders one decimal without a percent sign', () {
      expect(MatchStatisticsFormat.average(2.25), '2.3');
      expect(MatchStatisticsFormat.average(2.0), '2.0');
      expect(MatchStatisticsFormat.average(7 / 3), '2.3');
      expect(MatchStatisticsFormat.average(2.0), isNot(contains('%')));
    });

    test('null renders unavailable', () {
      expect(
        MatchStatisticsFormat.average(null),
        MatchStatisticsFormat.unavailable,
      );
    });
  });

  group('signedMargin', () {
    test('a favourable margin carries an explicit plus', () {
      expect(MatchStatisticsFormat.signedMargin(4.5), '+4.5');
      expect(MatchStatisticsFormat.signedMargin(1 / 3), '+0.3');
    });

    test('an unfavourable margin carries a minus', () {
      expect(MatchStatisticsFormat.signedMargin(-4.5), '-4.5');
    });

    test('zero carries no sign', () {
      // "+0.0" would imply a slight edge that is not there.
      expect(MatchStatisticsFormat.signedMargin(0), '0.0');
    });

    test('a negative value that rounds to zero does not render as -0.0', () {
      expect(MatchStatisticsFormat.signedMargin(-0.04), '0.0');
    });

    test('null renders unavailable', () {
      expect(
        MatchStatisticsFormat.signedMargin(null),
        MatchStatisticsFormat.unavailable,
      );
    });
  });

  test('a non-finite value renders unavailable, never NaN or Infinity', () {
    // These cannot arise from the domain layer, where every metric is a ratio
    // of ints behind a zero-denominator guard. They are rejected here anyway
    // because `toStringAsFixed` renders both literally, so a future caller
    // cannot introduce "NaN%" into the UI through this seam.
    for (final value in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        MatchStatisticsFormat.percent(value),
        MatchStatisticsFormat.unavailable,
      );
      expect(
        MatchStatisticsFormat.average(value),
        MatchStatisticsFormat.unavailable,
      );
      expect(
        MatchStatisticsFormat.signedMargin(value),
        MatchStatisticsFormat.unavailable,
      );
    }
  });
}
