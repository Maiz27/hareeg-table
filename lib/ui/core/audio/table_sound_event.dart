/// Logical table sound effects.
enum TableSoundEvent {
  /// First-frame brand cue accompanying the splash card fan.
  splashIntro,

  /// Round-opening shuffle / deck preparation.
  openingShuffle,

  /// One dealt card in the opening deal presentation.
  dealCard,

  /// Drawing a card from the stock pile.
  drawStock,

  /// Taking the visible discard.
  takeDiscard,

  /// Placing a card on the discard pile.
  discardCard,

  /// Placing cards onto the table meld area.
  meldPlace,

  /// Returning a card or staged table play.
  cardReturn,

  /// Successful Fifty claim.
  fiftyClaim,

  /// Joker placed with a declared identity — short distinct cue to focus the
  /// memory-reveal window. Plays in every strictness tier so players hear the
  /// declaration regardless of whether the badge persists.
  jokerDeclared,

  /// Invalid move feedback.
  invalidAction,

  /// Round result appears.
  roundEnd,

  /// Final match-over screen appears.
  matchEnd,
}
