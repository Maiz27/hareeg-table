import 'package:flutter/material.dart';

/// The raw Hareeg Table brand palette: every colour the app may paint, named
/// by what it is, not by what it is for.
///
/// This is the **only** file that holds a brand hex value. Nothing outside
/// `lib/ui/core/theme/` may reference it; the app paints with the roles in
/// `LoungeTokens`, which map onto these. Change a hue here and every surface,
/// ring and medallion follows; a role that needs a different hue is re-pointed
/// in `lounge_tokens.dart`, in one line. The identity source is
/// `assets/brand/explorations/identity-2026-10/GUIDELINES.md`.
abstract final class BrandPalette {
  // -- Identity -------------------------------------------------------------

  /// The flame. Primary brand colour: launcher tile, accent, Fifty heat.
  static const ember = Color(0xFFE4522B);

  /// Ember pressed / deepened, for pressed states and the lamp's inner edge.
  static const emberDeep = Color(0xFFC8401F);

  /// Ember caught by the light: the top of a lit gradient, a hot highlight.
  static const emberBright = Color(0xFFF07A52);

  /// Charcoal sunk one step: recessed fills, tracks, inset trays.
  static const charcoalDeep = Color(0xFF0E0B09);

  /// The ground. Menus, panels, the splash, the tile behind the mark.
  static const charcoal = Color(0xFF15110E);

  /// Charcoal lifted one step: raised chips, banners and panels on charcoal.
  static const charcoalRaised = Color(0xFF221B16);

  /// Charcoal lifted two steps: the pool behind cards and lit medallions.
  static const charcoalSpotlight = Color(0xFF2C231C);

  /// The card. Card faces, paper, light surfaces.
  static const ivory = Color(0xFFF8F0DD);

  /// Sand hairlines, motif strokes, quiet selection.
  static const sand = Color(0xFFD7BD83);

  // -- The table ------------------------------------------------------------

  /// Felt green: the playing surface and nothing else.
  static const felt = Color(0xFF12382F);

  /// Felt raised: meld lanes, inset panels on the table.
  static const feltRaised = Color(0xFF184235);

  /// Felt spotlight: the lighter pool behind on-table cards.
  static const feltSpotlight = Color(0xFF1B4A3C);

  /// The white-hot core of the flame: the Fifty stamp's edge, fresh embers.
  static const flameCore = Color(0xFFFFE3A0);

  /// Lagoon blue: a decorative cool spark in celebrations, never a state.
  static const lagoon = Color(0xFF5FA8D3);

  // -- Signals --------------------------------------------------------------

  /// Amber: a card about to leave the hand.
  static const amber = Color(0xFFF0962E);

  /// Crimson: danger, elimination scores, the red suits.
  static const crimson = Color(0xFFA92E24);

  /// Rose red tuned for rings and borders: a rejected action.
  static const rose = Color(0xFFE07466);

  /// Indigo: opponent badges and inactive seats, used sparingly.
  static const indigo = Color(0xFF23395B);

  /// Slate teal: the east seat's identity, cool like indigo but told apart.
  static const slate = Color(0xFF2F5F6D);

  // -- Text -----------------------------------------------------------------

  /// Off-white body text on dark surfaces.
  static const offWhite = Color(0xFFF5EFE3);

  /// Muted text on dark surfaces.
  static const stone = Color(0xFFB8AA91);

  // -- Coach (deliberately cool) -------------------------------------------

  /// Teal: the reserved coach ring.
  static const teal = Color(0xFF2FB4A6);

  /// Blue: second coach meld group.
  static const sky = Color(0xFF4FA8E0);

  /// Violet: third coach meld group.
  static const violet = Color(0xFFB07BE6);

  /// Warm rose: the one card the coach says to let go.
  static const orchid = Color(0xFFDC6FA0);

  // -- High contrast (accessibility setting only) ---------------------------
  // Saturated signal hues for the high-contrast cues setting. They override
  // the brand states on purpose, so they are not derived from the identity.

  /// Selection and panel edges under high contrast.
  static const signalYellow = Color(0xFFFFD400);

  /// Pending under high contrast.
  static const signalOrange = Color(0xFFFF6F00);

  /// Cover target under high contrast.
  static const signalCyan = Color(0xFF00D9FF);

  /// Coach ring under high contrast.
  static const signalMint = Color(0xFF36F0DC);

  /// Invalid under high contrast.
  static const signalRed = Color(0xFFFF2F2F);

  // -- Neutrals -------------------------------------------------------------

  /// Pure black, for shadows and scrims only.
  static const black = Color(0xFF000000);
}
