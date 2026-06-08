import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../l10n/app_strings.dart';

/// A single horizontal row of real card faces shown inside a reading section,
/// with an optional localized caption (e.g. a value total or a shape label).
///
/// The [cards] are rendered left-to-right with the active card theme so the
/// concept is taught with actual card faces, not just prose. The caption, when
/// present, is supplied as a localized string getter like every other piece of
/// panel copy.
class PracticeCardRow {
  /// Creates a card row.
  const PracticeCardRow({required this.cards, this.caption});

  /// Ordered cards rendered left to right.
  final List<HareegCard> cards;

  /// Optional localized caption shown beside the row (e.g. "10", "= 40").
  final String Function(AppStrings strings)? caption;
}

/// One section within a [PracticeReadingPanel].
///
/// A section may carry an optional bold heading, one or more body lines, and
/// one or more [cardRows] of real card faces. All copy is supplied as localized
/// string getters, never raw literals, so the panels honour the active
/// language; card faces themselves need no localization.
class PracticeReadingSection {
  /// Creates a reading-panel section.
  const PracticeReadingSection({
    this.heading,
    this.lines = const [],
    this.cardRows = const [],
  });

  /// Optional bold heading, or null for an unheaded paragraph.
  final String Function(AppStrings strings)? heading;

  /// Body lines rendered under the heading.
  final List<String Function(AppStrings strings)> lines;

  /// Card rows rendered under the body lines, each a row of real card faces.
  final List<PracticeCardRow> cardRows;
}

/// A conceptual reference panel: a localized title and a list of sections.
class PracticeReadingPanel {
  /// Creates a reading panel.
  const PracticeReadingPanel({required this.title, required this.sections});

  /// Localized panel title.
  final String Function(AppStrings strings) title;

  /// Ordered sections rendered top to bottom.
  final List<PracticeReadingSection> sections;
}

/// Content registry for the generic Fundamentals reading panels, keyed by the
/// stable catalog lesson id.
///
/// The bespoke `strictness-tiers` panel is intentionally absent: it keeps its
/// own [StrictnessExplainerScreen] with hand-built tier cards.
abstract final class PracticeReadingPanels {
  /// Lesson id → panel content, for the generic reading-panel screen.
  static final Map<String, PracticeReadingPanel> byLessonId = {
    'card-values': PracticeReadingPanel(
      title: _title,
      sections: [
        const PracticeReadingSection(
          lines: [_cardValuesIntro],
        ),
        PracticeReadingSection(
          heading: _cardValuesNumberHeading,
          lines: const [_cardValuesNumberLine],
          cardRows: [
            PracticeCardRow(cards: [_card(CardRank.two, CardSuit.clubs)],
                caption: _value2),
            PracticeCardRow(cards: [_card(CardRank.five, CardSuit.diamonds)],
                caption: _value5),
            PracticeCardRow(cards: [_card(CardRank.nine, CardSuit.spades)],
                caption: _value9),
          ],
        ),
        PracticeReadingSection(
          heading: _cardValuesFaceHeading,
          lines: const [_cardValuesFaceLine],
          cardRows: [
            PracticeCardRow(
              cards: [
                _card(CardRank.jack, CardSuit.clubs),
                _card(CardRank.queen, CardSuit.diamonds),
                _card(CardRank.king, CardSuit.spades),
                _card(CardRank.ace, CardSuit.hearts),
              ],
              caption: _value10Each,
            ),
          ],
        ),
        const PracticeReadingSection(
          lines: [_cardValuesOutro],
        ),
      ],
    ),
    'meld-shapes': PracticeReadingPanel(
      title: _meldShapesTitle,
      sections: [
        const PracticeReadingSection(
          lines: [_meldShapesIntro],
        ),
        PracticeReadingSection(
          heading: _meldShapesSetHeading,
          lines: const [_meldShapesSetLine],
          cardRows: [
            PracticeCardRow(
              cards: [
                _card(CardRank.seven, CardSuit.diamonds),
                _card(CardRank.seven, CardSuit.clubs),
                _card(CardRank.seven, CardSuit.hearts),
              ],
              caption: _meldShapesSetCaption,
            ),
          ],
        ),
        PracticeReadingSection(
          heading: _meldShapesRunHeading,
          lines: const [_meldShapesRunLine],
          cardRows: [
            PracticeCardRow(
              cards: [
                _card(CardRank.five, CardSuit.spades),
                _card(CardRank.six, CardSuit.spades),
                _card(CardRank.seven, CardSuit.spades),
              ],
              caption: _meldShapesRunCaption,
            ),
          ],
        ),
        const PracticeReadingSection(
          lines: [_meldShapesOutro],
        ),
      ],
    ),
    'the-ace': PracticeReadingPanel(
      title: _theAceTitle,
      sections: [
        const PracticeReadingSection(
          lines: [_theAceIntro],
        ),
        PracticeReadingSection(
          heading: _theAceHighHeading,
          lines: const [_theAceHighLine],
          cardRows: [
            PracticeCardRow(
              cards: [
                _card(CardRank.jack, CardSuit.clubs),
                _card(CardRank.queen, CardSuit.clubs),
                _card(CardRank.king, CardSuit.clubs),
                _card(CardRank.ace, CardSuit.clubs),
              ],
              caption: _theAceHighCaption,
            ),
          ],
        ),
        PracticeReadingSection(
          heading: _theAceLowHeading,
          lines: const [_theAceLowLine],
          cardRows: [
            PracticeCardRow(
              cards: [
                _card(CardRank.ace, CardSuit.spades),
                _card(CardRank.two, CardSuit.spades),
                _card(CardRank.three, CardSuit.spades),
                _card(CardRank.four, CardSuit.spades),
              ],
              caption: _theAceLowCaption,
            ),
          ],
        ),
        PracticeReadingSection(
          heading: _theAceFlipHeading,
          lines: const [_theAceFlipLine],
          cardRows: [
            PracticeCardRow(
              cards: [
                _card(CardRank.ace, CardSuit.spades),
                _card(CardRank.two, CardSuit.spades),
                _card(CardRank.three, CardSuit.spades),
                _card(CardRank.four, CardSuit.spades),
                _card(CardRank.five, CardSuit.spades),
              ],
              caption: _theAceFlipCaption,
            ),
          ],
        ),
        const PracticeReadingSection(
          lines: [_theAceOutro],
        ),
      ],
    ),
  };

  /// Looks up the panel content for [lessonId], or null when none is keyed.
  static PracticeReadingPanel? byId(String lessonId) => byLessonId[lessonId];

  /// Builds a standard demo card face. Reading panels are illustrative, so a
  /// fixed deck index is fine.
  static HareegCard _card(CardRank rank, CardSuit suit) =>
      HareegCard.standard(rank: rank, suit: suit, deckIndex: 0);

  // card-values
  static String _title(AppStrings s) => s.practiceCardValuesPanelTitle;
  static String _cardValuesIntro(AppStrings s) => s.practiceCardValuesIntro;
  static String _cardValuesNumberHeading(AppStrings s) =>
      s.practiceCardValuesNumberHeading;
  static String _cardValuesNumberLine(AppStrings s) =>
      s.practiceCardValuesNumberLine;
  static String _cardValuesFaceHeading(AppStrings s) =>
      s.practiceCardValuesFaceHeading;
  static String _cardValuesFaceLine(AppStrings s) =>
      s.practiceCardValuesFaceLine;
  static String _cardValuesOutro(AppStrings s) => s.practiceCardValuesOutro;
  static String _value2(AppStrings s) => s.practiceCardValue2;
  static String _value5(AppStrings s) => s.practiceCardValue5;
  static String _value9(AppStrings s) => s.practiceCardValue9;
  static String _value10Each(AppStrings s) => s.practiceCardValue10Each;

  // meld-shapes
  static String _meldShapesTitle(AppStrings s) => s.practiceMeldShapesPanelTitle;
  static String _meldShapesIntro(AppStrings s) => s.practiceMeldShapesIntro;
  static String _meldShapesSetHeading(AppStrings s) =>
      s.practiceMeldShapesSetHeading;
  static String _meldShapesSetLine(AppStrings s) => s.practiceMeldShapesSetLine;
  static String _meldShapesRunHeading(AppStrings s) =>
      s.practiceMeldShapesRunHeading;
  static String _meldShapesRunLine(AppStrings s) => s.practiceMeldShapesRunLine;
  static String _meldShapesOutro(AppStrings s) => s.practiceMeldShapesOutro;
  static String _meldShapesSetCaption(AppStrings s) =>
      s.practiceMeldShapesSetCaption;
  static String _meldShapesRunCaption(AppStrings s) =>
      s.practiceMeldShapesRunCaption;

  // the-ace
  static String _theAceTitle(AppStrings s) => s.practiceTheAcePanelTitle;
  static String _theAceIntro(AppStrings s) => s.practiceTheAceIntro;
  static String _theAceHighHeading(AppStrings s) => s.practiceTheAceHighHeading;
  static String _theAceHighLine(AppStrings s) => s.practiceTheAceHighLine;
  static String _theAceLowHeading(AppStrings s) => s.practiceTheAceLowHeading;
  static String _theAceLowLine(AppStrings s) => s.practiceTheAceLowLine;
  static String _theAceFlipHeading(AppStrings s) => s.practiceTheAceFlipHeading;
  static String _theAceFlipLine(AppStrings s) => s.practiceTheAceFlipLine;
  static String _theAceOutro(AppStrings s) => s.practiceTheAceOutro;
  static String _theAceHighCaption(AppStrings s) => s.practiceTheAceHighCaption;
  static String _theAceLowCaption(AppStrings s) => s.practiceTheAceLowCaption;
  static String _theAceFlipCaption(AppStrings s) => s.practiceTheAceFlipCaption;
}
