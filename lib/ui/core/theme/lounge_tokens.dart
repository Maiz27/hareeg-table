import 'package:flutter/material.dart';

/// Warm Sudanese Lounge design tokens.
///
/// One place for palette, spacing, touch targets, typography, and motion
/// constants used across the table, menus, cards, overlays, and splash. The
/// canonical palette source is `docs/design/direction.md`; new colours should
/// be added to both this file and the design doc.
abstract final class LoungeTokens {
  // -- Palette --------------------------------------------------------------

  /// Primary table surface colour.
  static const feltGreen = Color(0xFF12382F);

  /// Deeper edge tone used for table chrome and menu backgrounds.
  static const coffeeCharcoal = Color(0xFF15110E);

  /// Default card face base.
  static const cardIvory = Color(0xFFF8F0DD);

  /// Sand-coloured hairlines and motif strokes.
  static const sandLine = Color(0xFFD7BD83);

  /// Primary accent for buttons, opening progress, and active controls.
  static const goldAccent = Color(0xFFD69B35);

  /// Fifty / Khamsin heat.
  static const fiftyFlame = Color(0xFFEF5A24);

  /// Deep red used for warnings, illegal-action states, and the heart suit.
  static const deepRed = Color(0xFFA92E24);

  /// Cool accent used sparingly for opponent badges and inactive seats.
  static const indigoAccent = Color(0xFF23395B);

  /// Off-white body text on dark surfaces.
  static const offWhiteText = Color(0xFFF5EFE3);

  /// Muted text on dark surfaces.
  static const mutedText = Color(0xFFB8AA91);

  // -- Derived surface tones ------------------------------------------------

  /// Slightly raised felt for chips, banners, and inset panels.
  static const feltRaised = Color(0xFF184235);

  /// Felt tone used behind cards (a touch lighter for contrast).
  static const feltSpotlight = Color(0xFF1B4A3C);

  /// Background for sheets / overlays sitting above the table.
  static const overlayScrim = Color(0xCC0B0A08);

  /// Soft glow for selected card outlines.
  static const selectedGlow = Color(0x66D69B35);

  /// Cover-target tinted ring around legal drop zones.
  static const coverTargetTint = Color(0x33D69B35);

  /// Pending-discard amber border, slightly brighter than goldAccent.
  static const pendingDiscard = Color(0xFFE0A848);

  /// Invalid action red, tuned for ring/border use.
  static const invalidAction = Color(0xFFE07466);

  /// Coach highlight ring — a reserved cool teal used only by the coaching
  /// tier's proactive hints. Deliberately distinct from selection/cover
  /// (gold), pending (amber), invalid (red), and Fifty (flame) so a coached
  /// card never reads as any other state. Drawn as an outline + glow ring
  /// (never a face tint) so it stays legible across every card theme.
  static const coachHighlight = Color(0xFF2FB4A6);

  /// Soft outer glow for the coach highlight ring.
  static const coachGlow = Color(0x662FB4A6);

  /// Secondary coach ring hues, used to tell apart the distinct melds a single
  /// opening / finish hint points at. All cool and clearly separable from
  /// gold / amber / red / flame, so each meld group reads as its own ring.
  static const coachHighlightB = Color(0xFF4FA8E0);
  static const coachHighlightC = Color(0xFFB07BE6);

  /// Coach ring palette indexed by meld-group. Group 0 is the reserved teal.
  static const coachRingPalette = [
    coachHighlight,
    coachHighlightB,
    coachHighlightC,
  ];

  /// Coach "let this go" ring — a warm rose used only to mark the single card a
  /// proactive hint recommends discarding, so it reads as the opposite of the
  /// cool teal/blue/violet "keep these" rings sharing the same hint. Distinct
  /// from gold (selection), amber (pending), red (invalid), and flame (Fifty).
  static const coachDiscard = Color(0xFFDC6FA0);

  /// Eliminated seat overlay tint.
  static const eliminatedDim = Color(0xAA0B0A08);

  // -- Spacing scale --------------------------------------------------------

  /// 4 dp base spacing unit.
  static const spaceUnit = 4.0;

  /// 4 dp.
  static const space1 = spaceUnit;

  /// 8 dp.
  static const space2 = spaceUnit * 2;

  /// 12 dp.
  static const space3 = spaceUnit * 3;

  /// 16 dp.
  static const space4 = spaceUnit * 4;

  /// 20 dp.
  static const space5 = spaceUnit * 5;

  /// 24 dp.
  static const space6 = spaceUnit * 6;

  /// 32 dp.
  static const space8 = spaceUnit * 8;

  // -- Radii ----------------------------------------------------------------

  /// Card / chip corner radius.
  static const radiusCard = 10.0;

  /// Standard panel corner radius (overlays, sheets).
  static const radiusPanel = 18.0;

  /// Button corner radius.
  static const radiusButton = 12.0;

  // -- Touch targets --------------------------------------------------------

  /// Minimum tap target for primary buttons and icon-only buttons.
  static const tapTargetPrimary = 48.0;

  /// Tap target short edge for cards in the hand, picker, discard, and stock.
  static const tapTargetCardShort = 44.0;

  /// Opponent compact meld cover target (visible portion).
  static const tapTargetCompactCover = 36.0;

  /// Joker replacement / cover drop overlay (visible).
  static const tapTargetOverlay = 40.0;

  // -- Typography (token text styles, applied via AppTheme.dark()) ----------

  /// Display style used for the splash wordmark and major screen titles.
  static const display = TextStyle(
    color: offWhiteText,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
  );

  /// Section heading on menus and panels.
  static const heading = TextStyle(
    color: offWhiteText,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  /// Title used in chips, banners, and seat labels.
  static const titleSmall = TextStyle(
    color: offWhiteText,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  /// Body copy.
  static const body = TextStyle(color: offWhiteText, fontSize: 14);

  /// Secondary / muted body copy.
  static const bodyMuted = TextStyle(color: mutedText, fontSize: 13);

  /// Numeric label used on the central card glyphs and chip counters.
  static const numericChip = TextStyle(
    color: offWhiteText,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    letterSpacing: 0.4,
  );
}

/// Suit / card surface colours so themes can share a single tint set.
abstract final class CardSuitColors {
  /// Red suits (hearts, diamonds).
  static const red = LoungeTokens.deepRed;

  /// Black suits (spades, clubs) — coffee charcoal reads softer than pure
  /// black against ivory.
  static const black = LoungeTokens.coffeeCharcoal;

  /// Joker accent.
  static const joker = LoungeTokens.fiftyFlame;
}
