import 'package:flutter/material.dart';

import 'brand_palette.dart';

/// Hareeg Table design tokens.
///
/// One place for the colour roles, spacing, touch targets, typography and
/// motion constants used across the table, menus, cards, overlays and splash.
///
/// Colours are **roles**, not hues: a widget asks for `accent`, `surface` or
/// `stateSelected`, never for "ember" or "sand". The hues behind the roles
/// live in [BrandPalette], the only file that holds a hex value, so a palette
/// change is one edit there and a role that should move to a different hue is
/// one line here. Feature code never references [BrandPalette] directly
/// (`test/lint/design_token_ratchet_test.dart` enforces both rules).
///
/// The canonical description of each role is
/// `docs/design/design-contract.md` section 3.
abstract final class LoungeTokens {
  // -- Surfaces -------------------------------------------------------------

  /// The ground: scaffold, menus, screen headers, the splash.
  static const surface = BrandPalette.charcoal;

  /// Lifted one step: raised chips, banners, inset panels on [surface].
  static const surfaceRaised = BrandPalette.charcoalRaised;

  /// Lifted two steps: the pool behind cards and lit medallions on [surface].
  static const surfaceSpotlight = BrandPalette.charcoalSpotlight;

  /// Sunk one step: recessed fills, progress tracks, inset trays on [surface].
  static const surfaceInset = BrandPalette.charcoalDeep;

  /// L3 panel fill: sheets, pause, score, the coach card.
  static const panel = BrandPalette.charcoalRaised;

  /// L2 panel fill, slightly translucent over the table.
  static const panelTranslucent = Color(0xE015110E);

  /// Scrim behind sheets and overlays sitting above the table.
  static const scrim = Color(0xCC0B0A08);

  /// Light surface: paper panels, the light brand pairing.
  static const paper = BrandPalette.ivory;

  // -- The table ------------------------------------------------------------

  /// The playing surface. Felt is for the table only; menus sit on [surface].
  static const tableFelt = BrandPalette.felt;

  /// Raised felt: meld lanes, inset panels on the table.
  static const tableFeltRaised = BrandPalette.feltRaised;

  /// Felt spotlight: the lighter pool behind on-table cards.
  static const tableFeltSpotlight = BrandPalette.feltSpotlight;

  /// Default card face base.
  static const cardFace = BrandPalette.ivory;

  // -- Accent ---------------------------------------------------------------

  /// Primary action: filled buttons, active controls, progress, the lamp.
  static const accent = BrandPalette.ember;

  /// [accent] pressed or deepened; the dark end of a lit gradient.
  static const accentPressed = BrandPalette.emberDeep;

  /// [accent] caught by the light; the bright end of a lit gradient.
  static const accentBright = BrandPalette.emberBright;

  /// Text and icons on [accent].
  static const onAccent = BrandPalette.charcoal;

  /// Soft outer glow for accent rings and lit medallions.
  static const accentGlow = Color(0x66E4522B);

  // -- Lines and text -------------------------------------------------------

  /// Hairlines, motif strokes, secondary borders.
  static const line = BrandPalette.sand;

  /// Hairline edge for L2 surfaces (40 % [line]).
  static const lineSoft = Color(0x40D7BD83);

  /// Primary text on dark surfaces.
  static const textPrimary = BrandPalette.offWhite;

  /// Secondary text on dark surfaces.
  static const textMuted = BrandPalette.stone;

  /// Text on [paper] and [cardFace].
  static const textOnPaper = BrandPalette.charcoal;

  // -- States (reserved meanings; design contract section 3.3) --------------

  /// The player picked this: hand cards, chosen controls, legal drop zones.
  /// Quiet sand, so the flame stays reserved for fire.
  static const stateSelected = BrandPalette.sand;

  /// Soft glow for selected card outlines.
  static const stateSelectedGlow = Color(0x66D7BD83);

  /// Will leave the hand on confirm.
  static const statePending = BrandPalette.amber;

  /// Rejected action, tuned for ring and border use.
  static const stateInvalid = BrandPalette.rose;

  /// Fifty / Khamsin heat. The brand flame: Fifty moments and danger scores.
  static const fiftyHeat = BrandPalette.ember;

  /// The white-hot core of the Fifty flame: the stamp's top edge, the first
  /// shockwave ring, freshly thrown embers before they cool.
  static const fiftyHeatCore = BrandPalette.flameCore;

  /// A decorative cool spark for celebrations only. Not a state: the coach
  /// hues are reserved and [seatCool] is too dark on [surface].
  static const celebrationCool = BrandPalette.lagoon;

  /// Danger: warnings, elimination, illegal-action copy.
  static const danger = BrandPalette.crimson;

  /// Hearts and diamonds on the default card faces.
  static const suitRed = BrandPalette.crimson;

  /// Cool accent for opponent badges and inactive seats; the west seat.
  static const seatCool = BrandPalette.indigo;

  /// The east seat's identity hue, a second cool told apart from [seatCool].
  static const seatEast = BrandPalette.slate;

  /// Coach highlight ring — a reserved cool teal used only by the coaching
  /// tier's proactive hints. Deliberately distinct from selection (sand),
  /// pending (amber), invalid (rose) and Fifty (ember) so a coached card never
  /// reads as any other state. Drawn as an outline + glow ring (never a face
  /// tint) so it stays legible across every card theme.
  static const coachHighlight = BrandPalette.teal;

  /// Soft outer glow for the coach highlight ring.
  static const coachGlow = Color(0x662FB4A6);

  /// Secondary coach ring hues, used to tell apart the distinct melds a single
  /// opening / finish hint points at. All cool and clearly separable from the
  /// warm states, so each meld group reads as its own ring.
  static const coachHighlightB = BrandPalette.sky;
  static const coachHighlightC = BrandPalette.violet;

  /// Coach ring palette indexed by meld-group. Group 0 is the reserved teal.
  static const coachRingPalette = [
    coachHighlight,
    coachHighlightB,
    coachHighlightC,
  ];

  /// Coach "let this go" ring — a warm rose used only to mark the single card
  /// a proactive hint recommends discarding, so it reads as the opposite of
  /// the cool "keep these" rings sharing the same hint.
  static const coachDiscard = BrandPalette.orchid;

  // -- High-contrast states (the accessibility setting) ---------------------
  // Overlay-only: they sit above the card theme and replace the brand states
  // when "High-contrast cues" is on. Saturated by design.

  /// Selected card outline, and the panel edge, under high contrast.
  static const highContrastSelected = BrandPalette.signalYellow;
  static const highContrastSelectedGlow = Color(0xCCFFD400);

  /// Pending card under high contrast.
  static const highContrastPending = BrandPalette.signalOrange;
  static const highContrastPendingGlow = Color(0xCCFF6F00);
  static const highContrastPendingTint = Color(0x33FF6F00);

  /// Cover target under high contrast.
  static const highContrastCover = BrandPalette.signalCyan;
  static const highContrastCoverGlow = Color(0xCC00D9FF);
  static const highContrastCoverTint = Color(0x3300D9FF);

  /// Coach ring under high contrast (outline mint, glow the reserved teal).
  static const highContrastCoach = BrandPalette.signalMint;
  static const highContrastCoachGlow = Color(0xCC2FB4A6);

  /// Invalid under high contrast.
  static const highContrastInvalid = BrandPalette.signalRed;

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

  /// Pill radius for HUD chips and seat plates.
  static const radiusPill = 999.0;

  // -- Touch targets --------------------------------------------------------

  /// Minimum tap target for primary buttons and icon-only buttons.
  static const tapTargetPrimary = 48.0;

  /// Tap target short edge for cards in the hand, picker, discard, and stock.
  static const tapTargetCardShort = 44.0;

  // -- Typography (docs/design/design-contract.md section 4) -----------------

  /// Display family: geometric Kufic with Latin and Arabic coverage. Used for
  /// the wordmark, screen titles, big scores, and Fifty moments.
  static const displayFamily = 'ReemKufi';

  /// UI / body family: Latin and Arabic, legible at small sizes.
  static const uiFamily = 'IBMPlexSansArabic';

  /// Reem Kufi ships as a variable font; weights are set on the `wght` axis.
  static List<FontVariation> displayWeight(double weight) => [
    FontVariation('wght', weight),
  ];

  /// Large display used for the home wordmark and match results.
  static final displayLarge = TextStyle(
    fontFamily: displayFamily,
    color: textPrimary,
    fontSize: 40,
    fontWeight: FontWeight.w700,
    fontVariations: displayWeight(700),
    height: 1.1,
    letterSpacing: 0.2,
  );

  /// Display style used for the splash wordmark and major screen titles.
  static final display = TextStyle(
    fontFamily: displayFamily,
    color: textPrimary,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    fontVariations: displayWeight(700),
    height: 1.15,
    letterSpacing: 0.3,
  );

  /// Section heading on menus and panels.
  static const heading = TextStyle(
    fontFamily: uiFamily,
    color: textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: 0.1,
  );

  /// List rows, seat names, and button labels.
  static const title = TextStyle(
    fontFamily: uiFamily,
    color: textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.2,
  );

  /// Title used in chips, banners, and seat labels.
  static const titleSmall = TextStyle(
    fontFamily: uiFamily,
    color: textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.6,
  );

  /// Small uppercase overline above a section or inside a seat plate.
  static const overline = TextStyle(
    fontFamily: uiFamily,
    color: line,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 1.4,
  );

  /// Body copy.
  static const body = TextStyle(
    fontFamily: uiFamily,
    color: textPrimary,
    fontSize: 14,
    height: 1.45,
  );

  /// Secondary / muted body copy.
  static const bodyMuted = TextStyle(
    fontFamily: uiFamily,
    color: textMuted,
    fontSize: 13,
    height: 1.45,
  );

  /// Numeric label used on the central card glyphs and chip counters.
  /// Tabular figures keep counts and scores from jittering as they change.
  static const numericChip = TextStyle(
    fontFamily: uiFamily,
    color: textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    letterSpacing: 0.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Large tabular number for HUD chips, seat scores, and stat tiles. Set in
  /// the UI face: Reem Kufi's round zero reads as the letter O at chip size.
  static const numericDisplay = TextStyle(
    fontFamily: uiFamily,
    color: textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 24,
    height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // -- Elevation (design contract section 3.2) -------------------------------

  /// L2: HUD chips, seat plates, toasts.
  static const elevationL2 = [
    BoxShadow(color: Color(0x59000000), offset: Offset(0, 4), blurRadius: 12),
  ];

  /// L3: panels, sheets, the coach card.
  static const elevationL3 = [
    BoxShadow(color: Color(0x73000000), offset: Offset(0, 12), blurRadius: 32),
  ];

  // -- Motion (design contract section 6; scale with MotionScope) ------------

  /// Press feedback, ring flash in.
  static const motionInstant = Duration(milliseconds: 120);

  /// Card lift, chip and state changes.
  static const motionQuick = Duration(milliseconds: 180);

  /// Panels, toasts, seat plate state.
  static const motionStandard = Duration(milliseconds: 220);

  /// Turn change, coach card in and out.
  static const motionEmphasis = Duration(milliseconds: 280);
}
