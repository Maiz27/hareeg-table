/// Temporary string catalog for user-facing copy.
///
/// Keeping strings outside widgets from the first slice makes it easier to
/// replace this class with generated localization delegates later.
abstract final class AppStrings {
  /// App title used by the platform shell and main screen.
  static const appTitle = 'Hareeg Table';

  /// Primary title shown on the app's first screen.
  static const homeTitle = 'Hareeg Table';

  /// Short subtitle for the current foundation shell.
  static const homeSubtitle = 'Offline Classic Hareeg';

  /// Main menu primary action.
  static const newGame = 'New Game';

  /// Disabled resume action.
  static const continueGame = 'Continue';

  /// Settings action.
  static const settings = 'Settings';

  /// Rules/help action.
  static const rulesHelp = 'Rules / Help';

  /// Disabled resume explanation.
  static const noSavedMatch = 'No saved match yet';

  /// Saved-match loading explanation.
  static const checkingSavedMatch = 'Checking saved match...';

  /// Saved-match resume explanation.
  static const resumeSavedMatch = 'Resume saved Classic Hareeg table';

  /// Abandon saved match action.
  static const abandonSavedMatch = 'Abandon saved match';

  /// Seat-count summary label.
  static const seatsLabel = 'Seats';

  /// Opening summary label.
  static const openingLabel = 'Opening';

  /// Fifty timer summary label.
  static const fiftyLabel = 'Fifty';

  /// Coming-soon section title.
  static const plannedModes = 'Planned modes';

  /// Hareeg 14 planned mode label.
  static const hareeg14 = 'Hareeg 14';

  /// Fifties planned mode label.
  static const fifties = 'Fifties';

  /// Coming-soon label.
  static const comingSoon = 'Coming soon';

  /// Label for the default Classic Hareeg mode.
  static const classicModeTitle = 'Classic Hareeg';

  /// Compact summary of the default Classic Hareeg experience.
  static const classicModeDescription =
      'Four seats, anti-clockwise turns, 51 opening, covers, jokers, and Fifty.';

  /// Setup screen title.
  static const setupTitle = 'Classic Hareeg setup';

  /// Start table action.
  static const startTable = 'Start Table';

  /// Live table screen title.
  static const tableTitle = 'Classic Hareeg Table';

  /// Human player label.
  static const humanSeat = 'You';

  /// Stock area label.
  static const stock = 'Stock';

  /// Discard area label.
  static const discard = 'Discard';

  /// Empty meld zone label.
  static const meldZone = 'Meld area';

  /// Draw action.
  static const drawStock = 'Draw Stock';

  /// Discard action.
  static const discardCard = 'Discard';

  /// Take discard action.
  static const takeDiscard = 'Take Discard';

  /// Return a pending discard and draw from stock.
  static const returnDiscard = 'Return + Draw';

  /// Take back uncommitted opening melds.
  static const takeBackMelds = 'Take Back Melds';

  /// Pending discard status label.
  static const pendingDiscard = 'Pending discard';

  /// Auto-sort hand action.
  static const autoSort = 'Auto-sort';

  /// Placeholder settings title.
  static const settingsTitle = 'Settings';

  /// Rules help title.
  static const helpTitle = 'Classic Hareeg rules';

  /// Help section title for setup rules.
  static const helpSetupTitle = 'Setup';

  /// Help section body for setup rules.
  static const helpSetupBody =
      'Classic Hareeg uses four seats, one human player, three CPU players, and anti-clockwise turns. The app defaults to two decks and two jokers so there are enough cards for a four-seat deal. The starter receives 15 cards and skips the first draw.';

  /// Help section title for turn flow rules.
  static const helpTurnFlowTitle = 'Turn flow';

  /// Help section body for turn flow rules.
  static const helpTurnFlowBody =
      'The starter begins in action phase. Other turns begin by drawing from stock or taking the previous discard. A taken discard becomes pending: it must be used in a valid play that turn or returned before drawing from stock.';

  /// Help section title for opening rules.
  static const helpOpeningTitle = 'Opening and benchmark';

  /// Help section body for opening rules.
  static const helpOpeningBody =
      'The default opening requirement is 51, with 75 available as a setup option. A player opens by placing one or more new melds whose combined value reaches the current requirement. Covers do not count toward opening. The first opener owns the benchmark and can raise it until a second player opens, then the benchmark locks.';

  /// Help section title for cover rules.
  static const helpCoversTitle = 'Covers';

  /// Help section body for cover rules.
  static const helpCoversBody =
      'A cover is a card that can extend an existing table meld right now. Sequence covers are direct neighbors only; after a card is placed, chained covers may become legal. Covers cannot normally be discarded by opened or unopened players, but a cover may be the final discard when finishing.';

  /// Help section title for joker rules.
  static const helpJokersTitle = 'Jokers';

  /// Help section body for joker rules.
  static const helpJokersBody =
      'Jokers represent a chosen card identity when placed in a meld or cover. If several identities are legal, the human player must choose; CPU players choose deterministically. Opened players may replace a table joker with the represented card and take the joker. Normal joker discard is always blocked, but a joker may be the final discard.';

  /// Help section title for Fifty / Khamsin rules.
  static const helpFiftyTitle = 'Fifty / Khamsin';

  /// Help section body for Fifty / Khamsin rules.
  static const helpFiftyBody =
      'After a discard, only the immediate next player can claim Fifty, and only before the timer expires. The discarded card must be part of a legal finish, including hand melds, table covers, or chained covers. In Assisted mode, the Fifty action appears only when valid. If the timer is missed, the player may still take the discard normally when legal, but the finish scores as normal instead of Fifty.';

  /// Help section title for scoring rules.
  static const helpScoringTitle = 'Scoring';

  /// Help section body for scoring rules.
  static const helpScoringBody =
      'Normal winners score -1. In Fifty, the winner scores -3, except the first dealt round uses -1, and the discarder adds remaining cards plus 3. Other active players add remaining card count. Drawn rounds do not change scores. Players at 31 or more are eliminated, and the last remaining player wins.';

  /// Help section title for mistake preset rules.
  static const helpMistakePresetsTitle = 'Mistake presets';

  /// Help section body for mistake preset rules.
  static const helpMistakePresetsBody =
      'Assisted blocks illegal actions. Table penalties allow selected mistakes with +3. Hard table 17 allows selected mistakes with +17 and removes that player from the current round. Normal joker discard stays blocked in every preset.';

  /// Help section title for pause and resume rules.
  static const helpPauseResumeTitle = 'Pause and resume';

  /// Help section body for pause and resume rules.
  static const helpPauseResumeBody =
      'The app saves active Classic Hareeg table state locally at safe table changes. Continue resumes the saved hands, stock, discard pile, turn phase, pending discard, and setup. Abandon saved match clears the local save.';

  /// Help section title for planned modes.
  static const helpPlannedModesTitle = 'Planned modes';

  /// Help section body for planned modes.
  static const helpPlannedModesBody =
      'Hareeg 14 and a dedicated Fifties mode are planned future modes. The first release focuses on Classic Hareeg.';

  /// Status line confirming that rules code is isolated from Flutter widgets.
  static const rulesReady = 'Pure Dart rules core';

  /// Status line confirming that CPU logic has a separate boundary.
  static const cpuReady = 'CPU strategy boundary';

  /// Status line confirming that local preferences have a persistence boundary.
  static const persistenceReady = 'Local preferences boundary';

  // -- Splash + brand ------------------------------------------------------

  /// Splash subtitle shown under the wordmark.
  static const splashTagline = 'Offline Classic Hareeg';

  /// Splash hint copy.
  static const splashTapToContinue = 'Tap to continue';

  // -- Table chrome --------------------------------------------------------

  /// Score button tooltip.
  static const scores = 'Scores';

  /// Pause button tooltip.
  static const pauseTable = 'Pause';

  /// Score overlay title.
  static const scoresTitle = 'Match scores';

  /// Pause overlay title.
  static const pauseTitle = 'Paused';

  /// Pause overlay "Resume table" action.
  static const resumeTable = 'Resume table';

  /// Pause overlay "Leave table" action.
  static const leaveTable = 'Leave table';

  /// Pause overlay subhead for in-match controls.
  static const pauseInMatchControls = 'In-match settings';

  /// Aids selection group label.
  static const aidsLabel = 'Table aids';

  /// Aids selection footnote shown on the pause overlay.
  static const aidsHelp =
      'Aids only change which hints the app shows. Scoring stays the same.';

  /// Motion speed group label.
  static const motionSpeedLabel = 'Motion speed';

  /// Haptics toggle title.
  static const hapticsLabel = 'Table haptics';

  /// Haptics toggle subtitle.
  static const hapticsHelp = 'Light vibrations on taps, drops, and Fifty.';

  /// Sound toggle title.
  static const soundLabel = 'Table sounds';

  /// Sound toggle subtitle.
  static const soundHelp = 'Sounds will arrive in a future update.';

  /// Settings card-theme group label.
  static const cardThemeLabel = 'Card theme';

  /// Card theme picker subtitle.
  static const cardThemeHelp =
      'Themes can only be changed outside an active match.';

  /// About → Licenses navigation entry.
  static const aboutLicenses = 'About & Licenses';

  /// About header line on the licenses screen.
  static const aboutHeader = 'Hareeg Table';

  /// About body on the licenses screen.
  static const aboutBody =
      'Open-source Sudanese Hareeg, offline-first, ad-free. '
      'Source on GitHub.';

  /// Generic theme attribution heading on the licenses screen.
  static const licensesThemesHeader = 'Card themes';

  /// Generic licenses screen footer note.
  static const licensesFooter =
      'Bundled assets keep their original CC0 / Public Domain licenses.';

  // -- Aid level descriptions used on settings + pause ---------------------

  /// Guided aid level description shown in settings detail.
  static const aidGuidedDescription =
      'Full hints. Legal targets glow, pending warnings show, invalid moves explain themselves, Fifty prompts appear when valid.';

  /// Standard aid level description shown in settings detail.
  static const aidStandardDescription =
      'Meld picker remains; fewer proactive hints.';

  /// Table mode aid level description shown in settings detail.
  static const aidTableModeDescription =
      'Minimal aids while preserving accessibility and state feedback.';

  // -- Action labels shared by the table action bar ------------------------

  /// Score overlay button label.
  static const openScoresButton = 'Scores';

  /// Pause overlay button label.
  static const openPauseButton = 'Pause';

  /// Play meld button label.
  static const playMeld = 'Play meld';

  /// Place cover button label.
  static const placeCover = 'Place cover';

  /// Replace joker button label.
  static const replaceJoker = 'Replace joker';

  /// Claim Fifty button label.
  static const claimFifty = 'Claim Fifty';

  /// Sort mode group label.
  static const sortModeLabel = 'Sort';

  /// Sort modes.
  static const sortByRank = 'Rank';

  /// Sort by suit.
  static const sortBySuit = 'Suit';

  /// Manual sort label.
  static const sortManual = 'Manual';
}
