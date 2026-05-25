import 'package:flutter/material.dart';

import '../../../domain/classic_hareeg/models/playing_card.dart';
import 'card_painting.dart';
import 'card_state.dart';

/// Origin of a card theme's assets.
enum CardThemeAssetSource {
  /// Drawn entirely in Dart — no third-party assets.
  codeRendered,

  /// Bundled third-party assets (Kenney CC0, Wikimedia PD subset, etc.).
  bundledAssets,
}

/// Variant requested by a caller.
enum CardVariant {
  /// Full-size card (south seat hand, discard top, stock back).
  full,

  /// Compact meld card (opponent meld zones, fanned hands).
  compact,

  /// Picker card (legal meld combination picker).
  picker,

  /// Card back (stock pile, opponent hands).
  back,
}

/// Render mode for a joker.
enum JokerDisplay {
  /// Memory-aid: identity is briefly shown then quieted to the plain joker.
  memoryReveal,

  /// Default: represented identity is visible alongside the joker accent.
  assisted,

  /// Joker with no represented identity assigned yet.
  unassigned,
}

/// Inherits the active joker identity display mode for card rendering.
class JokerDisplayScope extends InheritedWidget {
  /// Creates a joker-display scope.
  const JokerDisplayScope({
    super.key,
    required this.display,
    this.cueDuration,
    required super.child,
  });

  /// Active joker display mode.
  final JokerDisplay display;

  /// How long the represented identity stays visible after placement when
  /// [display] is [JokerDisplay.memoryReveal]. Null means "persist" — used by
  /// the coaching/standard tiers where the badge never fades.
  final Duration? cueDuration;

  /// Reads the nearest display mode; falls back to assisted identity display.
  static JokerDisplay of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<JokerDisplayScope>();
    return scope?.display ?? JokerDisplay.assisted;
  }

  /// Reads the nearest cue duration, or null when no scope or no finite cue.
  static Duration? cueDurationOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<JokerDisplayScope>();
    return scope?.cueDuration;
  }

  @override
  bool updateShouldNotify(covariant JokerDisplayScope oldWidget) {
    return oldWidget.display != display ||
        oldWidget.cueDuration != cueDuration;
  }
}

/// Inherits whether card/table cues should use high-contrast overlays.
class CardContrastScope extends InheritedWidget {
  /// Creates a card-contrast scope.
  const CardContrastScope({
    super.key,
    required this.highContrast,
    required super.child,
  });

  /// Whether high-contrast cue overlays are enabled.
  final bool highContrast;

  /// Reads the nearest card contrast setting.
  static bool enabledOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CardContrastScope>();
    return scope?.highContrast ?? false;
  }

  @override
  bool updateShouldNotify(covariant CardContrastScope oldWidget) {
    return oldWidget.highContrast != highContrast;
  }
}

/// Optional badge drawn on top of the card face when the player should know
/// something extra about it (per-deck-copy distinction, joker memory aid).
enum CardBadge {
  /// No badge.
  none,

  /// Tiny pip in the corner that indicates which physical deck copy this
  /// card belongs to. Themes can choose to render it as a coloured dot.
  deckCopy,
}

/// Drawing request handed to a [CardTheme] paint method.
@immutable
class CardRenderRequest {
  /// Creates a render request.
  const CardRenderRequest({
    required this.card,
    required this.variant,
    required this.size,
    this.visualState = CardVisualState.normal,
    this.jokerDisplay = JokerDisplay.assisted,
    this.badge = CardBadge.none,
    this.faceDown = false,
    this.revealOpacity = 1.0,
  });

  /// Physical card being drawn (use [HareegCard.effectiveIdentity] for the
  /// face).
  final HareegCard card;

  /// Variant requested.
  final CardVariant variant;

  /// Render box size.
  final Size size;

  /// State overlay to apply.
  final CardVisualState visualState;

  /// How to render a joker's identity.
  final JokerDisplay jokerDisplay;

  /// Optional badge to draw on the face.
  final CardBadge badge;

  /// If true, draw the back regardless of [variant].
  final bool faceDown;

  /// Opacity of the represented-identity badge in `[0, 1]`. Used only when
  /// [jokerDisplay] is [JokerDisplay.memoryReveal] to animate the placement
  /// cue (fade in, hold, fade out). Defaults to 1.0 for the static cases.
  final double revealOpacity;
}

/// Optional extra-drawing hook a theme can run after the shared
/// [CardPainting] helpers have laid down the body, face, and back.
///
/// Receives the live [Canvas] and the [CardRenderRequest] so themes can
/// decorate the painted face with extras (e.g., Kenney Classic's mid-line
/// sand stroke). Returns nothing.
typedef CardPaintExtras = void Function(
  Canvas canvas,
  CardRenderRequest request,
);

/// Slug used in bundled asset filenames for each rank.
///
/// Kept here (not in a manifest field) so every asset-backed theme uses the
/// exact same vocabulary — `ace`, `two`, `three`, ..., `king`. This is the
/// same slug set the asset-consistency test asserts against, so themes that
/// pick their own renaming scheme cannot drift without the test flagging it.
const Map<CardRank, String> _rankSlugs = {
  CardRank.ace: 'ace',
  CardRank.two: 'two',
  CardRank.three: 'three',
  CardRank.four: 'four',
  CardRank.five: 'five',
  CardRank.six: 'six',
  CardRank.seven: 'seven',
  CardRank.eight: 'eight',
  CardRank.nine: 'nine',
  CardRank.ten: 'ten',
  CardRank.jack: 'jack',
  CardRank.queen: 'queen',
  CardRank.king: 'king',
};

/// Describes the bundled-asset surface of a [HareegCardTheme].
///
/// A null manifest means the theme is fully code-rendered. A non-null
/// manifest gives [HareegCardTheme.imageAssetFor] the data it needs to
/// resolve a `(card, variant)` request into a path under `assets/`:
///
/// - back  → `{root}/back.{extension}` when [hasBack] is true
/// - joker → `{root}/joker_red.{extension}` for the even-index joker,
///           `{root}/joker_black.{extension}` for the odd one, when
///           [hasJokers] is true
/// - standard face → `{root}/{rankSlug}_{suit}.{extension}`
///
/// Identities listed in [skipFaces] always resolve to `null` so the
/// code-rendered painter takes over for that one card — used for the
/// Sandline Lounge J♦ asset that currently holds J♥ artwork.
@immutable
class CardThemeAssetManifest {
  /// Creates an asset manifest.
  const CardThemeAssetManifest({
    required this.root,
    required this.extension,
    this.hasBack = true,
    this.hasJokers = true,
    this.skipFaces = const [],
  });

  /// Directory under `assets/` holding this theme's artwork.
  final String root;

  /// File extension (without the dot) for every artwork file (`png`, `webp`).
  final String extension;

  /// Whether `{root}/back.{extension}` exists. False for themes that paint
  /// their backs in code (Wikimedia PD ships only court faces).
  final bool hasBack;

  /// Whether `{root}/joker_red` / `joker_black` exist. False for themes that
  /// paint jokers in code (Wikimedia PD again).
  final bool hasJokers;

  /// `(rank, suit)` identities whose face asset is intentionally bypassed —
  /// the code-rendered painter draws them instead. Used to keep mismatched
  /// court art (e.g., the duplicate Sandline Lounge `jack_diamonds.webp`)
  /// from being shown. Modelled as a [List] (not a [Set]) so the manifest
  /// can be `const`-constructed — `CardIdentity` overrides `==`, which
  /// disqualifies it from `const` set membership.
  final List<CardIdentity> skipFaces;

  /// Resolves the asset path for [request], or null when the theme should
  /// fall back to the code-rendered painter.
  String? assetFor(CardRenderRequest request) {
    if (request.faceDown || request.variant == CardVariant.back) {
      return hasBack ? '$root/back.$extension' : null;
    }
    if (request.card.isJoker) {
      if (!hasJokers) return null;
      final suffix = (request.card.jokerIndex ?? 0).isEven ? 'red' : 'black';
      return '$root/joker_$suffix.$extension';
    }
    final identity = request.card.identity ?? request.card.representedIdentity;
    if (identity == null) return null;
    if (skipFaces.contains(identity)) return null;
    final rankSlug = _rankSlugs[identity.rank]!;
    return '$root/${rankSlug}_${identity.suit.name}.$extension';
  }
}

/// Bundled card theme rendered by [HareegCardView].
///
/// `HareegCardTheme` is a value object: a `const`-constructible bundle of
/// identity, palette, asset manifest, and optional paint extras. One theme
/// covers every variant (full / compact / picker / back) plus a
/// representation for jokers. State overlays are applied generically —
/// themes can swap in [overlayOverrides] if their palette needs a different
/// highlight set.
@immutable
class HareegCardTheme {
  /// Creates a card theme.
  const HareegCardTheme({
    required this.id,
    required this.label,
    required this.description,
    required this.palette,
    required this.source,
    required this.readableOnCompactLayouts,
    this.assetManifest,
    this.licenseAttribution,
    this.sourceUrl,
    this.available = true,
    this.unavailableReason,
    this.overlayOverrides,
    this.paintExtras,
  });

  /// Stable identifier persisted to preferences. Changing this orphans
  /// every player's saved theme preference, so don't.
  final String id;

  /// Player-facing label.
  final String label;

  /// Short description shown in the theme picker.
  final String description;

  /// Colour palette consumed by the shared [CardPainting] helpers.
  final CardThemePalette palette;

  /// Whether the theme's assets are code-rendered or bundled.
  final CardThemeAssetSource source;

  /// Bundled-asset surface, or null for fully code-rendered themes.
  final CardThemeAssetManifest? assetManifest;

  /// Optional license attribution shown on Settings → About → Licenses.
  final String? licenseAttribution;

  /// Optional source URL shown on Settings → About → Licenses.
  final String? sourceUrl;

  /// Whether the compact/picker variants remain readable on the smallest
  /// supported Android landscape viewport.
  final bool readableOnCompactLayouts;

  /// Whether the theme is currently available to play with. Themes whose
  /// bundled assets are not yet sourced can ship disabled but still listed
  /// in the picker.
  final bool available;

  /// Disabled-reason copy used by the picker (e.g., "Asset bundle pending").
  final String? unavailableReason;

  /// Optional overlay map; null inherits [DefaultCardStateOverlays.map].
  final CardStateOverlayMap? overlayOverrides;

  /// Optional extra drawing run after the shared face/back painters. Used
  /// by Kenney Classic to lay a sand-line stroke across the centre of the
  /// face — every other bundled theme leaves this null.
  final CardPaintExtras? paintExtras;

  /// Resolves the overlay style for a state, applying any theme override.
  CardStateOverlayStyle overlayFor(CardVisualState state) {
    final overrides = overlayOverrides;
    if (overrides != null && overrides.containsKey(state)) {
      return overrides[state]!;
    }
    return DefaultCardStateOverlays.map[state]!;
  }

  /// Optional bundled raster asset for this card.
  ///
  /// Code-rendered themes (no [assetManifest]) return null and paint
  /// everything on the canvas. Asset-backed themes return a path under
  /// `assets/` that [HareegCardView] composes before the state overlay.
  String? imageAssetFor(CardRenderRequest request) {
    return assetManifest?.assetFor(request);
  }

  /// Paints the card for the given request.
  ///
  /// Draws the face / back inside the rect `Offset.zero & request.size`
  /// using the shared [CardPainting] helpers, then runs [paintExtras] if
  /// the theme wants to decorate the result. The framework applies the
  /// state overlay afterwards using [overlayFor].
  void paint(Canvas canvas, CardRenderRequest request) {
    if (request.faceDown || request.variant == CardVariant.back) {
      CardPainting.paintBack(canvas, request, palette);
      return;
    }
    CardPainting.paintBody(canvas, request, palette);
    if (request.card.isJoker) {
      CardPainting.paintJokerFace(canvas, request, palette);
    } else {
      CardPainting.paintStandardFace(canvas, request, palette);
    }
    paintExtras?.call(canvas, request);
  }
}
