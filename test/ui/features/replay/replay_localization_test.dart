import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/cpu/classic_hareeg/coaching/review_insight.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_action.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/player_seat.dart';
import 'package:hareeg_table/domain/classic_hareeg/models/playing_card.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/features/replay/replay_viewer_view_state.dart';
import 'package:hareeg_table/domain/classic_hareeg/game/classic_hareeg_round.dart'
    show TurnPhase;
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';
import 'package:hareeg_table/ui/features/replay/review_insight_presenter.dart';

import '../../../scenario/classic_hareeg_scenario.dart';

/// Nothing a player reads may be an identifier.
///
/// Card ids, enum names and untranslated English are all storage or code
/// details; each of them reads as a bug in the product, and in Arabic an
/// English fallback reads as a missing translation.
void _readsLikeProse(String text, String where) {
  expect(text.trim(), isNotEmpty, reason: '$where is empty');
  expect(text, isNot(contains('deck-')), reason: '$where leaked a card id');
  expect(text, isNot(contains('_')), reason: '$where leaked an identifier');
  expect(
    RegExp(r'\b[a-z]+[A-Z]\w*\b').hasMatch(text),
    isFalse,
    reason: '$where leaked a camelCase enum name',
  );
}

final _ace = HareegCard.standard(
  rank: CardRank.ace,
  suit: CardSuit.hearts,
  deckIndex: 0,
);

const _catalogs = <String, AppStrings>{
  'english': AppStrings.english,
  'arabic': AppStrings.arabic,
};

ReviewInsightPresenter _presenter(AppStrings strings) =>
    ReviewInsightPresenter(strings: strings, cards: {_ace.id: _ace});

void main() {
  for (final entry in _catalogs.entries) {
    final label = entry.key;
    final catalog = entry.value;

    group('$label copy', () {
      test('every action kind reads as a sentence', () {
        final presenter = _presenter(catalog);

        for (final kind in ClassicHareegActionKind.values) {
          final line = presenter.describeAction(
            PlayerSeat.south,
            ClassicHareegActionDescriptor(
              id: 'discard:${_ace.id}',
              kind: kind,
              cardId: _ace.id,
              cardIds: [_ace.id],
            ),
          );
          _readsLikeProse(line, '$label action ${kind.name}');
        }
      });

      test('an action the app cannot classify still says something honest', () {
        final presenter = _presenter(catalog);
        final line = presenter.describeAction(
          PlayerSeat.east,
          ClassicHareegActionIds.describe('something-we-never-shipped'),
        );

        _readsLikeProse(line, '$label unknown action');
        // Not the raw id, and not silence either: the move did happen.
        expect(line, isNot(contains('something-we-never-shipped')));
      });

      test('every insight category reads as a sentence', () {
        final presenter = _presenter(catalog);

        for (final category in ReviewInsightCategory.values) {
          final insight = ReviewInsight(
            category: category,
            subjectSeat: PlayerSeat.east,
            cardIds: [_ace.id],
            evidence: [
              ReviewEvidence(
                kind: ReviewEvidenceKind.ownHand,
                seat: PlayerSeat.south,
                cardIds: [_ace.id],
                value: 2,
              ),
            ],
          );
          _readsLikeProse(
            presenter.sentenceFor(insight),
            '$label category ${category.name}',
          );
        }
      });

      test('every evidence kind reads as a sentence', () {
        final presenter = _presenter(catalog);

        for (final kind in ReviewEvidenceKind.values) {
          final insight = ReviewInsight(
            category: ReviewInsightCategory.safeDiscard,
            subjectSeat: PlayerSeat.east,
            evidence: [
              ReviewEvidence(
                kind: kind,
                seat: PlayerSeat.east,
                cardIds: [_ace.id],
                rankLabel: CardRank.ace.name,
                suitLabel: CardSuit.hearts.name,
                value: 2,
              ),
            ],
          );
          final lines = presenter.evidenceLines(insight);
          expect(lines, hasLength(1));
          _readsLikeProse(lines.single, '$label evidence ${kind.name}');
        }
      });

      test('every unavailable reason reads as a sentence', () {
        final presenter = _presenter(catalog);

        for (final reason in ReplayUnavailableReason.values) {
          _readsLikeProse(
            presenter.unavailableReason(reason),
            '$label reason ${reason.name}',
          );
        }
      });

      test('cards are named by rank and suit, never by id', () {
        final strings = catalog;
        final presenter = _presenter(catalog);
        final named = presenter.cardName(_ace.id);

        expect(named, isNotNull);
        expect(
          named,
          contains(strings.rankWord(CardRank.ace)),
          reason: '$label should name the rank',
        );
        expect(named, isNot(contains('deck-')));
      });

      test('a card the player could not see is not named at all', () {
        // Better to say less than to print an identifier for something the
        // reviewer had no way of seeing.
        final presenter = ReviewInsightPresenter(
          strings: catalog,
          cards: const {},
        );
        expect(presenter.cardName('deck-0-king-spades'), isNull);
      });
    });
  }

  test('the two languages actually differ', () {
    // A guard against the whole file passing because Arabic silently fell back
    // to English, which is exactly what AppStrings does for a missing key.
    final english = _presenter(AppStrings.english);
    final arabic = _presenter(AppStrings.arabic);

    for (final reason in ReplayUnavailableReason.values) {
      expect(
        arabic.unavailableReason(reason),
        isNot(english.unavailableReason(reason)),
        reason: 'reason ${reason.name} is not translated',
      );
    }

    for (final category in ReviewInsightCategory.values) {
      final insight = ReviewInsight(
        category: category,
        subjectSeat: PlayerSeat.east,
        cardIds: [_ace.id],
        evidence: [
          ReviewEvidence(
            kind: ReviewEvidenceKind.ownHand,
            cardIds: [_ace.id],
            value: 1,
          ),
        ],
      );
      expect(
        arabic.sentenceFor(insight),
        isNot(english.sentenceFor(insight)),
        reason: 'category ${category.name} is not translated',
      );
    }
  });

  group('a card taken from the pile is named, never guessed', () {
    // `take-discard` carries no card id — the action means "take whatever is on
    // top" — so the card has to come from the position it was taken from. An
    // earlier build fell back to "Joker", which narrated every ordinary pile
    // take as taking a Joker.
    final sevenOfClubs = HareegCard.standard(
      rank: CardRank.seven,
      suit: CardSuit.clubs,
      deckIndex: 0,
    );

    ({ReplayFrame previous, ReplayFrame applied}) frames() {
      final snapshot = ClassicHareegScenario.deal(
        discardPile: [sevenOfClubs],
        currentSeat: PlayerSeat.north,
      ).controller.toSnapshot(savedAt: replayClockEpoch);

      return (
        previous: ReplayFrame(
          index: 0,
          kind: ReplayFrameKind.initial,
          roundNumber: snapshot.roundNumber,
          snapshot: snapshot,
          clock: replayClockEpoch,
        ),
        applied: ReplayFrame(
          index: 1,
          kind: ReplayFrameKind.actionApplied,
          roundNumber: snapshot.roundNumber,
          snapshot: snapshot,
          clock: replayClockEpoch.add(const Duration(seconds: 1)),
          appliedEntry: MatchActionTranscriptEntry(
            order: 0,
            seat: PlayerSeat.north,
            roundNumber: snapshot.roundNumber,
            phase: TurnPhase.action,
            actionId: 'take-discard',
          ),
        ),
      );
    }

    for (final entry in _catalogs.entries) {
      test('${entry.key}: the real card is named, not a Joker', () {
        final catalog = entry.value;
        final pair = frames();
        final presenter = ReviewInsightPresenter.forFrame(
          strings: catalog,
          frame: pair.applied,
          previous: pair.previous,
        );

        final line = presenter.describeFrame(pair.applied);

        _readsLikeProse(line, '${entry.key} take-discard');
        expect(
          line,
          contains(catalog.rankWord(CardRank.seven)),
          reason: 'the seven that was actually on the pile must be named',
        );
        expect(
          line,
          isNot(contains(catalog.joker)),
          reason: 'an ordinary pile take is not a Joker take',
        );
      });
    }

    test('a card that genuinely cannot be identified is not invented', () {
      // With no pre-action position there is nothing to resolve from. Saying
      // "a card" is honest; naming a specific one would not be.
      final pair = frames();
      final presenter = ReviewInsightPresenter.forFrame(
        strings: AppStrings.english,
        frame: pair.applied,
      );

      final line = presenter.describeFrame(pair.applied);
      expect(line, contains(AppStrings.english.replayUnnamedCard));
      expect(line, isNot(contains(AppStrings.english.joker)));
    });
  });
}
