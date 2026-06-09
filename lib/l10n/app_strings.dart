import 'package:flutter/widgets.dart';

import '../domain/classic_hareeg/models/player_seat.dart';
import '../domain/classic_hareeg/models/playing_card.dart';
import '../domain/classic_hareeg/models/table_strictness.dart';

/// Locale-aware string catalog for user-facing copy.
///
/// This keeps the existing lightweight catalog shape while making the selected
/// language available through the widget tree. It can still be migrated to
/// generated ARB localizations later without changing most app call sites.
@immutable
class AppStrings {
  const AppStrings._(this.languageCode, this._values);

  /// English strings.
  static const english = AppStrings._('en', _englishValues);

  /// Arabic strings.
  static const arabic = AppStrings._('ar', _arabicValues);

  /// Locales supported by the app shell.
  static const supportedLocales = [Locale('en'), Locale('ar')];

  /// Resolves a string catalog from a stable language code.
  static AppStrings forLanguageCode(String code) {
    return code.toLowerCase().startsWith('ar') ? arabic : english;
  }

  /// Reads the current string catalog from the nearest scope.
  static AppStrings of(BuildContext context) => AppStringsScope.of(context);

  /// Stable locale code.
  final String languageCode;

  final Map<String, String> _values;

  /// Whether this language should be presented right-to-left.
  bool get isRtl => languageCode == 'ar';

  /// Text direction for the selected language.
  TextDirection get textDirection =>
      isRtl ? TextDirection.rtl : TextDirection.ltr;

  String _v(String key) => _values[key] ?? _englishValues[key]!;

  String get appTitle => _v('appTitle');
  String get homeTitle => _v('homeTitle');
  String get newGame => _v('newGame');
  String get continueGame => _v('continueGame');
  String get settings => _v('settings');
  String get rulesHelp => _v('rulesHelp');
  String get noSavedMatch => _v('noSavedMatch');
  String get checkingSavedMatch => _v('checkingSavedMatch');
  String get abandonSavedMatch => _v('abandonSavedMatch');
  String get classicModeDescription => _v('classicModeDescription');
  String get setupTitle => _v('setupTitle');
  String get startTable => _v('startTable');
  String get tableTitle => _v('tableTitle');
  String get humanSeat => _v('humanSeat');
  String get stock => _v('stock');
  String get discard => _v('discard');
  String get meldZone => _v('meldZone');
  String get drawStock => _v('drawStock');
  String get discardCard => _v('discardCard');
  String get takeDiscard => _v('takeDiscard');
  String get returnDiscard => _v('returnDiscard');
  String get takeBackMelds => _v('takeBackMelds');
  String get pendingDiscard => _v('pendingDiscard');
  String get settingsTitle => _v('settingsTitle');
  String get helpTitle => _v('helpTitle');
  String get helpIntro => _v('helpIntro');
  String get helpSetupTitle => _v('helpSetupTitle');
  String get helpSetupBody => _v('helpSetupBody');
  String get helpTurnFlowTitle => _v('helpTurnFlowTitle');
  String get helpTurnFlowBody => _v('helpTurnFlowBody');
  String get helpOpeningTitle => _v('helpOpeningTitle');
  String get helpOpeningBody => _v('helpOpeningBody');
  String get helpCoversTitle => _v('helpCoversTitle');
  String get helpCoversBody => _v('helpCoversBody');
  String get helpJokersTitle => _v('helpJokersTitle');
  String get helpJokersBody => _v('helpJokersBody');
  String get helpFiftyTitle => _v('helpFiftyTitle');
  String get helpFiftyBody => _v('helpFiftyBody');
  String get helpScoringTitle => _v('helpScoringTitle');
  String get helpScoringBody => _v('helpScoringBody');
  String get helpMistakePresetsTitle => _v('helpMistakePresetsTitle');
  String get helpMistakePresetsBody => _v('helpMistakePresetsBody');
  String get helpPauseResumeTitle => _v('helpPauseResumeTitle');
  String get helpPauseResumeBody => _v('helpPauseResumeBody');
  String get helpPlannedModesTitle => _v('helpPlannedModesTitle');
  String get helpPlannedModesBody => _v('helpPlannedModesBody');
  String get splashTagline => _v('splashTagline');
  String get splashTapToContinue => _v('splashTapToContinue');
  String get scores => _v('scores');
  String get pauseTable => _v('pauseTable');
  String get skipToNextRound => _v('skipToNextRound');
  String get scoresTitle => _v('scoresTitle');
  String get pauseTitle => _v('pauseTitle');
  String get resumeTable => _v('resumeTable');
  String get leaveTable => _v('leaveTable');
  String get pauseInMatchControls => _v('pauseInMatchControls');
  String get motionSpeedLabel => _v('motionSpeedLabel');
  String get fastCpuTurns => _v('fastCpuTurns');
  String get fastCpuTurnsDescription => _v('fastCpuTurnsDescription');
  String get hapticsLabel => _v('hapticsLabel');
  String get hapticsHelp => _v('hapticsHelp');
  String get soundLabel => _v('soundLabel');
  String get soundHelp => _v('soundHelp');
  String get highContrastCards => _v('highContrastCards');
  String get highContrastCardsDescription => _v('highContrastCardsDescription');
  String get aboutLicenses => _v('aboutLicenses');
  String get aboutHeader => _v('aboutHeader');
  String get aboutBody => _v('aboutBody');
  String get licensesThemesHeader => _v('licensesThemesHeader');
  String get licensesSoundsHeader => _v('licensesSoundsHeader');
  String get kenneyCasinoAudio => _v('kenneyCasinoAudio');
  String get kenneyCasinoAudioAttribution => _v('kenneyCasinoAudioAttribution');
  String get kenneyCasinoAudioUrl => _v('kenneyCasinoAudioUrl');
  String get licensesFooter => _v('licensesFooter');
  String get playMeld => _v('playMeld');
  String get placeCover => _v('placeCover');
  String get replaceJoker => _v('replaceJoker');
  String get claimFifty => _v('claimFifty');
  String get sortModeLabel => _v('sortModeLabel');
  String get sortByRank => _v('sortByRank');
  String get sortBySuit => _v('sortBySuit');
  String get sortManual => _v('sortManual');
  String get sortByRankDescription => _v('sortByRankDescription');
  String get sortBySuitDescription => _v('sortBySuitDescription');
  String get sortManualDescription => _v('sortManualDescription');
  String get tableRules => _v('tableRules');
  String get tableRulesDescription => _v('tableRulesDescription');
  String get deckCount => _v('deckCount');
  String get fiftyTimer => _v('fiftyTimer');
  String get handSort => _v('handSort');
  String get handSortDescription => _v('handSortDescription');
  String get tableStrictnessTitle => _v('tableStrictnessTitle');
  String get tableStrictnessSectionDescription =>
      _v('tableStrictnessSectionDescription');
  String get strictnessLockedActiveMatch => _v('strictnessLockedActiveMatch');
  String get look => _v('look');
  String get lookDescription => _v('lookDescription');
  String get feel => _v('feel');
  String get feelDescription => _v('feelDescription');
  String get language => _v('language');
  String get languageDescription => _v('languageDescription');
  String get englishLanguage => _v('englishLanguage');
  String get arabicLanguage => _v('arabicLanguage');
  String get tableSurface => _v('tableSurface');
  String get tableSurfaceDescription => _v('tableSurfaceDescription');
  String get themeLockedActiveMatch => _v('themeLockedActiveMatch');
  String get codeRendered => _v('codeRendered');
  String get bundledAsset => _v('bundledAsset');
  String get smallTableReady => _v('smallTableReady');
  String get compactQaPending => _v('compactQaPending');
  String get cpuDifficulty => _v('cpuDifficulty');
  String get beginner => _v('beginner');
  String get casual => _v('casual');
  String get skilled => _v('skilled');
  String get expert => _v('expert');
  String get firstStarter => _v('firstStarter');
  String get youStart => _v('youStart');
  String get random => _v('random');
  String get openingRequirement => _v('openingRequirement');
  String get jokers => _v('jokers');
  String get houseRules => _v('houseRules');
  String get edit => _v('edit');
  String get normal => _v('normal');
  String get fast => _v('fast');
  String get reduced => _v('reduced');
  String get normalMotion => _v('normalMotion');
  String get fastMotion => _v('fastMotion');
  String get reducedMotion => _v('reducedMotion');
  String get sandlineLounge => _v('sandlineLounge');
  String get darkFelt => _v('darkFelt');
  String get lightWood => _v('lightWood');
  String get midnightSapphire => _v('midnightSapphire');
  String get crimsonClay => _v('crimsonClay');
  String get close => _v('close');
  String get empty => _v('empty');
  String get noMeldsYet => _v('noMeldsYet');
  String get matchOver => _v('matchOver');
  String get youWinTheMatch => _v('youWinTheMatch');
  String get finalStandings => _v('finalStandings');
  String get newMatchSameSetup => _v('newMatchSameSetup');
  String get wonByFifty => _v('wonByFifty');
  String get wonByFinish => _v('wonByFinish');
  String get returnToMenu => _v('returnToMenu');
  String get eliminated => _v('eliminated');
  String get nextNow => _v('nextNow');
  String get menu => _v('menu');
  String get couldNotSaveTable => _v('couldNotSaveTable');
  String get reportTableIssue => _v('reportTableIssue');
  String get exportMatchReport => _v('exportMatchReport');
  String get matchReportShareReady => _v('matchReportShareReady');
  String get matchReportCopyFallback => _v('matchReportCopyFallback');
  String get copyReport => _v('copyReport');
  String get matchReportCopied => _v('matchReportCopied');
  String get matchReportCopyFailed => _v('matchReportCopyFailed');
  String get cpuEast => _v('cpuEast');
  String get cpuNorth => _v('cpuNorth');
  String get cpuWest => _v('cpuWest');
  String get joker => _v('joker');
  String get unassignedJoker => _v('unassignedJoker');
  String get unassignedJokerGuided => _v('unassignedJokerGuided');

  // First-run onboarding.
  String get onboardingSkip => _v('onboardingSkip');
  String get onboardingNext => _v('onboardingNext');
  String get onboardingDone => _v('onboardingDone');
  String get onboardingStartPractice => _v('onboardingStartPractice');
  String get onboardingStartPlaying => _v('onboardingStartPlaying');
  String get onboardingWelcomeTitle => _v('onboardingWelcomeTitle');
  String get onboardingWelcomeBody => _v('onboardingWelcomeBody');
  String get onboardingTurnTitle => _v('onboardingTurnTitle');
  String get onboardingTurnBody => _v('onboardingTurnBody');
  String get onboardingLearnTitle => _v('onboardingLearnTitle');
  String get onboardingLearnBody => _v('onboardingLearnBody');
  String get onboardingReadyTitle => _v('onboardingReadyTitle');
  String get onboardingReadyBody => _v('onboardingReadyBody');

  // Guided practice checklist hub.
  String get practiceTitle => _v('practiceTitle');
  String get practiceIntro => _v('practiceIntro');
  String get practiceReplayIntro => _v('practiceReplayIntro');
  String get practiceStatusNotStarted => _v('practiceStatusNotStarted');
  String get practiceStatusSkipped => _v('practiceStatusSkipped');
  String get practiceStatusCompleted => _v('practiceStatusCompleted');
  String get practiceStart => _v('practiceStart');
  String get practiceReplay => _v('practiceReplay');
  String get practiceSkip => _v('practiceSkip');
  String get practiceUnskip => _v('practiceUnskip');
  String get practiceComingSoon => _v('practiceComingSoon');

  /// Gentle nudge when a legal table action is off-script for the step.
  String get practiceFollowStep => _v('practiceFollowStep');

  /// Completion overlay: continue into the pack's next lesson.
  String get practiceNextLesson => _v('practiceNextLesson');
  String get practicePackFundamentalsTitle =>
      _v('practicePackFundamentalsTitle');
  String get practicePackCoreTitle => _v('practicePackCoreTitle');
  String get practicePackTableTitle => _v('practicePackTableTitle');
  String get practicePackFinishTitle => _v('practicePackFinishTitle');
  String get practicePackTableStrictnessTitle =>
      _v('practicePackTableStrictnessTitle');

  /// Checklist progress summary, e.g. "3 of 15 completed".
  String practiceProgress(int completed, int total) => _v(
    'practiceProgress',
  ).replaceFirst('{completed}', '$completed').replaceFirst('{total}', '$total');

  // Guided practice lesson catalog.
  // Fundamentals pack: conceptual reference panels.
  String get practiceCardValuesTitle => _v('practiceCardValuesTitle');
  String get practiceCardValuesSummary => _v('practiceCardValuesSummary');
  String get practiceMeldShapesTitle => _v('practiceMeldShapesTitle');
  String get practiceMeldShapesSummary => _v('practiceMeldShapesSummary');
  String get practiceTheAceTitle => _v('practiceTheAceTitle');
  String get practiceTheAceSummary => _v('practiceTheAceSummary');
  String get practiceTurnRhythmTitle => _v('practiceTurnRhythmTitle');
  String get practiceTurnRhythmSummary => _v('practiceTurnRhythmSummary');
  String get practiceFirstMeldTitle => _v('practiceFirstMeldTitle');
  String get practiceFirstMeldSummary => _v('practiceFirstMeldSummary');
  String get practiceDiscardOpeningTitle => _v('practiceDiscardOpeningTitle');
  String get practiceDiscardOpeningSummary =>
      _v('practiceDiscardOpeningSummary');
  String get practiceBaitDiscardTitle => _v('practiceBaitDiscardTitle');
  String get practiceBaitDiscardSummary => _v('practiceBaitDiscardSummary');
  String get practicePendingDiscardTitle => _v('practicePendingDiscardTitle');
  String get practicePendingDiscardSummary =>
      _v('practicePendingDiscardSummary');
  String get practiceOpeningTitle => _v('practiceOpeningTitle');
  String get practiceOpeningSummary => _v('practiceOpeningSummary');
  String get practiceBenchmarkTitle => _v('practiceBenchmarkTitle');
  String get practiceBenchmarkSummary => _v('practiceBenchmarkSummary');
  String get practiceSequenceCoverTitle => _v('practiceSequenceCoverTitle');
  String get practiceSequenceCoverSummary => _v('practiceSequenceCoverSummary');
  String get practiceSetCoverTitle => _v('practiceSetCoverTitle');
  String get practiceSetCoverSummary => _v('practiceSetCoverSummary');
  String get practiceCoverDiscardTitle => _v('practiceCoverDiscardTitle');
  String get practiceCoverDiscardSummary => _v('practiceCoverDiscardSummary');
  String get practiceJokerIdentityTitle => _v('practiceJokerIdentityTitle');
  String get practiceJokerIdentitySummary => _v('practiceJokerIdentitySummary');
  String get practiceJokerReplacementTitle =>
      _v('practiceJokerReplacementTitle');
  String get practiceJokerReplacementSummary =>
      _v('practiceJokerReplacementSummary');
  String get practiceFinalDiscardTitle => _v('practiceFinalDiscardTitle');
  String get practiceFinalDiscardSummary => _v('practiceFinalDiscardSummary');
  String get practiceNormalFinishTitle => _v('practiceNormalFinishTitle');
  String get practiceNormalFinishSummary => _v('practiceNormalFinishSummary');
  String get practicePerfectHandTitle => _v('practicePerfectHandTitle');
  String get practicePerfectHandSummary => _v('practicePerfectHandSummary');
  String get practiceJokerOutTitle => _v('practiceJokerOutTitle');
  String get practiceJokerOutSummary => _v('practiceJokerOutSummary');
  String get practiceFiftyClaimTitle => _v('practiceFiftyClaimTitle');
  String get practiceFiftyClaimSummary => _v('practiceFiftyClaimSummary');
  String get practiceFiftyScoringTitle => _v('practiceFiftyScoringTitle');
  String get practiceFiftyScoringSummary => _v('practiceFiftyScoringSummary');
  String get practiceStrictnessTitle => _v('practiceStrictnessTitle');
  String get practiceStrictnessSummary => _v('practiceStrictnessSummary');
  String get practiceStrictPenaltyTitle => _v('practiceStrictPenaltyTitle');
  String get practiceStrictPenaltySummary => _v('practiceStrictPenaltySummary');
  String get practiceTablePenaltyTitle => _v('practiceTablePenaltyTitle');
  String get practiceTablePenaltySummary => _v('practiceTablePenaltySummary');

  // Fundamentals reading-panel content.
  String get practiceCardValuesPanelTitle => _v('practiceCardValuesPanelTitle');
  String get practiceCardValuesIntro => _v('practiceCardValuesIntro');
  String get practiceCardValuesNumberHeading =>
      _v('practiceCardValuesNumberHeading');
  String get practiceCardValuesNumberLine => _v('practiceCardValuesNumberLine');
  String get practiceCardValuesFaceHeading =>
      _v('practiceCardValuesFaceHeading');
  String get practiceCardValuesFaceLine => _v('practiceCardValuesFaceLine');
  String get practiceCardValuesOutro => _v('practiceCardValuesOutro');
  String get practiceCardValue2 => _v('practiceCardValue2');
  String get practiceCardValue5 => _v('practiceCardValue5');
  String get practiceCardValue9 => _v('practiceCardValue9');
  String get practiceCardValue10Each => _v('practiceCardValue10Each');

  String get practiceMeldShapesPanelTitle => _v('practiceMeldShapesPanelTitle');
  String get practiceMeldShapesIntro => _v('practiceMeldShapesIntro');
  String get practiceMeldShapesSetHeading => _v('practiceMeldShapesSetHeading');
  String get practiceMeldShapesSetLine => _v('practiceMeldShapesSetLine');
  String get practiceMeldShapesRunHeading => _v('practiceMeldShapesRunHeading');
  String get practiceMeldShapesRunLine => _v('practiceMeldShapesRunLine');
  String get practiceMeldShapesOutro => _v('practiceMeldShapesOutro');
  String get practiceMeldShapesSetCaption => _v('practiceMeldShapesSetCaption');
  String get practiceMeldShapesRunCaption => _v('practiceMeldShapesRunCaption');

  String get practiceTheAcePanelTitle => _v('practiceTheAcePanelTitle');
  String get practiceTheAceIntro => _v('practiceTheAceIntro');
  String get practiceTheAceHighHeading => _v('practiceTheAceHighHeading');
  String get practiceTheAceHighLine => _v('practiceTheAceHighLine');
  String get practiceTheAceLowHeading => _v('practiceTheAceLowHeading');
  String get practiceTheAceLowLine => _v('practiceTheAceLowLine');
  String get practiceTheAceFlipHeading => _v('practiceTheAceFlipHeading');
  String get practiceTheAceFlipLine => _v('practiceTheAceFlipLine');
  String get practiceTheAceOutro => _v('practiceTheAceOutro');
  String get practiceTheAceHighCaption => _v('practiceTheAceHighCaption');
  String get practiceTheAceLowCaption => _v('practiceTheAceLowCaption');
  String get practiceTheAceFlipCaption => _v('practiceTheAceFlipCaption');

  // Rules/Help learning entry points.
  String get helpLearningTitle => _v('helpLearningTitle');
  String get helpLearningBody => _v('helpLearningBody');

  // Practice lesson surface.
  String get practiceLessonCompleteTitle => _v('practiceLessonCompleteTitle');
  String get practiceLessonCompleteBody => _v('practiceLessonCompleteBody');
  String get practiceBackToList => _v('practiceBackToList');
  String get practiceReplayLesson => _v('practiceReplayLesson');

  /// Step position label, e.g. "Step 1 of 2".
  String practiceStepLabel(int step, int total) => _v(
    'practiceStepLabel',
  ).replaceFirst('{step}', '$step').replaceFirst('{total}', '$total');

  // Turn rhythm lesson.
  String get practiceTurnRhythmStep1 => _v('practiceTurnRhythmStep1');
  String get practiceTurnRhythmStep1Done => _v('practiceTurnRhythmStep1Done');
  String get practiceTurnRhythmStep2 => _v('practiceTurnRhythmStep2');
  String get practiceTurnRhythmStep2Hint => _v('practiceTurnRhythmStep2Hint');

  // First meld lesson.
  String get practiceFirstMeldStep2 => _v('practiceFirstMeldStep2');
  String get practiceFirstMeldStep2Hint => _v('practiceFirstMeldStep2Hint');
  String get practiceFirstMeldStep2Done => _v('practiceFirstMeldStep2Done');
  String get practiceFirstMeldStep2Hold => _v('practiceFirstMeldStep2Hold');
  String get practiceFirstMeldStep3 => _v('practiceFirstMeldStep3');

  // Opening from the discard lesson.
  String get practiceDiscardOpeningStep1 => _v('practiceDiscardOpeningStep1');
  String get practiceDiscardOpeningStep1Done =>
      _v('practiceDiscardOpeningStep1Done');
  String get practiceDiscardOpeningStep2 => _v('practiceDiscardOpeningStep2');
  String get practiceDiscardOpeningStep2Hint =>
      _v('practiceDiscardOpeningStep2Hint');
  String get practiceDiscardOpeningStep2Done =>
      _v('practiceDiscardOpeningStep2Done');
  String get practiceDiscardOpeningStep3 => _v('practiceDiscardOpeningStep3');
  String get practiceDiscardOpeningStep3Done =>
      _v('practiceDiscardOpeningStep3Done');
  String get practiceDiscardOpeningStep4 => _v('practiceDiscardOpeningStep4');

  // Bait discard lesson.
  String get practiceBaitStep1 => _v('practiceBaitStep1');
  String get practiceBaitStep1Done => _v('practiceBaitStep1Done');
  String get practiceBaitStep2 => _v('practiceBaitStep2');

  // Opening to 51 lesson.
  String get practiceOpeningStep1 => _v('practiceOpeningStep1');
  String get practiceOpeningStep1Hint => _v('practiceOpeningStep1Hint');
  String get practiceOpeningStep1Done => _v('practiceOpeningStep1Done');
  String get practiceOpeningStep2 => _v('practiceOpeningStep2');
  String get practiceOpeningStep2Done => _v('practiceOpeningStep2Done');
  String get practiceOpeningStep3 => _v('practiceOpeningStep3');

  // Pending discard lesson.
  String get practicePendingStep1 => _v('practicePendingStep1');
  String get practicePendingStep1Done => _v('practicePendingStep1Done');
  String get practicePendingStep2 => _v('practicePendingStep2');
  String get practicePendingStep2Hint => _v('practicePendingStep2Hint');
  String get practicePendingStep2Done => _v('practicePendingStep2Done');
  String get practicePendingStep3 => _v('practicePendingStep3');
  String get practicePendingStep4 => _v('practicePendingStep4');
  String get practicePendingStep4Hint => _v('practicePendingStep4Hint');
  String get practicePendingStep4Done => _v('practicePendingStep4Done');

  // Benchmark pressure lesson.
  String get practiceBenchmarkStep1 => _v('practiceBenchmarkStep1');
  String get practiceBenchmarkStep2 => _v('practiceBenchmarkStep2');
  String get practiceBenchmarkStep2Hint => _v('practiceBenchmarkStep2Hint');
  String get practiceBenchmarkStep2Done => _v('practiceBenchmarkStep2Done');
  String get practiceBenchmarkStep3 => _v('practiceBenchmarkStep3');
  String get practiceBenchmarkStep3Hint => _v('practiceBenchmarkStep3Hint');
  String get practiceBenchmarkStep3Done => _v('practiceBenchmarkStep3Done');
  String get practiceBenchmarkStep4 => _v('practiceBenchmarkStep4');

  // Cover lessons.
  String get practiceSeqCoverStep1 => _v('practiceSeqCoverStep1');
  String get practiceSeqCoverStep1Hint => _v('practiceSeqCoverStep1Hint');
  String get practiceSeqCoverStep1Hold => _v('practiceSeqCoverStep1Hold');
  String get practiceSeqCoverStep1Done => _v('practiceSeqCoverStep1Done');
  String get practiceSeqCoverStep2 => _v('practiceSeqCoverStep2');
  String get practiceSeqCoverStep2Hint => _v('practiceSeqCoverStep2Hint');
  String get practiceSeqCoverStep2Done => _v('practiceSeqCoverStep2Done');
  String get practiceSetCoverStep1 => _v('practiceSetCoverStep1');
  String get practiceSetCoverStep1Hint => _v('practiceSetCoverStep1Hint');
  String get practiceSetCoverStep1Done => _v('practiceSetCoverStep1Done');
  String get practiceCoverFinishStep => _v('practiceCoverFinishStep');
  String get practiceCoverBlockStep1 => _v('practiceCoverBlockStep1');
  String get practiceCoverBlockStep1Hint => _v('practiceCoverBlockStep1Hint');

  // Joker lessons.
  String get practiceJokerIdentityStep1 => _v('practiceJokerIdentityStep1');
  String get practiceJokerIdentityStep1Hint =>
      _v('practiceJokerIdentityStep1Hint');
  String get practiceJokerIdentityStep1Done =>
      _v('practiceJokerIdentityStep1Done');
  String get practiceJokerReplaceStep1 => _v('practiceJokerReplaceStep1');
  String get practiceJokerReplaceStep1Hint =>
      _v('practiceJokerReplaceStep1Hint');
  String get practiceJokerReplaceStep1Done =>
      _v('practiceJokerReplaceStep1Done');
  String get practiceJokerReplaceStep2 => _v('practiceJokerReplaceStep2');
  String get practiceJokerReplaceStep2Hint =>
      _v('practiceJokerReplaceStep2Hint');
  String get practiceJokerReplaceStep2Hold =>
      _v('practiceJokerReplaceStep2Hold');

  // Final discard lesson.
  String get practiceFinalDiscardStep1 => _v('practiceFinalDiscardStep1');
  String get practiceFinalDiscardStep1Hint =>
      _v('practiceFinalDiscardStep1Hint');
  String get practiceFinalDiscardStep1Done =>
      _v('practiceFinalDiscardStep1Done');
  String get practiceFinalDiscardStep2 => _v('practiceFinalDiscardStep2');
  String get practiceFinalDiscardCompletion =>
      _v('practiceFinalDiscardCompletion');

  // Normal finish lesson.
  String get practiceNormalFinishStep1 => _v('practiceNormalFinishStep1');
  String get practiceNormalFinishStep1Done =>
      _v('practiceNormalFinishStep1Done');
  String get practiceNormalFinishStep2 => _v('practiceNormalFinishStep2');
  String get practiceNormalFinishStep2Hint =>
      _v('practiceNormalFinishStep2Hint');
  String get practiceNormalFinishStep3 => _v('practiceNormalFinishStep3');
  String get practiceNormalFinishCompletion =>
      _v('practiceNormalFinishCompletion');

  // Perfect-hand finish lesson. The hand stages every set without ever
  // reaching the 51 opening; laying the whole hand finishes outright.
  String get practicePerfectHandTwos => _v('practicePerfectHandTwos');
  String get practicePerfectHandTwosHint => _v('practicePerfectHandTwosHint');
  String get practicePerfectHandTwosDone => _v('practicePerfectHandTwosDone');
  String get practicePerfectHandThrees => _v('practicePerfectHandThrees');
  String get practicePerfectHandThreesHint =>
      _v('practicePerfectHandThreesHint');
  String get practicePerfectHandThreesDone =>
      _v('practicePerfectHandThreesDone');
  String get practicePerfectHandFours => _v('practicePerfectHandFours');
  String get practicePerfectHandFoursHint => _v('practicePerfectHandFoursHint');
  String get practicePerfectHandFoursDone => _v('practicePerfectHandFoursDone');
  String get practicePerfectHandFives => _v('practicePerfectHandFives');
  String get practicePerfectHandFivesHint => _v('practicePerfectHandFivesHint');
  String get practicePerfectHandFivesDone => _v('practicePerfectHandFivesDone');
  String get practicePerfectHandStep2 => _v('practicePerfectHandStep2');
  String get practicePerfectHandCompletion =>
      _v('practicePerfectHandCompletion');

  // Joker final-discard lesson.
  String get practiceJokerOutStep1 => _v('practiceJokerOutStep1');
  String get practiceJokerOutStep1Hint => _v('practiceJokerOutStep1Hint');
  String get practiceJokerOutStep1Done => _v('practiceJokerOutStep1Done');
  String get practiceJokerOutStep2 => _v('practiceJokerOutStep2');
  String get practiceJokerOutStep2Hint => _v('practiceJokerOutStep2Hint');
  String get practiceJokerOutCompletion => _v('practiceJokerOutCompletion');

  // Fifty lessons.
  String get practiceFiftyClaimStep1 => _v('practiceFiftyClaimStep1');
  String get practiceFiftyClaimStep1Hint => _v('practiceFiftyClaimStep1Hint');
  String get practiceFiftyClaimStep2 => _v('practiceFiftyClaimStep2');
  String get practiceFiftyClaimStep2Hint => _v('practiceFiftyClaimStep2Hint');
  String get practiceFiftyClaimStep2Done => _v('practiceFiftyClaimStep2Done');
  String get practiceFiftyClaimStep3 => _v('practiceFiftyClaimStep3');
  String get practiceFiftyClaimStep4 => _v('practiceFiftyClaimStep4');
  String get practiceFiftyClaimCompletion => _v('practiceFiftyClaimCompletion');
  String get practiceFiftyScoringStep1 => _v('practiceFiftyScoringStep1');
  String get practiceFiftyScoringStep2 => _v('practiceFiftyScoringStep2');
  String get practiceFiftyScoringStep2Hint =>
      _v('practiceFiftyScoringStep2Hint');
  String get practiceFiftyScoringStep3 => _v('practiceFiftyScoringStep3');
  String get practiceFiftyMissed => _v('practiceFiftyMissed');
  String get practiceRestartLesson => _v('practiceRestartLesson');

  String get practiceFiftyScoringCompletion =>
      _v('practiceFiftyScoringCompletion');

  // Strictness tier explainer.
  String get practiceTiersIntro => _v('practiceTiersIntro');
  String get practiceTiersGotIt => _v('practiceTiersGotIt');
  String get practiceTierCoachingBody => _v('practiceTierCoachingBody');
  String get practiceTierStandardBody => _v('practiceTierStandardBody');
  String get practiceTierStrictBody => _v('practiceTierStrictBody');
  String get practiceTierTableBody => _v('practiceTierTableBody');

  // Strict / Table penalty demos. The same trapped-cover throw the table
  // mechanics pack blocked, now offered as a paid mistake on the stricter
  // tiers.
  String get practiceStrictPenaltyStep1 => _v('practiceStrictPenaltyStep1');
  String get practiceStrictPenaltyStep1Hint =>
      _v('practiceStrictPenaltyStep1Hint');
  String get practiceStrictPenaltyStep1Done =>
      _v('practiceStrictPenaltyStep1Done');
  String get practiceStrictPenaltyCompletion =>
      _v('practiceStrictPenaltyCompletion');
  String get practiceTablePenaltyStep1 => _v('practiceTablePenaltyStep1');
  String get practiceTablePenaltyStep1Hint =>
      _v('practiceTablePenaltyStep1Hint');
  String get practiceTablePenaltyStep1Done =>
      _v('practiceTablePenaltyStep1Done');
  String get practiceTablePenaltyCompletion =>
      _v('practiceTablePenaltyCompletion');

  String get turn => isRtl ? 'الدور' : 'Turn';
  String get starter => isRtl ? 'البداية' : 'Starter';
  String get out => isRtl ? 'خارج' : 'Out';
  String get matchWinner => isRtl ? 'فائز المباراة' : 'Match winner';
  String get nextStarter => isRtl ? 'البداية التالية' : 'Next starter';
  String get roundDrawn => isRtl ? 'الجولة تعادلت' : 'Round drawn';
  String get roundScore => isRtl ? 'نقاط الجولة' : 'Round score';
  String get openMeld => isRtl ? 'افتح مجموعة' : 'Open meld';
  String get meld => isRtl ? 'مجموعة' : 'Meld';
  String get openNeed => isRtl ? 'تحتاج افتتاح' : 'Open need';
  String get collapseMeld => isRtl ? 'اطو المجموعة' : 'Collapse meld';
  String get expandMeld => isRtl ? 'وسع المجموعة' : 'Expand meld';
  String get takeThisMeldBack =>
      isRtl ? 'استرجع هذه المجموعة' : 'Take this meld back';
  String get playSelectedMeld =>
      isRtl ? 'العب المجموعة المحددة' : 'Play selected meld';
  String get faceDownCard => isRtl ? 'ورقة مقلوبة' : 'Face-down card';
  String get offlineFirst => isRtl ? 'يعمل دون اتصال' : 'Offline-first';
  String get noAdsOrPaidLocks =>
      isRtl ? 'بدون إعلانات أو أقفال مدفوعة' : 'No ads or paid locks';
  String get licenseNotDeclared =>
      isRtl ? 'لم يعلن الترخيص.' : 'License not declared.';

  // -- Coaching tier hints --------------------------------------------------
  // Copy for the proactive coaching layer. Cover and joker advice is framed
  // as a positive "keep" hint; only the defensive-discard insight is framed
  // as something to avoid (it is a legal move). EN reviewed; AR drafted and
  // pending owner review (issue #54, label 🙋 hitl).

  /// Eyebrow label shown on every coach callout.
  String get coachLabel => isRtl ? 'المدرب' : 'Coach';

  /// "Coaching tips" toggle title (pause overlay + settings).
  String get coachingTips => isRtl ? 'تلميحات التدريب' : 'Coaching tips';

  /// "Coaching tips" toggle subtitle.
  String get coachingTipsDescription => isRtl
      ? 'أظهر تلميحات حسب الموقف وأبرِز الأوراق التي تشير إليها (وضع التدريب فقط).'
      : 'Show contextual hints and ring the cards they point to (coaching tier only).';

  /// Generic noun used when a referenced card has no resolved identity.
  String get coachThisCard => isRtl ? 'هذه الورقة' : 'this card';

  String get coachFinishTitle => isRtl ? 'يمكنك الفوز' : 'You can win';

  String get coachFinishBody => isRtl
      ? 'أفرِغ يدك هذا الدور لتفوز بالجولة.'
      : 'Empty your hand this turn to win the round.';

  String get coachFiftyTitle => isRtl ? 'خمسين!' : 'Khamsin!';

  String coachFiftyBody(CardIdentity? card) {
    final name = card != null ? cardName(card) : coachThisCard;
    return isRtl
        ? 'طالِب بالخمسين على $name.'
        : 'Claim the Fifty on the $name.';
  }

  String get coachOpenNowTitle =>
      isRtl ? 'يمكنك الافتتاح الآن' : 'You can open now';

  String get coachOpenNowBody => isRtl
      ? 'هذه الأوراق تحقق قيمة الافتتاح. انزِلها على الطاولة.'
      : 'These cards meet the opening value. Lay them on the table.';

  String get coachOpeningProgressTitle =>
      isRtl ? 'تتقدّم نحو الافتتاح' : 'Building toward opening';

  String coachOpeningProgressBody({
    required int requirement,
    required int best,
    required int shortfall,
  }) {
    return isRtl
        ? 'أفضل مجموعة لديك بقيمة $best. تحتاج $requirement للافتتاح، باقٍ $shortfall.'
        : 'Your best meld is worth $best. You need $requirement to open, $shortfall more to go.';
  }

  String coachOpeningProgressNoMeldBody(int requirement) {
    return isRtl
        ? 'تحتاج $requirement للافتتاح. ابدأ بتجميع مجموعة بهذه القيمة.'
        : 'You need $requirement to open. Start gathering a meld worth that much.';
  }

  /// Appended to the opening-progress hint when a discard is also recommended,
  /// so one hint says both what to keep and what to throw.
  String coachDiscardToBuildSuffix(CardIdentity? card) {
    final name = card != null ? cardName(card) : coachThisCard;
    return isRtl
        ? 'ارمِ $name لمواصلة البناء.'
        : 'Discard the $name to keep building.';
  }

  String get coachPlayMeldTitle =>
      isRtl ? 'يمكنك إنزال مجموعة' : 'You can lay down a meld';

  String get coachPlayMeldBody => isRtl
      ? 'هذه الأوراق تكوّن مجموعة قانونية. أنزلها الآن، أو احتفظ بها لتكبيرها أو للتحضير لخمسين.'
      : 'These cards form a legal meld. Lay them down now, or hold them to build '
            'a bigger meld or set up a Fifty.';

  /// Appended to the play-meld hint when a loose card can ALSO be laid off as a
  /// cover this turn, so one hint shows both plays.
  String coachPlayMeldAlsoCoverSuffix(CardIdentity? card) {
    final name = card != null ? cardName(card) : coachThisCard;
    return isRtl
        ? 'ويمكنك أيضًا لعب $name كتغطية على المجموعة المميّزة.'
        : 'You can also lay the $name onto the highlighted meld.';
  }

  String get coachPickupTitle => isRtl ? 'خذ ورقة الرمي' : 'Take the discard';

  String coachPickupBody(CardIdentity? card) {
    final name = card != null ? cardName(card) : coachThisCard;
    return isRtl
        ? 'أخذ $name يكمل إحدى مجموعاتك.'
        : 'Taking the $name completes one of your melds.';
  }

  String get coachCoverKeepTitle => isRtl ? 'تستحق الاحتفاظ' : 'Worth keeping';

  String coachCoverKeepBody(CardIdentity? card) {
    final name = card != null ? cardName(card) : coachThisCard;
    // A KEEP hint (not an act-now hint): it extends a meld you already own, so
    // hold it rather than discard it. Playing it off is the separate "Lay it
    // off" (playCover) hint.
    return isRtl
        ? 'احتفظ بـ $name؛ فهي تمدّد مجموعتك المميّزة على الطاولة.'
        : 'Keep the $name — it extends your highlighted meld on the table.';
  }

  String get coachDiscardTitle => isRtl ? 'أنهِ دورك' : 'End your turn';

  String coachDiscardBody(CardIdentity? card) {
    final name = card != null ? cardName(card) : coachThisCard;
    return isRtl
        ? '$name هي أقل ورقة فائدة لك، ارمِها لإنهاء دورك.'
        : 'The $name is your least useful card, so discard it to end your turn.';
  }

  String get coachDrawTitle => isRtl ? 'اسحب ورقة' : 'Draw a card';

  String get coachDrawBody => isRtl
      ? 'لا توجد حركة أفضل الآن. اسحب من مجموعة السحب وواصل.'
      : 'No stronger move right now. Draw from the stock and carry on.';

  /// Draw hint for an unopened seat: the draw instruction with the opening
  /// progress folded in so the shortfall is not lost behind the draw advice.
  String coachDrawBodyWithProgress({
    required int best,
    required int shortfall,
  }) {
    return isRtl
        ? 'اسحب من مجموعة السحب لتقترب من الافتتاح. أفضل مجموعة لديك بقيمة $best، باقٍ $shortfall.'
        : 'Draw from the stock to build toward opening. Your best meld is worth $best, $shortfall to go.';
  }

  String get coachPlayCoverTitle => isRtl ? 'العب التغطية' : 'Lay it off';

  String coachPlayCoverBody(CardIdentity? card) {
    final name = card != null ? cardName(card) : coachThisCard;
    return isRtl
        ? 'العب $name على المجموعة المميّزة على الطاولة، ثم أنهِ دورك برمي ورقة.'
        : 'Play the $name onto the highlighted meld, then discard to end your '
              'turn.';
  }

  /// Finish-by-cover: covering every highlighted card empties the hand and wins
  /// the round. Reuses [coachFinishTitle] ("You can win").
  String get coachCoverFinishBody => isRtl
      ? 'غطِّ هذه الأوراق على المجموعات المميّزة لتفرِغ يدك وتفوز.'
      : 'Cover these onto the highlighted melds to empty your hand and win.';

  /// Several independent covers are available; the player can lay one off and
  /// still play or discard the other(s).
  String get coachCoverChoiceBody => isRtl
      ? 'أيّ منها يصلح: غطِّ بإحداها، والعب أو ارمِ الأخرى.'
      : 'Either works — cover with one, and play or discard the other.';

  String get coachJokerTitle => isRtl ? 'استعِد الجوكر' : 'Reclaim your joker';

  String coachJokerBody(CardIdentity? card) {
    final name = card != null ? cardName(card) : coachThisCard;
    // Action hint, not a keep hint: it tells the player to make the swap now,
    // and the ring on the hand card + table meld points at where.
    return isRtl
        ? 'استخدم $name لاستبدال الجوكر في المجموعة المميّزة على الطاولة.'
        : 'Use your $name to swap in for the joker in the highlighted meld.';
  }

  String get coachDefensiveTitle => isRtl ? 'احتفظ بها الآن' : 'Hold this back';

  String coachDefensiveBody({
    required CardIdentity? card,
    required PlayerSeat opponent,
    CardRank? rank,
    CardSuit? suit,
  }) {
    final name = card != null ? cardName(card) : coachThisCard;
    final who = seatLabel(opponent);
    final String target;
    if (rank != null && suit != null) {
      target = isRtl
          ? '${rankWord(rank)} و${suitWord(suit)}'
          : 'the ${rankWord(rank)} and ${suitWord(suit)}';
    } else if (rank != null) {
      target = isRtl ? rankWord(rank) : 'the ${rankWord(rank)}';
    } else {
      target = suitWord(suit!);
    }
    return isRtl
        ? 'تجنّب رمي $name. $who يجمع $target.'
        : 'Avoid discarding the $name. $who is collecting $target.';
  }

  String decksValue(int value) => isRtl ? '$value رزم' : '$value decks';

  String fiftySecondsValue(int value) => isRtl ? '$value ثوان' : '${value}s';

  String houseRulesSummary({
    required int deckCount,
    required int fiftyTimerSeconds,
  }) {
    if (isRtl) {
      return '$deckCount رزم  ·  $fiftyTimerSeconds ثوان للخمسين';
    }
    return '$deckCount decks  ·  ${fiftyTimerSeconds}s fifty';
  }

  /// Player-facing label for a [TableStrictness] tier.
  String tableStrictnessLabel(TableStrictness tier) {
    if (isRtl) {
      return switch (tier) {
        TableStrictness.coaching => 'تدريب',
        TableStrictness.standard => 'قياسي',
        TableStrictness.strict => 'صارم',
        TableStrictness.table => 'طاولة',
      };
    }
    return switch (tier) {
      TableStrictness.coaching => 'Coaching',
      TableStrictness.standard => 'Standard',
      TableStrictness.strict => 'Strict',
      TableStrictness.table => 'Table',
    };
  }

  /// Player-facing description for a [TableStrictness] tier.
  String tableStrictnessDescription(TableStrictness tier) {
    if (isRtl) {
      return switch (tier) {
        TableStrictness.coaching =>
          'يمنع الحركات غير القانونية ويعرض تلميحات استباقية حسب الموقف.',
        TableStrictness.standard =>
          'يمنع الحركات غير القانونية، بدون تلميحات استباقية.',
        TableStrictness.strict => 'يسمح بأخطاء محددة مع +3، بدون تلميحات.',
        TableStrictness.table =>
          'يسمح بأخطاء مع +17 وإخراج اللاعب، بدون تلميحات.',
      };
    }
    return switch (tier) {
      TableStrictness.coaching =>
        'Blocks illegal moves and shows proactive contextual hints.',
      TableStrictness.standard => 'Blocks illegal moves, no proactive hints.',
      TableStrictness.strict =>
        'Allows selected mistakes with +3 penalty, no hints.',
      TableStrictness.table =>
        'Allows selected mistakes with +17 and round-out, no hints.',
    };
  }

  String cardThemePreview(String themeLabel) {
    return isRtl
        ? 'معاينة سمة أوراق $themeLabel'
        : '$themeLabel card theme preview';
  }

  String representedJoker(String represented) {
    return isRtl
        ? 'يمثل $represented في المجموعات والتكميلات والتسجيل.'
        : 'Represents $represented for melds, covers, and scoring.';
  }

  String representedJokerGuided(String represented) {
    return isRtl
        ? 'يمثل $represented في المجموعات والتكميلات والتسجيل. عرض الذاكرة يكشفه لفترة قصيرة ثم يخفيه.'
        : 'Represents $represented for melds, covers, and scoring. Memory display reveals this briefly, then quiets it.';
  }

  String cardValue(int value) => isRtl ? 'القيمة $value.' : 'Value $value.';

  String cardValueGuided(int value) {
    return isRtl
        ? 'القيمة $value. يدخل في مجموعات الرتبة الواحدة أو سلاسل النوع الواحد عندما تكون قانونية.'
        : 'Value $value. Fits same-rank sets and same-suit runs when legal.';
  }

  String cardValueWithSuit(int value, String suit) {
    return isRtl ? 'القيمة $value. $suit.' : 'Value $value. $suit.';
  }

  String seatLabel(PlayerSeat seat) {
    return switch (seat) {
      PlayerSeat.south => humanSeat,
      PlayerSeat.east => cpuEast,
      PlayerSeat.north => cpuNorth,
      PlayerSeat.west => cpuWest,
    };
  }

  String rankWord(CardRank rank) {
    if (isRtl) {
      return switch (rank) {
        CardRank.ace => 'آس',
        CardRank.two => 'اثنان',
        CardRank.three => 'ثلاثة',
        CardRank.four => 'أربعة',
        CardRank.five => 'خمسة',
        CardRank.six => 'ستة',
        CardRank.seven => 'سبعة',
        CardRank.eight => 'ثمانية',
        CardRank.nine => 'تسعة',
        CardRank.ten => 'عشرة',
        CardRank.jack => 'ولد',
        CardRank.queen => 'ملكة',
        CardRank.king => 'ملك',
      };
    }
    return switch (rank) {
      CardRank.ace => 'Ace',
      CardRank.two => 'Two',
      CardRank.three => 'Three',
      CardRank.four => 'Four',
      CardRank.five => 'Five',
      CardRank.six => 'Six',
      CardRank.seven => 'Seven',
      CardRank.eight => 'Eight',
      CardRank.nine => 'Nine',
      CardRank.ten => 'Ten',
      CardRank.jack => 'Jack',
      CardRank.queen => 'Queen',
      CardRank.king => 'King',
    };
  }

  String suitWord(CardSuit suit) {
    if (isRtl) {
      return switch (suit) {
        CardSuit.spades => 'البستوني',
        CardSuit.hearts => 'القلوب',
        CardSuit.diamonds => 'الديناري',
        CardSuit.clubs => 'السباتي',
      };
    }
    return switch (suit) {
      CardSuit.spades => 'Spades',
      CardSuit.hearts => 'Hearts',
      CardSuit.diamonds => 'Diamonds',
      CardSuit.clubs => 'Clubs',
    };
  }

  String cardName(CardIdentity identity) {
    final rank = rankWord(identity.rank);
    final suit = suitWord(identity.suit);
    return isRtl ? '$rank من $suit' : '$rank of $suit';
  }

  String jokerAs(CardIdentity identity) {
    return isRtl
        ? 'جوكر كـ ${cardName(identity)}'
        : 'Joker as ${cardName(identity)}';
  }

  String jokerRepresenting(String represented) {
    return isRtl ? 'جوكر يمثل $represented' : 'Joker representing $represented';
  }

  String jokerDeclaredBySeat(PlayerSeat seat, CardIdentity identity) {
    final name = cardName(identity);
    return isRtl
        ? '${seatLabel(seat)} أعلن الجوكر كـ $name.'
        : '${seatLabel(seat)} declared joker as $name.';
  }

  String youDeclaredJoker(CardIdentity identity) {
    final name = cardName(identity);
    return isRtl ? 'أعلنت الجوكر كـ $name.' : 'You declared joker as $name.';
  }

  String playerFinished(PlayerSeat seat) {
    return isRtl
        ? '${seatLabel(seat)} أنهى الجولة'
        : '${seatLabel(seat)} finished';
  }

  String playerHitFifty(PlayerSeat seat) {
    return isRtl
        ? '${seatLabel(seat)} أعلن الخمسين'
        : '${seatLabel(seat)} hit Fifty';
  }

  String roundToPlay(int roundNumber, PlayerSeat seat) {
    final seatName = seatLabel(seat);
    return isRtl
        ? 'الجولة $roundNumber، دور $seatName'
        : 'Round $roundNumber, ${seatName.toLowerCase()} to play';
  }

  String startedBy(String starterLabel) {
    return isRtl ? 'بدأها $starterLabel' : 'Started by $starterLabel';
  }

  String onTheTable(String currentLabel) {
    return isRtl ? 'على الطاولة: $currentLabel' : 'On the table: $currentLabel';
  }

  String cardsCountTag(int cards) => isRtl ? '$cards أوراق' : 'cards $cards';

  String meldsAndCardsCount(int melds, int cards) {
    return isRtl ? '$meldsم · $cards' : '${melds}m · $cards';
  }

  String get selectedCardsDoNotFormLegalMeld => isRtl
      ? 'الأوراق المحددة لا تشكل مجموعة قانونية.'
      : 'Selected cards do not form a legal meld.';

  String get legalMeld => isRtl ? 'مجموعة قانونية.' : 'Legal meld.';

  String openingReady(int value) {
    return isRtl
        ? 'الافتتاح جاهز (القيمة $value).'
        : 'Opening ready (value $value).';
  }

  String valueNeedsOpening(int value, int requirement) {
    return isRtl
        ? 'القيمة $value. تحتاج $requirement للافتتاح.'
        : 'Value $value. Needs $requirement to open.';
  }

  String nextRoundStartsWith(PlayerSeat seat) {
    return isRtl
        ? 'الجولة التالية تبدأ مع ${seatLabel(seat)}.'
        : 'Next round starts with ${seatLabel(seat)}.';
  }

  String playerWinsMatch(PlayerSeat seat) {
    return isRtl
        ? '${seatLabel(seat)} فاز بالمباراة.'
        : '${seatLabel(seat)} wins the match.';
  }

  String matchWinnerHeadline(PlayerSeat seat) {
    if (seat == PlayerSeat.south) {
      return youWinTheMatch;
    }
    return isRtl
        ? '${seatLabel(seat)} فاز بالمباراة'
        : '${seatLabel(seat)} wins the match';
  }

  String eliminatedInRound(int round) {
    return isRtl ? 'خرج في الجولة $round' : 'Eliminated in round $round';
  }

  String roundsPlayed(int rounds) {
    if (isRtl) {
      return rounds == 1 ? 'لُعبت جولة واحدة' : 'لُعبت $rounds جولات';
    }
    return rounds == 1 ? '1 round played' : '$rounds rounds played';
  }

  String cpuTurnSafetyCapReached(int limit, PlayerSeat seat) {
    return isRtl
        ? 'توقف دور اللاعب الآلي بعد $limit حركة عند ${seatLabel(seat)}.'
        : 'CPU turn safety cap $limit reached at ${seatLabel(seat)}.';
  }

  String cpuTurnPaused(PlayerSeat seat) {
    return isRtl
        ? 'توقف دور اللاعب الآلي عند ${seatLabel(seat)}.'
        : 'CPU turn paused at ${seatLabel(seat)}.';
  }

  String roundResultDetailNormal() {
    return isRtl
        ? 'أضيفت الأوراق المتبقية. الفائز يأخذ -1.'
        : 'Remaining cards were added. Winner receives -1.';
  }

  String roundResultDetailFifty({required bool firstRoundException}) {
    if (isRtl) {
      return firstRoundException
          ? 'خمسين الجولة الأولى: الفائز يأخذ -1؛ الرامي يأخذ الأوراق زائد 3.'
          : 'الخمسين: الفائز يأخذ -3؛ الرامي يأخذ الأوراق زائد 3.';
    }
    return firstRoundException
        ? 'First-round Fifty: winner receives -1; discarder takes cards plus 3.'
        : 'Fifty: winner receives -3; discarder takes cards plus 3.';
  }

  String roundResultDetailDraw() {
    return isRtl
        ? 'نفدت كومة السحب. لا توجد تغييرات في النقاط.'
        : 'Stock exhausted. No score changes.';
  }

  String gameMessage(String message) {
    if (!isRtl) {
      return message;
    }

    final openingBelow = RegExp(
      r'^Opening value (\d+) is below (\d+)\.$',
    ).firstMatch(message);
    if (openingBelow != null) {
      return 'قيمة الافتتاح ${openingBelow.group(1)} أقل من ${openingBelow.group(2)}.';
    }

    final openingSufficient = RegExp(
      r'^Opening value (\d+) is sufficient\.$',
    ).firstMatch(message);
    if (openingSufficient != null) {
      return 'قيمة الافتتاح ${openingSufficient.group(1)} كافية.';
    }

    final jokerAsMatch = RegExp(r'^(.+) Joker as (.+)\.$').firstMatch(message);
    if (jokerAsMatch != null) {
      return '${gameMessage(jokerAsMatch.group(1)!.trim())} جوكر كـ ${jokerAsMatch.group(2)}.';
    }

    return switch (message) {
      'That card cannot be discarded now.' => 'لا يمكن رمي هذه الورقة الآن.',
      'Drop a valid meld, cover, or joker replacement.' =>
        'أسقط مجموعة صحيحة أو تكملة أو استبدال جوكر.',
      'That card does not fit this meld.' =>
        'هذه الورقة لا تناسب هذه المجموعة.',
      'Could not save the table. You can keep playing.' =>
        'تعذر حفظ الطاولة. يمكنك متابعة اللعب.',
      'Only the immediate next player can claim Fifty.' =>
        'اللاعب التالي مباشرة فقط يمكنه إعلان الخمسين.',
      'Fifty timer expired.' => 'انتهى مؤقت الخمسين.',
      'Fifty must use the discarded card in the finish.' =>
        'يجب أن يستخدم الخمسين الورقة المرمية في الإنهاء.',
      'Valid Fifty.' => 'خمسين صحيح.',
      'Fifty claimed.' => 'أُعلن الخمسين.',
      'Fifty claimed — prove the finish before ending the turn.' =>
        'أُعلن الخمسين — أثبت الإنهاء قبل نهاية الدور.',
      'Fifty proven.' => 'أُثبت الخمسين.',
      'The claimed card must be used in a meld or cover, never discarded.' =>
        'الورقة المعلنة يجب أن تُستخدم في مجموعة أو تكميلة، ولا تُرمى أبدا.',
      'That last card does not prove the Fifty.' =>
        'هذه الورقة الأخيرة لا تثبت الخمسين.',
      'That card cannot end the proof turn — pick a plain discard.' =>
        'هذه الورقة لا تنهي دور الإثبات — اختر رمية عادية.',
      'Prove the Fifty before ending the turn.' =>
        'أثبت الخمسين قبل إنهاء الدور.',
      'The claimed card cannot be returned — prove the Fifty or end the '
          'turn.' =>
        'لا يمكن إرجاع الورقة المعلنة — أثبت الخمسين أو أنهِ الدور.',
      'The taken card cannot be discarded — use it in a meld or cover.' =>
        'لا يمكن رمي الورقة المأخوذة — استخدمها في مجموعة أو تكميلة.',
      'Use or return the taken card before ending the turn.' =>
        'استخدم الورقة المأخوذة أو أرجعها قبل إنهاء الدور.',
      'Take back your staged melds before returning the taken card.' =>
        'استرجع مجموعاتك المرحلية قبل إرجاع الورقة المأخوذة.',
      'Final discard may use a cover.' => 'يمكن أن تكون الرمية الأخيرة تكملة.',
      'This card is a cover and cannot be discarded normally.' =>
        'هذه الورقة تكملة ولا يمكن رميها بشكل عادي.',
      'Card can be discarded.' => 'يمكن رمي الورقة.',
      'A finish needs exactly one final discard.' =>
        'الإنهاء يحتاج رمية أخيرة واحدة بالضبط.',
      'A finish needs played cards before the final discard.' =>
        'الإنهاء يحتاج أوراقا ملعوبة قبل الرمية الأخيرة.',
      'Unopened players must open or finish a perfect hand.' =>
        'اللاعب الذي لم يفتح يجب أن يفتح أو ينهي يدا كاملة.',
      'Perfect hand finish bypasses opening.' =>
        'إنهاء اليد الكاملة يتجاوز الافتتاح.',
      'Valid finish.' => 'إنهاء صحيح.',
      'Stock still has cards.' => 'ما زالت كومة السحب تحتوي أوراقا.',
      'Only an immediate finish may continue after empty stock.' =>
        'بعد نفاد السحب، لا يستمر اللعب إلا بإنهاء مباشر.',
      'Stock is empty; round ends as a draw.' =>
        'كومة السحب فارغة؛ تنتهي الجولة بالتعادل.',
      'Valid set.' => 'مجموعة صحيحة.',
      'Valid low-ace sequence.' => 'سلسلة آس منخفض صحيحة.',
      'Valid high-ace sequence.' => 'سلسلة آس مرتفع صحيحة.',
      'Jokers cannot be discarded during normal play.' =>
        'لا يمكن رمي الجوكر أثناء اللعب العادي.',
      'This strictness blocks that illegal action.' =>
        'مستوى الصرامة هذا يمنع هذه الحركة غير القانونية.',
      'Strict penalty: +3.' => 'عقوبة الوضع الصارم: +3.',
      'Table mistake: +17 and out of this round.' =>
        'خطأ وضع الطاولة: +17 وخروج من هذه الجولة.',
      'This player has already opened.' => 'هذا اللاعب فتح بالفعل.',
      'Covers cannot satisfy opening.' => 'التكميلات لا تحقق الافتتاح.',
      'Opening needs at least one meld.' =>
        'الافتتاح يحتاج مجموعة واحدة على الأقل.',
      'Table plays returned to your hand.' => 'أعيدت لعبات الطاولة إلى يدك.',
      'Covers returned to your hand.' => 'أعيدت التكميلات إلى يدك.',
      'Opening melds returned to your hand.' =>
        'أعيدت مجموعات الافتتاح إلى يدك.',
      'Valid table play.' => 'لعب طاولة صحيح.',
      _ => message,
    };
  }
}

/// Makes the current localized string catalog available to descendants.
class AppStringsScope extends InheritedWidget {
  /// Creates a string scope.
  const AppStringsScope({
    super.key,
    required this.strings,
    required super.child,
  });

  /// Active localized strings.
  final AppStrings strings;

  /// Reads the nearest string scope, falling back to English.
  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    return scope?.strings ?? AppStrings.english;
  }

  @override
  bool updateShouldNotify(covariant AppStringsScope oldWidget) {
    return oldWidget.strings != strings;
  }
}

/// Convenience access for localized strings in widgets.
extension AppStringsBuildContext on BuildContext {
  /// Active string catalog.
  AppStrings get strings => AppStrings.of(this);
}

const _englishValues = {
  'appTitle': 'Hareeg Table',
  'homeTitle': 'Hareeg Table',
  'newGame': 'New Game',
  'continueGame': 'Continue',
  'settings': 'Settings',
  'rulesHelp': 'Rules / Help',
  'noSavedMatch': 'No saved match yet',
  'checkingSavedMatch': 'Checking saved match...',
  'abandonSavedMatch': 'Abandon saved match',
  'classicModeDescription':
      'Four seats, anti-clockwise turns, 51 opening, covers, jokers, and Fifty.',
  'setupTitle': 'Classic Hareeg setup',
  'startTable': 'Start Table',
  'tableTitle': 'Classic Hareeg Table',
  'humanSeat': 'You',
  'stock': 'Stock',
  'discard': 'Discard',
  'meldZone': 'Meld area',
  'drawStock': 'Draw Stock',
  'discardCard': 'Discard',
  'takeDiscard': 'Take Discard',
  'returnDiscard': 'Return + Draw',
  'takeBackMelds': 'Take Back Melds',
  'pendingDiscard': 'Pending discard',
  'settingsTitle': 'Settings',
  'helpTitle': 'Classic Hareeg rules',
  'helpIntro':
      'A quick table reference for Classic Hareeg rules, scoring, Fifty, and resume behavior.',
  'helpSetupTitle': 'Setup',
  'helpSetupBody':
      'Classic Hareeg uses four seats, one human player, three CPU players, and anti-clockwise turns. The app defaults to two decks and two jokers so there are enough cards for a four-seat deal. The starter receives 15 cards and skips the first draw.',
  'helpTurnFlowTitle': 'Turn flow',
  'helpTurnFlowBody':
      'The starter begins in action phase. Other turns begin by drawing from stock or taking the previous discard. A taken discard becomes pending: it may be used in a meld or cover at any point of the turn, but the turn cannot end while it sits unused and it can never be the turn\'s closing discard. Until it is used, it may be returned instead.',
  'helpOpeningTitle': 'Opening and benchmark',
  'helpOpeningBody':
      'The default opening requirement is 51, with 75 available as a setup option. A player opens by placing one or more new melds whose combined value reaches the current requirement. Covers do not count toward opening. The first opener owns the benchmark and can raise it until a second player opens, then the benchmark locks.',
  'helpCoversTitle': 'Covers',
  'helpCoversBody':
      'A cover is a card that can extend an existing table meld right now. Sequence covers are direct neighbors only; after a card is placed, chained covers may become legal. Covers cannot normally be discarded by opened or unopened players, but a cover may be the final discard when finishing.',
  'helpJokersTitle': 'Jokers',
  'helpJokersBody':
      'Jokers represent a chosen card identity when placed in a meld or cover. If several identities are legal, the human player must choose; CPU players choose deterministically. Opened players may replace a table joker with the represented card and take the joker. Normal joker discard is always blocked, but a joker may be the final discard.',
  'helpFiftyTitle': 'Fifty / Khamsin',
  'helpFiftyBody':
      'After a discard, only the immediate next player can claim Fifty, and only before the timer expires. Claiming takes the thrown card into the hand; the claimant then proves the finish with no timer — melds, covers, or chained covers in any order — and the claimed card must end up in a meld or cover, never as the discard. Coaching and Standard show the Fifty action only when the finish is provable and block ending the turn unproven; on Strict an unproven exit charges +3 and the turn ends normally, on Table it removes the claimant from the round. If the timer is missed, the player may still take the discard normally when legal, but the finish scores as normal instead of Fifty.',
  'helpScoringTitle': 'Scoring',
  'helpScoringBody':
      'Normal winners score -1. In Fifty, the winner scores -3, except the first dealt round uses -1, and the discarder adds remaining cards plus 3. Other active players add remaining card count. Drawn rounds do not change scores. Players at 31 or more are eliminated, and the last remaining player wins.',
  'helpMistakePresetsTitle': 'Mistake handling',
  'helpMistakePresetsBody':
      'Coaching and Standard block illegal actions. Strict allows selected mistakes with +3 and keeps the player in the round. Table allows selected mistakes with +17 and removes that player from the current round. Normal joker discard stays blocked at every strictness.',
  'helpPauseResumeTitle': 'Pause and resume',
  'helpPauseResumeBody':
      'The app saves active Classic Hareeg table state locally at safe table changes. Continue resumes the saved hands, stock, discard pile, turn phase, pending discard, and setup. Abandon saved match clears the local save.',
  'helpPlannedModesTitle': 'Planned modes',
  'helpPlannedModesBody':
      'Hareeg 14 and a dedicated Fifties mode are planned future modes. The first release focuses on Classic Hareeg.',
  'splashTagline': 'Offline Classic Hareeg',
  'splashTapToContinue': 'Tap to continue',
  'scores': 'Scores',
  'pauseTable': 'Pause',
  'skipToNextRound': 'Skip to next round',
  'scoresTitle': 'Match scores',
  'pauseTitle': 'Paused',
  'resumeTable': 'Resume table',
  'leaveTable': 'Leave table',
  'pauseInMatchControls': 'In-match settings',
  'motionSpeedLabel': 'Motion speed',
  'fastCpuTurns': 'Fast CPU turns',
  'fastCpuTurnsDescription':
      'Shorten CPU pauses and card flights so opponent turns resolve faster.',
  'hapticsLabel': 'Table haptics',
  'hapticsHelp': 'Light vibrations on taps, drops, and Fifty.',
  'soundLabel': 'Table sounds',
  'soundHelp': 'Play card movement and table feedback sounds.',
  'highContrastCards': 'High-contrast cues',
  'highContrastCardsDescription':
      'Strengthen card highlights and table pop-ups without changing the selected deck art.',
  'aboutLicenses': 'About & Licenses',
  'aboutHeader': 'Hareeg Table',
  'aboutBody':
      'Open-source Sudanese Hareeg, offline-first, ad-free. Source on GitHub.',
  'licensesThemesHeader': 'Card themes',
  'licensesSoundsHeader': 'Sound effects',
  'kenneyCasinoAudio': 'Kenney Casino Audio',
  'kenneyCasinoAudioAttribution':
      'Kenney.nl Casino Audio, Creative Commons CC0 1.0 Universal.',
  'kenneyCasinoAudioUrl': 'https://kenney.nl/assets/casino-audio',
  'licensesFooter':
      'Bundled assets keep their original CC0 / Public Domain licenses.',
  'playMeld': 'Play meld',
  'placeCover': 'Place cover',
  'replaceJoker': 'Replace joker',
  'claimFifty': 'Claim Fifty',
  'sortModeLabel': 'Sort',
  'sortByRank': 'Rank',
  'sortBySuit': 'Suit',
  'sortManual': 'Manual',
  'sortByRankDescription': 'Rank-major, then suit.',
  'sortBySuitDescription': 'Suit-major, then rank.',
  'sortManualDescription': 'Drag to reorder cards yourself.',
  'tableRules': 'Table rules',
  'tableRulesDescription': 'Deck count and fifty-claim window.',
  'deckCount': 'Deck count',
  'fiftyTimer': 'Fifty timer',
  'handSort': 'Card sorting',
  'handSortDescription': 'Initial sort applied to your hand each round.',
  'tableStrictnessTitle': 'Table strictness',
  'tableStrictnessSectionDescription':
      'Rule enforcement, hints, and joker memory behavior. Locked during an active match.',
  'strictnessLockedActiveMatch':
      'Strictness is locked during an active match. Leave the table and start a new game to change it.',
  'look': 'Look',
  'lookDescription': 'Card faces and the felt under them.',
  'feel': 'Feel',
  'feelDescription': 'Motion, haptics, sound.',
  'language': 'Language',
  'languageDescription': 'Choose the table language.',
  'englishLanguage': 'English',
  'arabicLanguage': 'Arabic',
  'tableSurface': 'Table surface',
  'tableSurfaceDescription':
      'Tap a swatch to switch the material under the cards and meld zones. Rules and card art stay unchanged.',
  'themeLockedActiveMatch': 'Theme picker is locked during an active match.',
  'codeRendered': 'Code-rendered',
  'bundledAsset': 'Bundled asset',
  'smallTableReady': 'Small-table ready',
  'compactQaPending': 'Compact QA pending',
  'cpuDifficulty': 'CPU difficulty',
  'beginner': 'Beginner',
  'casual': 'Casual',
  'skilled': 'Skilled',
  'expert': 'Expert',
  'firstStarter': 'First starter',
  'youStart': 'You start',
  'random': 'Random',
  'openingRequirement': 'Opening requirement',
  'jokers': 'Jokers',
  'houseRules': 'House rules',
  'edit': 'Edit',
  'normal': 'Normal',
  'fast': 'Fast',
  'reduced': 'Reduced',
  'normalMotion': 'Normal motion',
  'fastMotion': 'Fast motion',
  'reducedMotion': 'Reduced motion',
  'sandlineLounge': 'Sandline Lounge',
  'darkFelt': 'Dark felt',
  'lightWood': 'Light wood',
  'midnightSapphire': 'Midnight sapphire',
  'crimsonClay': 'Crimson clay',
  'close': 'Close',
  'empty': 'Empty',
  'noMeldsYet': 'No melds yet',
  'matchOver': 'Match over',
  'youWinTheMatch': 'You win the match',
  'finalStandings': 'Final standings',
  'newMatchSameSetup': 'New match, same setup',
  'wonByFifty': 'Won by Fifty',
  'wonByFinish': 'Won by finish',
  'returnToMenu': 'Return to menu',
  'eliminated': 'Eliminated',
  'nextNow': 'Next now',
  'menu': 'Menu',
  'couldNotSaveTable': 'Could not save the table. You can keep playing.',
  'reportTableIssue': 'Report table issue',
  'exportMatchReport': 'Export match report',
  'matchReportShareReady': 'Match report ready to share.',
  'matchReportCopyFallback':
      'File sharing is not available here. Copy the report JSON instead?',
  'copyReport': 'Copy report',
  'matchReportCopied': 'Match report copied to clipboard.',
  'matchReportCopyFailed': 'Could not copy the match report.',
  'cpuEast': 'CPU East',
  'cpuNorth': 'CPU North',
  'cpuWest': 'CPU West',
  'joker': 'Joker',
  'unassignedJoker': 'Unassigned joker.',
  'unassignedJokerGuided':
      'Unassigned joker. Pick its identity when a legal meld needs it.',
  'onboardingSkip': 'Skip intro',
  'onboardingNext': 'Next',
  'onboardingDone': 'Done',
  'onboardingStartPractice': 'Try guided practice',
  'onboardingStartPlaying': 'Start playing',
  'onboardingWelcomeTitle': 'Welcome to the table',
  'onboardingWelcomeBody':
      'Classic Hareeg is a four-seat card game played anti-clockwise. Build melds, open to the table requirement, and be the first to go out — the last player under 31 points wins the match.',
  'onboardingTurnTitle': 'A turn in three beats',
  'onboardingTurnBody':
      'Draw from stock or take the discard, play melds and covers when you can, then end your turn with a discard. Openings, covers, jokers, and Fifty add the pressure — each one has its own short practice hand.',
  'onboardingLearnTitle': 'Learn your way',
  'onboardingLearnBody':
      'Guided practice teaches one mechanic at a time in short, repeatable mini hands — separate from real matches. The live coach is different: it gives compact hints during real play on the Coaching table tier.',
  'onboardingReadyTitle': 'Ready when you are',
  'onboardingReadyBody':
      'Start with guided practice, or jump straight to a table. You can replay this intro any time from Rules / Help.',
  'practiceTitle': 'Guided practice',
  'practiceIntro':
      'Short mini hands, one mechanic each, ending the moment you show the move. Skip what you know, replay what you forget — this list never blocks normal play.',
  'practiceReplayIntro': 'Replay intro',
  'practiceStatusNotStarted': 'Not started',
  'practiceStatusSkipped': 'Skipped',
  'practiceStatusCompleted': 'Completed',
  'practiceStart': 'Start',
  'practiceReplay': 'Replay',
  'practiceSkip': 'Skip',
  'practiceUnskip': 'Unskip',
  'practiceComingSoon': 'This practice hand arrives in an upcoming update.',
  'practiceFollowStep': 'Good instinct — but follow the current step first.',
  'practiceNextLesson': 'Next lesson',
  'practicePackFundamentalsTitle': 'Fundamentals',
  'practicePackCoreTitle': 'Core turn basics',
  'practicePackTableTitle': 'Table mechanics',
  'practicePackFinishTitle': 'Finishing & Fifty',
  'practicePackTableStrictnessTitle': 'Table strictness',
  'practiceProgress': '{completed} of {total} completed',
  'practiceCardValuesTitle': 'What your cards are worth',
  'practiceCardValuesSummary':
      'Face cards and the ace are 10; number cards are their number.',
  'practiceMeldShapesTitle': 'Sets and runs',
  'practiceMeldShapesSummary':
      'The two meld shapes: same-rank sets and same-suit runs.',
  'practiceTheAceTitle': 'The Ace',
  'practiceTheAceSummary':
      'The ace runs high or low — and a low run that reaches a five flips '
      'it to 1.',
  'practiceTurnRhythmTitle': 'Turn rhythm',
  'practiceTurnRhythmSummary':
      'Draw, play if you can, then discard to end your turn.',
  'practiceFirstMeldTitle': 'Your first meld',
  'practiceFirstMeldSummary':
      'Open the table with one run straight from your own hand.',
  'practiceDiscardOpeningTitle': 'Opening from the discard',
  'practiceDiscardOpeningSummary':
      'Take the thrown card that pushes your opening past 51.',
  'practiceBaitDiscardTitle': 'The bait discard',
  'practiceBaitDiscardSummary':
      'A useful-looking discard is not always worth taking.',
  'practicePendingDiscardTitle': 'Taking the discard',
  'practicePendingDiscardSummary':
      'A taken discard must be used in a play or returned before drawing.',
  'practiceOpeningTitle': 'Opening to 51',
  'practiceOpeningSummary':
      'Stage melds worth the opening requirement in one turn.',
  'practiceBenchmarkTitle': 'Benchmark pressure',
  'practiceBenchmarkSummary':
      'A high first opening raises what everyone else must reach.',
  'practiceSequenceCoverTitle': 'Stacking covers',
  'practiceSequenceCoverSummary':
      'Grow a run by two and fill a second meld in the same turn.',
  'practiceSetCoverTitle': 'Your first cover',
  'practiceSetCoverSummary':
      'Extend another player\'s meld with one card of your own.',
  'practiceCoverDiscardTitle': 'Cover discard rules',
  'practiceCoverDiscardSummary':
      'Why a playable cover usually cannot be thrown away.',
  'practiceJokerIdentityTitle': 'Joker identity',
  'practiceJokerIdentitySummary':
      'Choose exactly what a placed joker represents.',
  'practiceJokerReplacementTitle': 'Joker replacement',
  'practiceJokerReplacementSummary':
      'Swap in the real card to reclaim a joker from the table.',
  'practiceFinalDiscardTitle': 'The final discard',
  'practiceFinalDiscardSummary':
      'Finishing always keeps one last card to throw.',
  'practiceNormalFinishTitle': 'Finishing a round',
  'practiceNormalFinishSummary':
      'Go out cleanly and see how the round is scored.',
  'practicePerfectHandTitle': 'The perfect hand',
  'practicePerfectHandSummary':
      'A whole hand of melds finishes without ever opening.',
  'practiceJokerOutTitle': 'A joker as your last card',
  'practiceJokerOutSummary':
      'A joker cannot be thrown in play — but it can be your closing throw.',
  'practiceFiftyClaimTitle': 'Fifty timing',
  'practiceFiftyClaimSummary':
      'Claim Khamsin from the discard before the window closes.',
  'practiceFiftyScoringTitle': 'Fifty scoring',
  'practiceFiftyScoringSummary':
      'The reward for the winner and the penalty for the discarder.',
  'practiceStrictnessTitle': 'Table strictness tiers',
  'practiceStrictnessSummary':
      'What Coaching, Standard, Strict, and Table expect from you.',
  'practiceStrictPenaltyTitle': 'Strict: the +3 throw',
  'practiceStrictPenaltySummary':
      'On a Strict table, throwing a card the table can use costs +3.',
  'practiceTablePenaltyTitle': 'Table: +17 and out',
  'practiceTablePenaltySummary':
      'On a Table table, the same throw costs +17 and ends your round.',
  'practiceCardValuesPanelTitle': 'What your cards are worth',
  'practiceCardValuesIntro':
      'Opening and scoring both add up card values — here is what each card '
      'is worth.',
  'practiceCardValuesNumberHeading': 'Number cards (2–10)',
  'practiceCardValuesNumberLine':
      'Worth the number on the card. A 7 is 7 points.',
  'practiceCardValuesFaceHeading': 'Ace, Jack, Queen, King',
  'practiceCardValuesFaceLine': 'Each worth 10 points.',
  'practiceCardValuesOutro': 'So three kings are 30, and a six is 6.',
  'practiceCardValue2': '= 2',
  'practiceCardValue5': '= 5',
  'practiceCardValue9': '= 9',
  'practiceCardValue10Each': 'Each = 10',
  'practiceMeldShapesPanelTitle': 'Sets and runs',
  'practiceMeldShapesIntro':
      'A meld is three or more cards in one of two shapes.',
  'practiceMeldShapesSetHeading': 'Set',
  'practiceMeldShapesSetLine':
      'Same rank, all different suits — like 7♠ 7♥ 7♦. Three or four cards.',
  'practiceMeldShapesRunHeading': 'Run',
  'practiceMeldShapesRunLine':
      'Same suit, in a row — like 5♥ 6♥ 7♥. Three or more cards.',
  'practiceMeldShapesOutro':
      'A set never repeats a suit; a run is one suit and must be consecutive.',
  'practiceMeldShapesSetCaption': 'Set — same rank',
  'practiceMeldShapesRunCaption': 'Run — same suit, in sequence',
  'practiceTheAcePanelTitle': 'The Ace',
  'practiceTheAceIntro':
      'The ace is the trickiest card to value. In a run it plays two ways.',
  'practiceTheAceHighHeading': 'High',
  'practiceTheAceHighLine':
      'After the king — J♣ Q♣ K♣ A♣ — the ace counts 10. That run is worth '
      '40.',
  'practiceTheAceLowHeading': 'Low',
  'practiceTheAceLowLine':
      'Before the two — A♠ 2♠ 3♠ 4♠ — the ace still counts 10, so the run '
      'is 19.',
  'practiceTheAceFlipHeading': 'The flip',
  'practiceTheAceFlipLine':
      'But once a low run reaches a five, the ace drops to 1. A♠ 2♠ 3♠ 4♠ 5♠ '
      'is worth 15, not 25.',
  'practiceTheAceOutro':
      'This is decided as the run is formed. Adding a 5 to a run already on '
      'the table does not change the ace.',
  'practiceTheAceHighCaption': 'Ace = 10 → worth 40',
  'practiceTheAceLowCaption': 'Ace = 10 → worth 19',
  'practiceTheAceFlipCaption': 'Ace drops to 1 → worth 15',
  'helpLearningTitle': 'New to Hareeg?',
  'helpLearningBody':
      'Step through short guided practice hands, or replay the first-run intro.',
  'practiceLessonCompleteTitle': 'Lesson complete!',
  'practiceLessonCompleteBody':
      'Nice — you showed the move. Replay it any time from the practice list.',
  'practiceBackToList': 'Back to practice',
  'practiceReplayLesson': 'Replay lesson',
  'practiceStepLabel': 'Step {step} of {total}',
  'practiceTurnRhythmStep1':
      'Your turn starts with a card: draw one from the stock.',
  'practiceTurnRhythmStep1Done': 'Card drawn — it joined your hand.',
  'practiceTurnRhythmStep2':
      'Now end your turn: pick a card you do not need and discard it.',
  'practiceTurnRhythmStep2Hint':
      'Drag the card you can spare onto the discard pile.',
  'practiceFirstMeldStep2':
      'Three or more cards that share a rank or run in one suit make a meld. Your hearts already line up: 9 through ace is one run worth 59 — past the 51 opening. Play it.',
  'practiceFirstMeldStep2Hint':
      'Tap all six hearts, then the gold meld chip — extras break the meld, and the undo pill takes a staged meld back.',
  'practiceFirstMeldStep2Done': 'Opened at 59 in a single play.',
  'practiceFirstMeldStep2Hold':
      'Staged — but only the full six-heart run reaches 51. The undo pill takes it back; then play all six.',
  'practiceFirstMeldStep3': 'Finish the turn: discard a card you do not need.',
  'practiceDiscardOpeningStep1':
      'Your queens are a ready 30, and you hold two more eights — West\'s eight completes the set. Together that is 54, past the 51 opening. Tap the pile to take it.',
  'practiceDiscardOpeningStep1Done':
      'The eight is pending: a taken card must earn its place this turn.',
  'practiceDiscardOpeningStep2':
      'The taken eight must be used before your turn ends: meld the three eights.',
  'practiceDiscardOpeningStep2Hint':
      'Tap the three eights, then the gold meld chip.',
  'practiceDiscardOpeningStep2Done':
      'Staged at 24 — the queens will push it past 51.',
  'practiceDiscardOpeningStep3':
      'Now the queens: 24 + 30 makes 54 and the opening seals.',
  'practiceDiscardOpeningStep3Done': 'Opened at 54 — two sets, one turn.',
  'practiceDiscardOpeningStep4': 'End your turn with a discard.',
  'practiceBaitStep1':
      'West\'s seven pairs with yours — but three sevens make 21, nowhere near the 51 you need to open. Leave it and draw from the stock.',
  'practiceBaitStep1Done': 'Good judgment — the bait stays on the pile.',
  'practiceBaitStep2': 'Bank the patience: end your turn with a discard.',
  'practiceOpeningStep1':
      'No single meld here reaches 51 — but melds can stack in one turn. Start with your kings; notice 30 is not enough on its own.',
  'practiceOpeningStep1Hint':
      'Tap the three kings, then the gold meld chip. Staged it wrong? The undo pill takes it back.',
  'practiceOpeningStep1Done':
      'Staged at 30. The table holds your melds until you reach 51.',
  'practiceOpeningStep2': 'Add the jacks to push the total past 51.',
  'practiceOpeningStep2Done': 'Opened at 60! The table is yours now.',
  'practiceOpeningStep3': 'Seal the opening: end your turn with a discard.',
  'practicePendingStep1':
      'You are open — your run and sevens already hold the table. West\'s four pairs with yours: tap the pile and see what taking commits you to.',
  'practicePendingStep1Done':
      'The four is pending. It must hit the table this turn — or go back.',
  'practicePendingStep2':
      'Here is the exit: until a pending card touches the table, tapping the pile hands it back.',
  'practicePendingStep2Hint':
      'You could meld it instead — a taken card must be used in a meld or cover before your turn ends.',
  'practicePendingStep2Done':
      'Returned — no harm, but no second chance: a returned card cannot be re-taken this turn.',
  'practicePendingStep3':
      'The four is off limits now, so the turn falls back to its start: draw from the stock.',
  'practicePendingStep4':
      'Now the real freedom: you opened already, so any value melds. Play your twos — six points, perfectly legal.',
  'practicePendingStep4Hint': 'Tap the three twos, then the gold meld chip.',
  'practicePendingStep4Done':
      'Melded for 6 — the numbers only matter before you open.',
  'practiceBenchmarkStep1':
      'West opened big: 75 on the table, so the bar is now 75 — not 51. Start your turn with a draw.',
  'practiceBenchmarkStep2':
      'Your hearts make a real run worth 54. Stage it and watch the table\'s answer.',
  'practiceBenchmarkStep2Hint': 'Tap the six hearts, then the gold meld chip.',
  'practiceBenchmarkStep2Done':
      'Staged at 54 — over the old 51, under West\'s 75. The table holds it but cannot open.',
  'practiceBenchmarkStep3':
      'Under the bar, staged melds are stuck — they cannot seal. Take the run back and build on it later.',
  'practiceBenchmarkStep3Hint':
      'Tap the undo pill — or the staged run itself — to take it back.',
  'practiceBenchmarkStep3Done':
      'Back in hand, nothing lost — a staged opening is never locked in.',
  'practiceBenchmarkStep4':
      'End the turn with a discard. The run keeps its value for a 75-point turn later.',
  'practiceSeqCoverStep1':
      'Covers stack: West\'s run ends at the ten, and you hold the jack AND the queen. Grow it by two.',
  'practiceSeqCoverStep1Hint':
      'Drag the J♦ onto West\'s diamond run, then the Q♦ — or select both and drop them together.',
  'practiceSeqCoverStep1Hold':
      'One on — the run reaches the jack now. The queen is its new neighbor: slide it on too.',
  'practiceSeqCoverStep1Done':
      'Two covers stacked — the run runs 8 through queen now.',
  'practiceSeqCoverStep2':
      'Same turn, different meld: West\'s eights miss the diamond, and the second deck gave you its twin. Fill the set.',
  'practiceSeqCoverStep2Hint': 'Drag your 8♦ onto West\'s eights.',
  'practiceSeqCoverStep2Done':
      'Three covers, two melds, one turn — every card you shed this way is one less to count against you.',
  'practiceSetCoverStep1':
      'Once you are open, every meld on the table can grow — that is a cover. West\'s kings miss clubs, and you hold it.',
  'practiceSetCoverStep1Hint': 'Drag the K♣ onto West\'s kings.',
  'practiceSetCoverStep1Done':
      'Covered. Four suits make a full set — nothing more can land on it.',
  'practiceCoverFinishStep': 'End your turn with a discard.',
  'practiceCoverBlockStep1':
      'Your ten of hearts completes West\'s tens — but you are not open to place it, and a cover can never be thrown away. It is stuck: discard another card.',
  'practiceCoverBlockStep1Hint':
      'Try it — drag the 10♥ to the pile or onto the tens; the table refuses both. Then discard any other card.',
  'practiceJokerIdentityStep1':
      'A joker is whatever you declare — once. Meld your two sevens with the joker and pick what it stands for.',
  'practiceJokerIdentityStep1Hint':
      'Tap both sevens and the joker, then the gold meld chip — a picker asks for the joker\'s identity. Either seven works.',
  'practiceJokerIdentityStep1Done':
      'Declared. The joker is exactly that card now — until someone reclaims it.',
  'practiceJokerReplaceStep1':
      'West\'s joker stands in for the seven of diamonds — and you hold the real one. Swap it: the joker comes to your hand.',
  'practiceJokerReplaceStep1Hint':
      'Drag your 7♦ onto West\'s sevens; the exact represented card is the only legal swap.',
  'practiceJokerReplaceStep1Done':
      'Reclaimed — and look at your hearts: the 8 and 10 are one nine apart.',
  'practiceJokerReplaceStep2':
      'Your call: bridge the 8 and 10 of hearts with the joker as a nine, or bank it for later. Either way, a joker cannot be thrown away mid-round — end with a plain card.',
  'practiceJokerReplaceStep2Hint':
      'Tap the 8♥, 10♥ and joker, then the gold meld chip — or just drag a plain card to the pile.',
  'practiceJokerReplaceStep2Hold':
      'Bridged — the joker is a nine of hearts now. Seal the turn with a discard.',
  'practiceFinalDiscardStep1':
      'You are one play from the end — but no one wins by simply laying every card. Play your three nines.',
  'practiceFinalDiscardStep1Hint':
      'Tap the three nines, then the gold meld chip.',
  'practiceFinalDiscardStep1Done':
      'One card left — exactly what a finish needs.',
  'practiceFinalDiscardStep2':
      'Finishing always ends with a throw: discard the 5 of spades to go out.',
  'practiceFinalDiscardCompletion':
      'Round won — you can never meld your hand all the way to empty: the last card always leaves as a discard, never a play.',
  'practiceNormalFinishStep1':
      'Two melds and a spare card: this hand can finish cleanly. Play the queens.',
  'practiceNormalFinishStep1Done':
      'Queens down — the heart run will empty everything but one.',
  'practiceNormalFinishStep2': 'Now the heart run: all five in one play.',
  'practiceNormalFinishStep2Hint':
      'Tap the five hearts, then the gold meld chip.',
  'practiceNormalFinishStep3':
      'Go out: discard the 7 of spades and end the round.',
  'practiceNormalFinishCompletion':
      'The winner takes -1; every seat that never opened adds the full count of cards left in its hand — the number of cards, not their pip value. Going out early is defense for you and damage for them.',
  'practicePerfectHandTwos':
      'Your whole hand melds, yet totals only 47 — below the 51 you would need to open. Stage it set by set anyway: play the four twos.',
  'practicePerfectHandTwosHint': 'Tap the four twos, then the gold meld chip.',
  'practicePerfectHandTwosDone': 'Twos staged — 8 so far, still short of 51.',
  'practicePerfectHandThrees': 'Add the four threes to the staged opening.',
  'practicePerfectHandThreesHint':
      'Tap the four threes, then the gold meld chip.',
  'practicePerfectHandThreesDone': 'Threes staged — 20 now, still below 51.',
  'practicePerfectHandFours': 'Add the three fours.',
  'practicePerfectHandFoursHint':
      'Tap the three fours, then the gold meld chip.',
  'practicePerfectHandFoursDone':
      'Fours staged — 32, the bar is still out of reach.',
  'practicePerfectHandFives': 'Add the three fives — your last set.',
  'practicePerfectHandFivesHint':
      'Tap the three fives, then the gold meld chip.',
  'practicePerfectHandFivesDone':
      'Every set is staged at 47 — you never reached 51, yet only the king is left.',
  'practicePerfectHandStep2':
      'Finishing still ends with a throw: discard the king to go out.',
  'practicePerfectHandCompletion':
      'Round won — you staged every set and never reached 51, but laying your whole hand finishes the round outright, bypassing the opening you never needed. The seats that never opened still pay their full hand.',
  'practiceJokerOutStep1':
      'You are one play from the end: your eights complete the set, leaving only the joker. Play the three eights.',
  'practiceJokerOutStep1Hint': 'Tap the three eights, then the gold meld chip.',
  'practiceJokerOutStep1Done':
      'Eights down — only the joker is left in your hand.',
  'practiceJokerOutStep2':
      'A joker can never be thrown away during play — but this is the close, and a closing throw is the one exception. Discard the joker to go out.',
  'practiceJokerOutStep2Hint':
      'Drag the joker to the pile — the only time the pile accepts it.',
  'practiceJokerOutCompletion':
      'Round won — a joker cannot be discarded while the round runs, but the finishing throw may be a joker. The last card always leaves your hand.',
  'practiceFiftyClaimStep1':
      'West just threw the 8 of diamonds — your eights meet it, your twos follow, and the queen stays back to throw. That discard is claimable: call Fifty before the timer runs out.',
  'practiceFiftyClaimStep1Hint':
      'Tap the thrown card or the flame ring. Practice holds the ring at 3 — a real table never waits.',
  'practiceFiftyClaimStep2':
      'Claimed — the eight is in your hand and the clock is gone. Now prove the call: meld the three eights.',
  'practiceFiftyClaimStep2Hint':
      'Tap both eights and the claimed 8♦, then the gold meld chip. The claimed card must end the turn on the table.',
  'practiceFiftyClaimStep2Done':
      'The claimed card found its meld — half the proof is down.',
  'practiceFiftyClaimStep3': 'Keep laying it down: the twos.',
  'practiceFiftyClaimStep4':
      'Seal the Fifty: throw the queen and take the round.',
  'practiceFiftyClaimCompletion':
      'Claimed and proven — you laid the finish down yourself, and the round is yours.',
  'practiceFiftyScoringStep1':
      'Same claim, new lens: watch what Fifty does to the score sheet. Claim West\'s 5 of hearts before the timer dies.',
  'practiceFiftyScoringStep2':
      'Prove it: meld the three fives — the claimed card leads them.',
  'practiceFiftyScoringStep2Hint':
      'Tap both fives and the claimed 5♥, then the gold meld chip.',
  'practiceFiftyScoringStep3':
      'Throw the king — and watch what it does to the score sheet.',
  'practiceFiftyScoringCompletion':
      'Fifty pays double-edged: you score -3, and West — who threw the card — adds their leftover cards plus 3. (First dealt round is the exception: the winner takes -1 there.)',
  'practiceFiftyMissed':
      'The window closed — Fifty waits for no one. Restart and claim faster.',
  'practiceRestartLesson': 'Restart lesson',
  'practiceTiersIntro':
      'Four ways to run a table — same rules, different mercy.',
  'practiceTiersGotIt': 'Got it',
  'practiceTierCoachingBody':
      'Illegal moves are blocked and the live coach offers hints. Learn here.',
  'practiceTierStandardBody':
      'Illegal moves are blocked, no hints. The quiet default.',
  'practiceTierStrictBody':
      'Selected mistakes go through and cost +3 — you stay in the round, and memory rules apply.',
  'practiceTierTableBody':
      'House rules: mistakes cost +17 and you sit out the rest of the round.',
  'practiceStrictPenaltyStep1':
      'Same trapped ten — but this is a Strict table. Standard blocked this throw; Strict lets it land as a paid mistake. Throw the 10♥ on purpose and watch what it costs.',
  'practiceStrictPenaltyStep1Hint':
      'Drag the 10♥ to the pile — it lands, then snaps back and adds +3 to your score. That penalty finishes the lesson.',
  'practiceStrictPenaltyStep1Done':
      'Felt it — +3 and the ten bounced back. Strict charges the mistake but keeps you in the round.',
  'practiceStrictPenaltyCompletion':
      'On a Strict table, throwing a card the table can use is allowed — but it costs +3 instead of being blocked. The card came back to your hand, yet the points stuck. Standard would have refused the throw outright; Strict makes you pay for it.',
  'practiceTablePenaltyStep1':
      'The same throw, one table harsher. On a Table table it is allowed too — throw the 10♥ on purpose and watch the full price land.',
  'practiceTablePenaltyStep1Hint':
      'Drag the 10♥ to the pile — it goes through, adds +17, and takes you out of the round.',
  'practiceTablePenaltyStep1Done':
      'There it is — +17 and you are out of the round. The harshest table charges everything at once.',
  'practiceTablePenaltyCompletion':
      'On a Table table the same throw costs +17 and you are out of the round — the harshest table. The card leaves your hand for good and your seat sits out the rest of the round.',
};

const _arabicValues = {
  'appTitle': 'طاولة حريق',
  'homeTitle': 'طاولة حريق',
  'newGame': 'لعبة جديدة',
  'continueGame': 'متابعة',
  'settings': 'الإعدادات',
  'rulesHelp': 'القواعد / المساعدة',
  'noSavedMatch': 'لا توجد مباراة محفوظة بعد',
  'checkingSavedMatch': 'جار فحص المباراة المحفوظة...',
  'abandonSavedMatch': 'حذف المباراة المحفوظة',
  'classicModeDescription':
      'أربعة مقاعد، دوران عكس عقارب الساعة، افتتاح 51، تكميلات، جوكر، وخمسين.',
  'setupTitle': 'إعداد حريق الكلاسيكي',
  'startTable': 'ابدأ الطاولة',
  'tableTitle': 'طاولة حريق الكلاسيكية',
  'humanSeat': 'أنت',
  'stock': 'السحب',
  'discard': 'الرمي',
  'meldZone': 'منطقة المجموعات',
  'drawStock': 'اسحب من الكومة',
  'discardCard': 'ارم',
  'takeDiscard': 'خذ الرمية',
  'returnDiscard': 'أرجع + اسحب',
  'takeBackMelds': 'استرجع المجموعات',
  'pendingDiscard': 'رمية معلقة',
  'settingsTitle': 'الإعدادات',
  'helpTitle': 'قواعد حريق الكلاسيكي',
  'helpIntro':
      'مرجع سريع لقواعد حريق الكلاسيكي، التسجيل، الخمسين، واستئناف اللعب.',
  'helpSetupTitle': 'الإعداد',
  'helpSetupBody':
      'يستخدم حريق الكلاسيكي أربعة مقاعد: لاعب بشري واحد وثلاثة لاعبين آليين، مع دوران عكس عقارب الساعة. يبدأ التطبيق برزمتين وجوكرين لتكفي أوراق أربعة مقاعد. صاحب البداية يأخذ 15 ورقة ويتجاوز أول سحبة.',
  'helpTurnFlowTitle': 'سير الدور',
  'helpTurnFlowBody':
      'يبدأ صاحب البداية في مرحلة اللعب. بقية الأدوار تبدأ بالسحب من الكومة أو أخذ الرمية السابقة. الرمية المأخوذة تصبح معلقة: يمكن استخدامها في مجموعة أو تكميلة في أي وقت من الدور، لكن الدور لا ينتهي وهي غير مستخدمة، ولا يمكن أبدا أن تكون رمية نهاية الدور. وما دامت غير مستخدمة يمكن إرجاعها بدلا من ذلك.',
  'helpOpeningTitle': 'الافتتاح والمعيار',
  'helpOpeningBody':
      'شرط الافتتاح الافتراضي هو 51، ويمكن اختيار 75 من الإعدادات. يفتتح اللاعب بوضع مجموعة جديدة أو أكثر تصل قيمتها المشتركة إلى الشرط الحالي. التكميلات لا تحتسب في الافتتاح. أول لاعب يفتتح يملك المعيار ويمكنه رفعه حتى يفتتح لاعب ثان، ثم يثبت المعيار.',
  'helpCoversTitle': 'التكميلات',
  'helpCoversBody':
      'التكميلة هي ورقة يمكنها تمديد مجموعة موجودة على الطاولة الآن. تكميلات السلسلة تكون بالجيران المباشرين فقط؛ وبعد وضع ورقة قد تصبح تكميلات متتابعة قانونية. لا يمكن عادة رمي التكميلة من لاعب افتتح أو لم يفتتح، لكنها يمكن أن تكون الرمية الأخيرة عند الإنهاء.',
  'helpJokersTitle': 'الجوكر',
  'helpJokersBody':
      'يمثل الجوكر هوية ورقة مختارة عند وضعه في مجموعة أو تكميلة. إذا وجدت عدة هويات قانونية يجب على اللاعب البشري الاختيار، بينما يختار اللاعب الآلي بطريقة ثابتة. اللاعب الذي افتتح يمكنه استبدال جوكر على الطاولة بالورقة التي يمثلها وأخذ الجوكر. رمي الجوكر العادي ممنوع دائما، لكن يمكن أن يكون الرمية الأخيرة.',
  'helpFiftyTitle': 'الخمسين',
  'helpFiftyBody':
      'بعد الرمي، اللاعب التالي مباشرة فقط يستطيع إعلان الخمسين، وذلك قبل انتهاء المؤقت. الإعلان يأخذ الورقة المرمية إلى اليد، ثم يثبت المعلن الإنهاء بلا مؤقت — مجموعات أو تكميلات أو تكميلات متتابعة بأي ترتيب — ويجب أن تنتهي الورقة المعلنة في مجموعة أو تكميلة، ولا تُرمى أبدا. وضعا التدريب والقياسي يظهران إجراء الخمسين فقط عندما يكون الإنهاء قابلا للإثبات ويمنعان إنهاء الدور دون إثبات؛ في الوضع الصارم يكلف الخروج دون إثبات +3 وينتهي الدور بشكل عادي، وفي وضع الطاولة يُخرج المعلن من الجولة. إذا انتهى المؤقت يمكن للاعب أخذ الرمية بشكل عادي عند قانونيتها، لكن الإنهاء يسجل كإنهاء عادي وليس خمسين.',
  'helpScoringTitle': 'التسجيل',
  'helpScoringBody':
      'الفائز العادي يسجل -1. في الخمسين يسجل الفائز -3، ما عدا الجولة الأولى الموزعة فتستخدم -1، ويضيف الرامي الأوراق المتبقية لديه زائد 3. بقية اللاعبين النشطين يضيفون عدد أوراقهم المتبقية. الجولات المسحوبة لا تغير النقاط. اللاعب الذي يصل إلى 31 أو أكثر يخرج، وآخر لاعب باق يفوز.',
  'helpMistakePresetsTitle': 'معالجة الأخطاء',
  'helpMistakePresetsBody':
      'وضعا التدريب والقياسي يمنعان الحركات غير القانونية. الوضع الصارم يسمح بأخطاء محددة مع +3 ويبقي اللاعب في الجولة. وضع الطاولة يسمح بأخطاء محددة مع +17 ويخرج ذلك اللاعب من الجولة الحالية. رمي الجوكر العادي يبقى ممنوعا في كل مستويات الصرامة.',
  'helpPauseResumeTitle': 'الإيقاف والاستئناف',
  'helpPauseResumeBody':
      'يحفظ التطبيق حالة طاولة حريق الكلاسيكية محليا عند تغييرات الطاولة الآمنة. المتابعة تستعيد الأيدي، كومة السحب، كومة الرمي، مرحلة الدور، الرمية المعلقة، والإعدادات. حذف المباراة المحفوظة يمسح الحفظ المحلي.',
  'helpPlannedModesTitle': 'أطوار مخططة',
  'helpPlannedModesBody':
      'حريق 14 وطور مخصص للخمسينات مخططان لاحقا. الإصدار الأول يركز على حريق الكلاسيكي.',
  'splashTagline': 'حريق كلاسيكي دون اتصال',
  'splashTapToContinue': 'اضغط للمتابعة',
  'scores': 'النقاط',
  'pauseTable': 'إيقاف',
  'skipToNextRound': 'تخطي للجولة التالية',
  'scoresTitle': 'نقاط المباراة',
  'pauseTitle': 'متوقفة',
  'resumeTable': 'استئناف الطاولة',
  'leaveTable': 'مغادرة الطاولة',
  'pauseInMatchControls': 'إعدادات أثناء المباراة',
  'motionSpeedLabel': 'سرعة الحركة',
  'fastCpuTurns': 'أدوار آلية سريعة',
  'fastCpuTurnsDescription':
      'اختصر توقفات اللاعب الآلي وحركة الأوراق لتسريع أدوار الخصوم.',
  'hapticsLabel': 'اهتزازات الطاولة',
  'hapticsHelp': 'اهتزازات خفيفة عند الضغط، الإفلات، والخمسين.',
  'soundLabel': 'أصوات الطاولة',
  'soundHelp': 'شغّل أصوات حركة الأوراق وتنبيهات الطاولة.',
  'highContrastCards': 'إشارات عالية التباين',
  'highContrastCardsDescription':
      'قوّ إبرازات الأوراق والنوافذ دون تغيير رسومات السمة المختارة.',
  'aboutLicenses': 'حول التطبيق والتراخيص',
  'aboutHeader': 'طاولة حريق',
  'aboutBody':
      'حريق سوداني مفتوح المصدر، يعمل دون اتصال، وبدون إعلانات. المصدر على GitHub.',
  'licensesThemesHeader': 'سمات الأوراق',
  'licensesSoundsHeader': 'المؤثرات الصوتية',
  'kenneyCasinoAudio': 'Kenney Casino Audio',
  'kenneyCasinoAudioAttribution':
      'Kenney.nl Casino Audio، ترخيص Creative Commons CC0 1.0 Universal.',
  'kenneyCasinoAudioUrl': 'https://kenney.nl/assets/casino-audio',
  'licensesFooter':
      'الأصول المضمنة تحتفظ بتراخيص CC0 / الملكية العامة الأصلية.',
  'playMeld': 'العب مجموعة',
  'placeCover': 'ضع تكملة',
  'replaceJoker': 'استبدل الجوكر',
  'claimFifty': 'أعلن الخمسين',
  'sortModeLabel': 'الترتيب',
  'sortByRank': 'الرتبة',
  'sortBySuit': 'النوع',
  'sortManual': 'يدوي',
  'sortByRankDescription': 'حسب الرتبة ثم النوع.',
  'sortBySuitDescription': 'حسب النوع ثم الرتبة.',
  'sortManualDescription': 'اسحب لإعادة ترتيب الأوراق بنفسك.',
  'tableRules': 'قواعد الطاولة',
  'tableRulesDescription': 'عدد الرزم ونافذة إعلان الخمسين.',
  'deckCount': 'عدد الرزم',
  'fiftyTimer': 'مؤقت الخمسين',
  'handSort': 'ترتيب الأوراق',
  'handSortDescription': 'الترتيب المبدئي ليدك في بداية كل جولة.',
  'tableStrictnessTitle': 'مستوى صرامة الطاولة',
  'tableStrictnessSectionDescription':
      'تطبيق القواعد، التلميحات، وسلوك ذاكرة الجوكر. مقفل أثناء المباراة النشطة.',
  'strictnessLockedActiveMatch':
      'مستوى الصرامة مقفل أثناء المباراة النشطة. غادر الطاولة وابدأ مباراة جديدة لتغييره.',
  'look': 'المظهر',
  'lookDescription': 'وجوه الأوراق والسطح تحتها.',
  'feel': 'الإحساس',
  'feelDescription': 'الحركة، الاهتزازات، والصوت.',
  'language': 'اللغة',
  'languageDescription': 'اختر لغة الطاولة.',
  'englishLanguage': 'English',
  'arabicLanguage': 'العربية',
  'tableSurface': 'سطح الطاولة',
  'tableSurfaceDescription':
      'اضغط على عينة لتغيير المادة تحت الأوراق ومناطق المجموعات. القواعد ورسوم الأوراق لا تتغير.',
  'themeLockedActiveMatch': 'اختيار السمة مقفل أثناء المباراة النشطة.',
  'codeRendered': 'مرسومة بالكود',
  'bundledAsset': 'أصل مضمن',
  'smallTableReady': 'جاهزة للطاولات الصغيرة',
  'compactQaPending': 'فحص العرض المدمج لاحقا',
  'cpuDifficulty': 'صعوبة اللاعب الآلي',
  'beginner': 'مبتدئ',
  'casual': 'عادي',
  'skilled': 'ماهر',
  'expert': 'خبير',
  'firstStarter': 'البداية الأولى',
  'youStart': 'أنت تبدأ',
  'random': 'عشوائي',
  'openingRequirement': 'شرط الافتتاح',
  'jokers': 'الجوكر',
  'houseRules': 'قواعد البيت',
  'edit': 'تعديل',
  'normal': 'عادي',
  'fast': 'سريع',
  'reduced': 'مخفض',
  'normalMotion': 'حركة عادية',
  'fastMotion': 'حركة سريعة',
  'reducedMotion': 'حركة مخفضة',
  'sandlineLounge': 'Sandline Lounge',
  'darkFelt': 'لباد داكن',
  'lightWood': 'خشب فاتح',
  'midnightSapphire': 'ياقوت ليلي',
  'crimsonClay': 'طين قرمزي',
  'close': 'إغلاق',
  'empty': 'فارغ',
  'noMeldsYet': 'لا توجد مجموعات بعد',
  'matchOver': 'انتهت المباراة',
  'youWinTheMatch': 'فزت بالمباراة',
  'finalStandings': 'الترتيب النهائي',
  'newMatchSameSetup': 'مباراة جديدة، نفس الإعدادات',
  'wonByFifty': 'فاز بالخمسين',
  'wonByFinish': 'فاز بإنهاء الجولة',
  'returnToMenu': 'العودة للقائمة',
  'eliminated': 'خارج اللعب',
  'nextNow': 'التالي الآن',
  'menu': 'القائمة',
  'couldNotSaveTable': 'تعذر حفظ الطاولة. يمكنك متابعة اللعب.',
  'reportTableIssue': 'أبلغ عن مشكلة في الطاولة',
  'exportMatchReport': 'تصدير تقرير المباراة',
  'matchReportShareReady': 'تقرير المباراة جاهز للمشاركة.',
  'matchReportCopyFallback':
      'مشاركة الملف غير متاحة هنا. هل تريد نسخ JSON التقرير بدلا من ذلك؟',
  'copyReport': 'نسخ التقرير',
  'matchReportCopied': 'تم نسخ تقرير المباراة إلى الحافظة.',
  'matchReportCopyFailed': 'تعذر نسخ تقرير المباراة.',
  'cpuEast': 'الآلي شرق',
  'cpuNorth': 'الآلي شمال',
  'cpuWest': 'الآلي غرب',
  'joker': 'جوكر',
  'unassignedJoker': 'جوكر غير محدد.',
  'unassignedJokerGuided':
      'جوكر غير محدد. اختر هويته عندما تحتاجه مجموعة قانونية.',
  'onboardingSkip': 'تخطي المقدمة',
  'onboardingNext': 'التالي',
  'onboardingDone': 'تم',
  'onboardingStartPractice': 'جرب التدريب الموجه',
  'onboardingStartPlaying': 'ابدأ اللعب',
  'onboardingWelcomeTitle': 'أهلا بك على الطاولة',
  'onboardingWelcomeBody':
      'حريق الكلاسيكي لعبة ورق بأربعة مقاعد تدور عكس عقارب الساعة. كوّن المجموعات، افتتح بقيمة الطاولة المطلوبة، وكن أول من ينهي أوراقه — آخر لاعب تحت 31 نقطة يفوز بالمباراة.',
  'onboardingTurnTitle': 'الدور في ثلاث خطوات',
  'onboardingTurnBody':
      'اسحب من الكومة أو خذ الرمية، العب مجموعات وتكميلات إن استطعت، ثم أنه دورك برمي ورقة. الافتتاح والتكميلات والجوكر والخمسين تضيف الضغط — ولكل منها تدريب قصير خاص.',
  'onboardingLearnTitle': 'تعلم بطريقتك',
  'onboardingLearnBody':
      'التدريب الموجه يعلّم آلية واحدة في كل مرة عبر أيادي قصيرة قابلة للإعادة — منفصلة عن المباريات الحقيقية. المدرب المباشر مختلف: يقدم تلميحات مختصرة أثناء اللعب الفعلي في مستوى التدريب.',
  'onboardingReadyTitle': 'جاهز متى ما كنت',
  'onboardingReadyBody':
      'ابدأ بالتدريب الموجه، أو انتقل مباشرة إلى الطاولة. يمكنك إعادة هذه المقدمة في أي وقت من القواعد / المساعدة.',
  'practiceTitle': 'التدريب الموجه',
  'practiceIntro':
      'أيادٍ قصيرة، آلية واحدة لكل منها، وتنتهي لحظة إتقانك للحركة. تخطَّ ما تعرفه وأعد ما نسيته — هذه القائمة لا تعيق اللعب العادي أبدا.',
  'practiceReplayIntro': 'إعادة المقدمة',
  'practiceStatusNotStarted': 'لم يبدأ',
  'practiceStatusSkipped': 'تم تخطيه',
  'practiceStatusCompleted': 'مكتمل',
  'practiceStart': 'ابدأ',
  'practiceReplay': 'إعادة',
  'practiceSkip': 'تخطي',
  'practiceUnskip': 'إلغاء التخطي',
  'practiceComingSoon': 'هذا التدريب سيتوفر في تحديث قادم.',
  'practiceFollowStep': 'حدس جيد — لكن اتبع الخطوة الحالية أولاً.',
  'practiceNextLesson': 'الدرس التالي',
  'practicePackFundamentalsTitle': 'الأساسيات',
  'practicePackCoreTitle': 'أساسيات الدور',
  'practicePackTableTitle': 'آليات الطاولة',
  'practicePackFinishTitle': 'الإنهاء والخمسين',
  'practicePackTableStrictnessTitle': 'صرامة الطاولة',
  'practiceProgress': 'اكتمل {completed} من {total}',
  'practiceCardValuesTitle': 'قيمة أوراقك',
  'practiceCardValuesSummary':
      'الأوراق الملوّنة والآص بـ10؛ والأوراق الرقمية بقيمة رقمها.',
  'practiceMeldShapesTitle': 'المجموعات والتسلسلات',
  'practiceMeldShapesSummary':
      'شكلا المجموعة: مجموعات بنفس الرتبة وتسلسلات بنفس النوع.',
  'practiceTheAceTitle': 'الآص',
  'practiceTheAceSummary':
      'الآص يكون عاليًا أو منخفضًا — والتسلسل المنخفض الذي يبلغ الخمسة يقلبه '
      'إلى 1.',
  'practiceTurnRhythmTitle': 'إيقاع الدور',
  'practiceTurnRhythmSummary': 'اسحب، العب إن استطعت، ثم ارم لإنهاء دورك.',
  'practiceFirstMeldTitle': 'أول مجموعة لك',
  'practiceFirstMeldSummary': 'افتتح الطاولة بتسلسل واحد من يدك مباشرة.',
  'practiceDiscardOpeningTitle': 'الافتتاح من الرمية',
  'practiceDiscardOpeningSummary':
      'خذ الورقة المرمية التي تدفع افتتاحك فوق 51.',
  'practiceBaitDiscardTitle': 'رمية الطُعم',
  'practiceBaitDiscardSummary': 'الورقة التي تبدو مفيدة لا تستحق الأخذ دائما.',
  'practicePendingDiscardTitle': 'أخذ الرمية',
  'practicePendingDiscardSummary':
      'الرمية المأخوذة يجب استخدامها في لعبة أو إرجاعها قبل السحب.',
  'practiceOpeningTitle': 'الافتتاح بـ 51',
  'practiceOpeningSummary': 'كدّس مجموعات بقيمة شرط الافتتاح في دور واحد.',
  'practiceBenchmarkTitle': 'ضغط المعيار',
  'practiceBenchmarkSummary':
      'الافتتاح الأول العالي يرفع ما يجب على الآخرين بلوغه.',
  'practiceSequenceCoverTitle': 'تكميلات متراكمة',
  'practiceSequenceCoverSummary':
      'مدّد تسلسلا بورقتين وأكمل مجموعة ثانية في نفس الدور.',
  'practiceSetCoverTitle': 'تكميلتك الأولى',
  'practiceSetCoverSummary': 'مدّد مجموعة لاعب آخر بورقة واحدة من يدك.',
  'practiceCoverDiscardTitle': 'قواعد رمي التكميلة',
  'practiceCoverDiscardSummary': 'لماذا لا يمكن عادة رمي ورقة تصلح تكميلة.',
  'practiceJokerIdentityTitle': 'هوية الجوكر',
  'practiceJokerIdentitySummary': 'حدد بالضبط ما يمثله الجوكر الموضوع.',
  'practiceJokerReplacementTitle': 'استبدال الجوكر',
  'practiceJokerReplacementSummary':
      'ضع الورقة الحقيقية لتسترجع الجوكر من الطاولة.',
  'practiceFinalDiscardTitle': 'الرمية الأخيرة',
  'practiceFinalDiscardSummary': 'الإنهاء يحتفظ دائما بورقة أخيرة للرمي.',
  'practiceNormalFinishTitle': 'إنهاء الجولة',
  'practiceNormalFinishSummary': 'أنهِ أوراقك وشاهد كيف تحسب الجولة.',
  'practicePerfectHandTitle': 'اليد المثالية',
  'practicePerfectHandSummary': 'يد كاملة من المجموعات تنهي دون أي افتتاح.',
  'practiceJokerOutTitle': 'الجوكر ورقتك الأخيرة',
  'practiceJokerOutSummary':
      'الجوكر لا يُرمى أثناء اللعب — لكنه قد يكون رميتك الختامية.',
  'practiceFiftyClaimTitle': 'توقيت الخمسين',
  'practiceFiftyClaimSummary': 'اطلب الخمسين من الرمية قبل انتهاء المهلة.',
  'practiceFiftyScoringTitle': 'حساب الخمسين',
  'practiceFiftyScoringSummary': 'مكافأة الفائز وعقوبة من رمى الورقة.',
  'practiceStrictPenaltyTitle': 'الصارمة: رمية الـ +3',
  'practiceStrictPenaltySummary':
      'على طاولة صارمة، رمي ورقة تصلح للطاولة يكلف +3.',
  'practiceTablePenaltyTitle': 'طاولة البيت: +17 وخروج',
  'practiceTablePenaltySummary':
      'على طاولة البيت، نفس الرمية تكلف +17 وتنهي جولتك.',
  'practiceStrictnessTitle': 'مستويات صرامة الطاولة',
  'practiceStrictnessSummary':
      'ما تتوقعه منك مستويات التدريب والقياسي والصارم والطاولة.',
  'practiceCardValuesPanelTitle': 'قيمة أوراقك',
  'practiceCardValuesIntro':
      'الافتتاح والتسجيل كلاهما يجمع قيم الأوراق — وهذه قيمة كل ورقة.',
  'practiceCardValuesNumberHeading': 'الأوراق الرقمية (2–10)',
  'practiceCardValuesNumberLine':
      'تساوي الرقم المكتوب عليها. الـ7 يساوي 7 نقاط.',
  'practiceCardValuesFaceHeading': 'الآص والولد والبنت والشايب',
  'practiceCardValuesFaceLine': 'كل منها يساوي 10 نقاط.',
  'practiceCardValuesOutro': 'فثلاثة شيوب تساوي 30، والستة تساوي 6.',
  'practiceCardValue2': '= 2',
  'practiceCardValue5': '= 5',
  'practiceCardValue9': '= 9',
  'practiceCardValue10Each': 'كلٌّ = 10',
  'practiceMeldShapesPanelTitle': 'المجموعات والتسلسلات',
  'practiceMeldShapesIntro': 'المجموعة هي ثلاث أوراق أو أكثر في أحد شكلين.',
  'practiceMeldShapesSetHeading': 'مجموعة',
  'practiceMeldShapesSetLine':
      'نفس الرتبة بأنواع مختلفة — مثل 7♠ 7♥ 7♦. ثلاث أو أربع أوراق.',
  'practiceMeldShapesRunHeading': 'تسلسل',
  'practiceMeldShapesRunLine':
      'نفس النوع بترتيب متتابع — مثل 5♥ 6♥ 7♥. ثلاث أوراق أو أكثر.',
  'practiceMeldShapesOutro':
      'المجموعة لا تكرّر نوعًا؛ والتسلسل نوع واحد ويجب أن يكون متتابعًا.',
  'practiceMeldShapesSetCaption': 'مجموعة — نفس الرتبة',
  'practiceMeldShapesRunCaption': 'تسلسل — نفس النوع، بالترتيب',
  'practiceTheAcePanelTitle': 'الآص',
  'practiceTheAceIntro': 'الآص أصعب ورقة في تقييمها. في التسلسل يلعب بطريقتين.',
  'practiceTheAceHighHeading': 'عالٍ',
  'practiceTheAceHighLine':
      'بعد الشايب — J♣ Q♣ K♣ A♣ — يُحسب الآص 10. ذلك التسلسل يساوي 40.',
  'practiceTheAceLowHeading': 'منخفض',
  'practiceTheAceLowLine':
      'قبل الاثنين — A♠ 2♠ 3♠ 4♠ — يبقى الآص يُحسب 10، فيساوي التسلسل 19.',
  'practiceTheAceFlipHeading': 'الانقلاب',
  'practiceTheAceFlipLine':
      'لكن متى بلغ التسلسل المنخفض الخمسة، يهبط الآص إلى 1. فـA♠ 2♠ 3♠ 4♠ 5♠ '
      'يساوي 15 لا 25.',
  'practiceTheAceOutro':
      'يُحسم هذا أثناء تكوين التسلسل. إضافة 5 إلى تسلسل موجود على الطاولة '
      'لا يغيّر الآص.',
  'practiceTheAceHighCaption': 'الآص = 10 ← يساوي 40',
  'practiceTheAceLowCaption': 'الآص = 10 ← يساوي 19',
  'practiceTheAceFlipCaption': 'الآص يهبط إلى 1 ← يساوي 15',
  'helpLearningTitle': 'جديد على حريق؟',
  'helpLearningBody':
      'تدرّب عبر أيادٍ موجهة قصيرة، أو أعد مقدمة التشغيل الأول.',
  'practiceLessonCompleteTitle': 'اكتمل الدرس!',
  'practiceLessonCompleteBody':
      'أحسنت — أتقنت الحركة. يمكنك إعادتها في أي وقت من قائمة التدريب.',
  'practiceBackToList': 'العودة للتدريب',
  'practiceReplayLesson': 'إعادة الدرس',
  'practiceStepLabel': 'الخطوة {step} من {total}',
  'practiceTurnRhythmStep1': 'دورك يبدأ بورقة: اسحب واحدة من الكومة.',
  'practiceTurnRhythmStep1Done': 'سحبت ورقة — انضمت إلى يدك.',
  'practiceTurnRhythmStep2': 'الآن أنهِ دورك: اختر ورقة لا تحتاجها وارمها.',
  'practiceTurnRhythmStep2Hint': 'اسحب البطاقة التي لا تحتاجها إلى كومة الرمي.',
  'practiceFirstMeldStep2':
      'ثلاث أوراق أو أكثر تتشارك الرتبة أو تتسلسل بشكل واحد تصنع مجموعة. قلوبك مصطفة بالفعل: من 9 إلى الآس تسلسل واحد بقيمة 59 — فوق افتتاح 51. العبه.',
  'practiceFirstMeldStep2Hint':
      'اضغط على القلوب الستة كلها ثم على شريحة المجموعة الذهبية — الزيادة تفسد المجموعة، وزر التراجع يستعيد المجموعة المرحلية.',
  'practiceFirstMeldStep2Done': 'افتتحت بـ 59 بلعبة واحدة.',
  'practiceFirstMeldStep2Hold':
      'مرحلية — لكن التسلسل الكامل بقلوبه الستة هو ما يبلغ 51. زر التراجع يستعيدها؛ ثم العب الستة كلها.',
  'practiceFirstMeldStep3': 'أنهِ الدور: ارم ورقة لا تحتاجها.',
  'practiceDiscardOpeningStep1':
      'ملكاتك جاهزة بقيمة 30، وتحمل ثمانيتين أخريين — ثمانية الغرب تكمل المجموعة. معا تساوي 54، فوق افتتاح 51. اضغط على كومة الرمي لأخذها.',
  'practiceDiscardOpeningStep1Done':
      'الثمانية الآن معلقة: الورقة المأخوذة يجب أن تستحق مكانها هذا الدور.',
  'practiceDiscardOpeningStep2':
      'الثمانية المأخوذة يجب أن تُستخدم قبل نهاية دورك: العب الثمانيات الثلاث.',
  'practiceDiscardOpeningStep2Hint':
      'اضغط على الثمانيات الثلاث ثم على شريحة المجموعة الذهبية.',
  'practiceDiscardOpeningStep2Done': 'مرحلية عند 24 — الملكات ستدفعها فوق 51.',
  'practiceDiscardOpeningStep3':
      'الآن الملكات: 24 + 30 تساوي 54 ويكتمل الافتتاح.',
  'practiceDiscardOpeningStep3Done': 'افتتحت بـ 54 — مجموعتان في دور واحد.',
  'practiceDiscardOpeningStep4': 'أنهِ دورك برمي ورقة.',
  'practiceBaitStep1':
      'سبعة الغرب تناسب سبعاتك — لكن ثلاث سبعات تساوي 21، بعيدة كل البعد عن 51 المطلوبة للافتتاح. اتركها واسحب من الكومة.',
  'practiceBaitStep1Done': 'حكم سليم — الطُعم بقي على الكومة.',
  'practiceBaitStep2': 'اكسب بالصبر: أنهِ دورك برمي ورقة.',
  'practiceOpeningStep1':
      'لا توجد مجموعة واحدة هنا تبلغ 51 — لكن المجموعات تتكدس في الدور الواحد. ابدأ بملوكك؛ لاحظ أن 30 لا تكفي وحدها.',
  'practiceOpeningStep1Hint':
      'اضغط على الملوك الثلاثة ثم على شريحة المجموعة الذهبية. وضعتها خطأ؟ زر التراجع يستعيدها.',
  'practiceOpeningStep1Done':
      'مرحلية عند 30. الطاولة تحفظ مجموعاتك حتى تبلغ 51.',
  'practiceOpeningStep2': 'أضف الأولاد لتتجاوز قيمة 51.',
  'practiceOpeningStep2Done': 'افتتحت بـ 60! الطاولة لك الآن.',
  'practiceOpeningStep3': 'أكمل الافتتاح: أنهِ دورك برمي ورقة.',
  'practicePendingStep1':
      'أنت مفتتح — تسلسلك وسبعاتك على الطاولة بالفعل. أربعة الغرب تزاوج أربعاتك: اضغط على الكومة وانظر بمَ يلزمك الأخذ.',
  'practicePendingStep1Done':
      'الأربعة معلقة. يجب أن تنزل على الطاولة هذا الدور — أو تعود.',
  'practicePendingStep2':
      'هذا هو المخرج: ما دامت الورقة المعلقة لم تلمس الطاولة، الضغط على الكومة يعيدها.',
  'practicePendingStep2Hint':
      'كان بإمكانك لعبها بدلا من ذلك — الورقة المأخوذة يجب أن تُستخدم في مجموعة أو تكميلة قبل نهاية دورك.',
  'practicePendingStep2Done':
      'أُعيدت — لا ضرر، لكن لا فرصة ثانية: الورقة المعادة لا تُؤخذ مجددا هذا الدور.',
  'practicePendingStep3':
      'الأربعة محظورة الآن، فيعود الدور إلى بدايته: اسحب من كومة السحب.',
  'practicePendingStep4':
      'وهذه الحرية الحقيقية: افتتحت سابقا، فأي قيمة تنزل. العب الاثنينات — ست نقاط، وقانونية تماما.',
  'practicePendingStep4Hint':
      'اضغط على الاثنينات الثلاث ثم على شريحة المجموعة الذهبية.',
  'practicePendingStep4Done': 'نزلت بقيمة 6 — الأرقام لا تهم إلا قبل الافتتاح.',
  'practiceBenchmarkStep1':
      'افتتح الغرب بقوة: 75 على الطاولة، فأصبح المعيار 75 — لا 51. ابدأ دورك بالسحب.',
  'practiceBenchmarkStep2':
      'كُبّاتك تصنع تسلسلا حقيقيا بقيمة 54. جهّزه وراقب رد الطاولة.',
  'practiceBenchmarkStep2Hint':
      'اضغط على الكُبّات الست ثم على شريحة المجموعة الذهبية.',
  'practiceBenchmarkStep2Done':
      'مرحلية عند 54 — فوق 51 القديمة، تحت 75 الغرب. الطاولة تحفظها لكنها لا تفتتح.',
  'practiceBenchmarkStep3':
      'تحت المعيار تبقى المجموعات عالقة — لا تُختم. استرجع التسلسل وابنِ عليه لاحقا.',
  'practiceBenchmarkStep3Hint':
      'اضغط على زر التراجع — أو على التسلسل المرحلي نفسه — لاسترجاعه.',
  'practiceBenchmarkStep3Done':
      'عاد إلى يدك، لم تخسر شيئا — التجهيز لا يُلزمك قبل الختم.',
  'practiceBenchmarkStep4':
      'أنهِ الدور برمي ورقة. التسلسل يحتفظ بقيمته لدور يبلغ 75 لاحقا.',
  'practiceSeqCoverStep1':
      'التكميلات تتراكم: تسلسل الغرب ينتهي عند العشرة، وأنت تحمل الولد والملكة معا. مدّده باثنتين.',
  'practiceSeqCoverStep1Hint':
      'اسحب J♦ إلى تسلسل الغرب الديناري ثم Q♦ — أو حدد الاثنتين وأنزلهما معا.',
  'practiceSeqCoverStep1Hold':
      'نزلت واحدة — التسلسل يبلغ الولد الآن. الملكة جارته الجديدة: أنزلها أيضا.',
  'practiceSeqCoverStep1Done':
      'تكميلتان متراكمتان — التسلسل يمتد من 8 إلى الملكة الآن.',
  'practiceSeqCoverStep2':
      'نفس الدور، مجموعة أخرى: ثمانيات الغرب ينقصها الديناري، والرزمة الثانية أعطتك توأمها. أكمل المجموعة.',
  'practiceSeqCoverStep2Hint': 'اسحب 8♦ إلى ثمانيات الغرب.',
  'practiceSeqCoverStep2Done':
      'ثلاث تكميلات على مجموعتين في دور واحد — كل ورقة تنزلها هكذا ورقة أقل تُحسب عليك.',
  'practiceSetCoverStep1':
      'بعد افتتاحك، كل مجموعة على الطاولة قابلة للنمو — هذه هي التكميلة. ملوك الغرب ينقصها السنيك، وأنت تحمله.',
  'practiceSetCoverStep1Hint': 'اسحب K♣ إلى ملوك الغرب.',
  'practiceSetCoverStep1Done':
      'تم التكميل. أربعة أشكال تصنع مجموعة مكتملة — لا شيء يضاف إليها بعد الآن.',
  'practiceCoverFinishStep': 'أنهِ دورك برمي ورقة.',
  'practiceCoverBlockStep1':
      'عشرتك الكُبّة تكمل عشرات الغرب — لكنك لست مفتتحا لتضعها، والتكميلة لا تُرمى أبدا. إنها عالقة: ارم ورقة أخرى.',
  'practiceCoverBlockStep1Hint':
      'جرّب — اسحب 10♥ إلى الكومة أو إلى العشرات؛ الطاولة ترفض الاثنين. ثم ارم أي ورقة أخرى.',
  'practiceJokerIdentityStep1':
      'الجوكر هو ما تعلنه — مرة واحدة. العب سبعتيك مع الجوكر واختر ما يمثله.',
  'practiceJokerIdentityStep1Hint':
      'اضغط على السبعتين والجوكر ثم على شريحة المجموعة الذهبية — تظهر نافذة تسأل عن هوية الجوكر. أي سبعة تصلح.',
  'practiceJokerIdentityStep1Done':
      'أُعلن. الجوكر الآن هو تلك الورقة بالضبط — حتى يسترجعه أحد.',
  'practiceJokerReplaceStep1':
      'جوكر الغرب ينوب عن سبعة الديناري — وأنت تحمل الأصلية. بدّلها: الجوكر يأتي إلى يدك.',
  'practiceJokerReplaceStep1Hint':
      'اسحب 7♦ إلى سبعات الغرب؛ الورقة الممثلة بالضبط هي التبديل القانوني الوحيد.',
  'practiceJokerReplaceStep1Done':
      'استرجعته — وانظر إلى كُبّاتك: الثمانية والعشرة بينهما تسعة واحدة.',
  'practiceJokerReplaceStep2':
      'القرار لك: اجسر بين 8 و10 الكُبّة بالجوكر كتسعة، أو احتفظ به. في الحالين، الجوكر لا يُرمى أثناء الجولة — أنهِ بورقة عادية.',
  'practiceJokerReplaceStep2Hint':
      'اضغط على 8♥ و10♥ والجوكر ثم شريحة المجموعة الذهبية — أو اسحب ورقة عادية إلى الكومة مباشرة.',
  'practiceJokerReplaceStep2Hold':
      'تم الجسر — الجوكر تسعة كُبّة الآن. أكمل الدور برمي ورقة.',
  'practiceFinalDiscardStep1':
      'أنت على بعد لعبة من النهاية — لكن لا أحد يفوز بمجرد وضع كل أوراقه. العب تساعياتك الثلاث.',
  'practiceFinalDiscardStep1Hint':
      'اضغط على التساعيات الثلاث ثم شريحة المجموعة الذهبية.',
  'practiceFinalDiscardStep1Done': 'بقيت ورقة واحدة — تماما ما يحتاجه الإنهاء.',
  'practiceFinalDiscardStep2':
      'الإنهاء ينتهي دائما برمية: ارم 5 البستوني لتخرج.',
  'practiceFinalDiscardCompletion':
      'فزت بالجولة — لا يمكنك أبدا تنزيل يدك كلها مجموعات حتى تفرغ: الورقة الأخيرة تغادر رمية دائما، لا لعبة.',
  'practiceNormalFinishStep1':
      'مجموعتان وورقة فائضة: هذه اليد تنهي بنظافة. العب الملكات.',
  'practiceNormalFinishStep1Done':
      'نزلت الملكات — تتابع الكُبّة سيفرغ كل شيء إلا ورقة واحدة.',
  'practiceNormalFinishStep2': 'الآن تتابع الكُبّة: الخمس أوراق في لعبة واحدة.',
  'practiceNormalFinishStep2Hint':
      'اضغط أوراق الكُبّة الخمس ثم شريحة المجموعة الذهبية.',
  'practiceNormalFinishStep3': 'اخرج: ارم 7 البستوني وأنهِ الجولة.',
  'practiceNormalFinishCompletion':
      'الفائز يأخذ -1؛ وكل مقعد لم يفتتح يضيف عدد الأوراق الباقية في يده كاملا — عدد الأوراق لا قيمتها. الخروج المبكر دفاع لك وضرر عليهم.',
  'practicePerfectHandTwos':
      'يدك كلها مجموعات، لكن مجموعها 47 فقط — دون 51 التي تلزمك للافتتاح. انزلها مجموعة مجموعة رغم ذلك: العب الثنائيات الأربع.',
  'practicePerfectHandTwosHint':
      'اضغط الثنائيات الأربع ثم شريحة المجموعة الذهبية.',
  'practicePerfectHandTwosDone': 'نزلت الثنائيات — 8 حتى الآن، ما زلت دون 51.',
  'practicePerfectHandThrees': 'أضف الثلاثيات الأربع إلى الافتتاح المرحلي.',
  'practicePerfectHandThreesHint':
      'اضغط الثلاثيات الأربع ثم شريحة المجموعة الذهبية.',
  'practicePerfectHandThreesDone': 'نزلت الثلاثيات — 20 الآن، لا تزال دون 51.',
  'practicePerfectHandFours': 'أضف الرباعيات الثلاث.',
  'practicePerfectHandFoursHint':
      'اضغط الرباعيات الثلاث ثم شريحة المجموعة الذهبية.',
  'practicePerfectHandFoursDone': 'نزلت الرباعيات — 32، والحد ما زال بعيدا.',
  'practicePerfectHandFives': 'أضف الخماسيات الثلاث — مجموعتك الأخيرة.',
  'practicePerfectHandFivesHint':
      'اضغط الخماسيات الثلاث ثم شريحة المجموعة الذهبية.',
  'practicePerfectHandFivesDone':
      'كل المجموعات نزلت عند 47 — لم تبلغ 51 قط، ومع ذلك لم يبق إلا الملك.',
  'practicePerfectHandStep2': 'الإنهاء ينتهي دائما برمية: ارم الملك لتخرج.',
  'practicePerfectHandCompletion':
      'فزت بالجولة — نزّلت كل مجموعة ولم تبلغ 51 قط، لكن إنزال يدك كلها ينهي الجولة مباشرة، متجاوزا الافتتاح الذي لم تحتجه. والمقاعد التي لم تفتتح تدفع يدها كاملة.',
  'practiceJokerOutStep1':
      'أنت على بعد لعبة من النهاية: ثمانياتك تكمل المجموعة ولا يبقى إلا الجوكر. العب الثمانيات الثلاث.',
  'practiceJokerOutStep1Hint':
      'اضغط الثمانيات الثلاث ثم شريحة المجموعة الذهبية.',
  'practiceJokerOutStep1Done': 'نزلت الثمانيات — لم يبق في يدك إلا الجوكر.',
  'practiceJokerOutStep2':
      'الجوكر لا يُرمى أبدا أثناء اللعب — لكن هذا هو الختام، والرمية الختامية هي الاستثناء الوحيد. ارم الجوكر لتخرج.',
  'practiceJokerOutStep2Hint':
      'اسحب الجوكر إلى الكومة — المرة الوحيدة التي تقبله فيها الكومة.',
  'practiceJokerOutCompletion':
      'فزت بالجولة — الجوكر لا يُرمى ما دامت الجولة جارية، لكن الرمية الختامية قد تكون جوكرا. الورقة الأخيرة تغادر يدك دائما.',
  'practiceFiftyClaimStep1':
      'الغرب رمى للتو 8 الديناري — ثمانياتك تكتمل بها، وثنائياتك تتبعها، والملكة تبقى للرمي. تلك الرمية قابلة للمطالبة: اطلب الخمسين قبل نفاد المؤقت.',
  'practiceFiftyClaimStep1Hint':
      'اضغط الورقة المرمية أو حلقة اللهب. التدريب يوقف الحلقة عند 3 — الطاولة الحقيقية لا تنتظر.',
  'practiceFiftyClaimStep2':
      'طالبت — الثمانية في يدك والمؤقت اختفى. الآن أثبت النداء: العب الثمانيات الثلاث.',
  'practiceFiftyClaimStep2Hint':
      'اضغط الثمانيتين و8 الديناري المطالَب بها ثم شريحة المجموعة الذهبية. الورقة المطالَب بها يجب أن تنهي الدور على الطاولة.',
  'practiceFiftyClaimStep2Done':
      'الورقة المطالَب بها وجدت مجموعتها — نصف الإثبات نزل.',
  'practiceFiftyClaimStep3': 'واصل الإنزال: الثنائيات.',
  'practiceFiftyClaimStep4': 'اختم الخمسين: ارم الملكة وخذ الجولة.',
  'practiceFiftyClaimCompletion':
      'طالبت وأثبتّ — أنزلت الإنهاء بيدك، والجولة لك.',
  'practiceFiftyScoringStep1':
      'نفس المطالبة بعدسة جديدة: راقب ما يفعله الخمسين بورقة النتائج. طالب بـ 5 الكُبّة من الغرب قبل موت المؤقت.',
  'practiceFiftyScoringStep2':
      'أثبتها: العب الخمسات الثلاث — الورقة المطالَب بها تتقدمها.',
  'practiceFiftyScoringStep2Hint':
      'اضغط الخمستين و5 الكُبّة المطالَب بها ثم شريحة المجموعة الذهبية.',
  'practiceFiftyScoringStep3': 'ارم الملك — وراقب ما يفعله ذلك بورقة النتائج.',
  'practiceFiftyScoringCompletion':
      'الخمسين سلاح ذو حدين: تسجل -3، والغرب — من رمى الورقة — يضيف ما بقي في يده زائد 3. (الجولة الأولى الموزعة استثناء: الفائز يأخذ -1 فيها.)',
  'practiceFiftyMissed':
      'أُغلقت النافذة — الخمسين لا ينتظر أحدا. أعد الدرس وطالب أسرع.',
  'practiceRestartLesson': 'إعادة الدرس',
  'practiceTiersIntro': 'أربع طرق لإدارة الطاولة — نفس القواعد، رحمة مختلفة.',
  'practiceTiersGotIt': 'فهمت',
  'practiceTierCoachingBody':
      'الحركات غير القانونية محجوبة والمدرب المباشر يلمّح. تعلم هنا.',
  'practiceTierStandardBody':
      'الحركات غير القانونية محجوبة، دون تلميحات. الافتراضي الهادئ.',
  'practiceTierStrictBody':
      'أخطاء مختارة تمر وتكلف +3 — تبقى في الجولة، وقواعد الذاكرة تنطبق.',
  'practiceTierTableBody':
      'قواعد البيت: الأخطاء تكلف +17 وتجلس خارج بقية الجولة.',
  'practiceStrictPenaltyStep1':
      'نفس العشرة المحاصرة — لكن هذه طاولة صارمة. القياسية حجبت هذه الرمية؛ الصارمة تجعلها تنزل كخطأ مدفوع. ارمِ 10 الكُبّة عمدا وراقب كلفتها.',
  'practiceStrictPenaltyStep1Hint':
      'اسحب 10 الكُبّة إلى الكومة — تنزل ثم ترتد وتضيف +3 إلى نتيجتك. هذه العقوبة تنهي الدرس.',
  'practiceStrictPenaltyStep1Done':
      'شعرت بها — +3 والعشرة ارتدت. الصارمة تحاسب على الخطأ لكنها تبقيك في الجولة.',
  'practiceStrictPenaltyCompletion':
      'على طاولة صارمة، رمي ورقة تصلح للطاولة مسموح — لكنه يكلف +3 بدلا من أن يُحجب. عادت الورقة إلى يدك، لكن النقاط بقيت. القياسية كانت سترفض الرمية تماما؛ الصارمة تجعلك تدفع ثمنها.',
  'practiceTablePenaltyStep1':
      'نفس الرمية، طاولة أقسى. على طاولة البيت هي مسموحة أيضا — ارمِ 10 الكُبّة عمدا وراقب الثمن الكامل ينزل.',
  'practiceTablePenaltyStep1Hint':
      'اسحب 10 الكُبّة إلى الكومة — تمر، تضيف +17، وتخرجك من الجولة.',
  'practiceTablePenaltyStep1Done':
      'ها هي — +17 وأنت خارج الجولة. أقسى طاولة تحاسب على كل شيء دفعة واحدة.',
  'practiceTablePenaltyCompletion':
      'على طاولة البيت نفس الرمية تكلف +17 وتخرج من الجولة — أقسى طاولة. تغادر الورقة يدك للأبد ويجلس مقعدك خارج بقية الجولة.',
};
