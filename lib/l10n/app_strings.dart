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
  String get practicePackCoreTitle => _v('practicePackCoreTitle');
  String get practicePackTableTitle => _v('practicePackTableTitle');
  String get practicePackFinishTitle => _v('practicePackFinishTitle');

  /// Checklist progress summary, e.g. "3 of 15 completed".
  String practiceProgress(int completed, int total) => _v(
    'practiceProgress',
  ).replaceFirst('{completed}', '$completed').replaceFirst('{total}', '$total');

  // Guided practice lesson catalog.
  String get practiceTurnRhythmTitle => _v('practiceTurnRhythmTitle');
  String get practiceTurnRhythmSummary => _v('practiceTurnRhythmSummary');
  String get practicePendingDiscardTitle => _v('practicePendingDiscardTitle');
  String get practicePendingDiscardSummary =>
      _v('practicePendingDiscardSummary');
  String get practiceMeldPickerTitle => _v('practiceMeldPickerTitle');
  String get practiceMeldPickerSummary => _v('practiceMeldPickerSummary');
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
  String get practiceFiftyClaimTitle => _v('practiceFiftyClaimTitle');
  String get practiceFiftyClaimSummary => _v('practiceFiftyClaimSummary');
  String get practiceFiftyScoringTitle => _v('practiceFiftyScoringTitle');
  String get practiceFiftyScoringSummary => _v('practiceFiftyScoringSummary');
  String get practiceStrictnessTitle => _v('practiceStrictnessTitle');
  String get practiceStrictnessSummary => _v('practiceStrictnessSummary');

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
      'The starter begins in action phase. Other turns begin by drawing from stock or taking the previous discard. A taken discard becomes pending: it must be used in a valid play that turn or returned before drawing from stock.',
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
      'After a discard, only the immediate next player can claim Fifty, and only before the timer expires. The discarded card must be part of a legal finish, including hand melds, table covers, or chained covers. Coaching and Standard show the Fifty action only when the finish is proven; Strict and Table allow wrong claims as penalized mistakes. If the timer is missed, the player may still take the discard normally when legal, but the finish scores as normal instead of Fifty.',
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
  'practicePackCoreTitle': 'Core turn basics',
  'practicePackTableTitle': 'Table mechanics',
  'practicePackFinishTitle': 'Finishing & Fifty',
  'practiceProgress': '{completed} of {total} completed',
  'practiceTurnRhythmTitle': 'Turn rhythm',
  'practiceTurnRhythmSummary':
      'Draw, play if you can, then discard to end your turn.',
  'practicePendingDiscardTitle': 'Taking the discard',
  'practicePendingDiscardSummary':
      'A taken discard must be used in a play or returned before drawing.',
  'practiceMeldPickerTitle': 'Choosing a legal meld',
  'practiceMeldPickerSummary':
      'Turn selected cards into one exact legal set or sequence.',
  'practiceOpeningTitle': 'Opening to 51',
  'practiceOpeningSummary':
      'Place melds worth the opening requirement in one turn.',
  'practiceBenchmarkTitle': 'Benchmark pressure',
  'practiceBenchmarkSummary':
      'A high first opening raises what everyone else must reach.',
  'practiceSequenceCoverTitle': 'Sequence covers',
  'practiceSequenceCoverSummary':
      'Extend a table run with its direct neighbors.',
  'practiceSetCoverTitle': 'Set covers',
  'practiceSetCoverSummary': 'Extend a set with the missing suit.',
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
  'practiceFiftyClaimTitle': 'Fifty timing',
  'practiceFiftyClaimSummary':
      'Claim Khamsin from the discard before the window closes.',
  'practiceFiftyScoringTitle': 'Fifty scoring',
  'practiceFiftyScoringSummary':
      'The reward for the winner and the penalty for the discarder.',
  'practiceStrictnessTitle': 'Table strictness tiers',
  'practiceStrictnessSummary':
      'What Coaching, Standard, Strict, and Table expect from you.',
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
      'يبدأ صاحب البداية في مرحلة اللعب. بقية الأدوار تبدأ بالسحب من الكومة أو أخذ الرمية السابقة. الرمية المأخوذة تصبح معلقة: يجب استخدامها في لعب قانوني في نفس الدور أو إرجاعها قبل السحب من الكومة.',
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
      'بعد الرمي، اللاعب التالي مباشرة فقط يستطيع إعلان الخمسين، وذلك قبل انتهاء المؤقت. يجب أن تكون الورقة المرمية جزءا من إنهاء قانوني، سواء عبر مجموعات اليد أو تكميلات الطاولة أو التكميلات المتتابعة. وضعا التدريب والقياسي يظهران إجراء الخمسين فقط عندما يكون الإنهاء مثبتا، بينما يسمح الوضعان الصارم والطاولة بإعلانات خاطئة كأخطاء مع عقوبة. إذا انتهى المؤقت يمكن للاعب أخذ الرمية بشكل عادي عند قانونيتها، لكن الإنهاء يسجل كإنهاء عادي وليس خمسين.',
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
  'practicePackCoreTitle': 'أساسيات الدور',
  'practicePackTableTitle': 'آليات الطاولة',
  'practicePackFinishTitle': 'الإنهاء والخمسين',
  'practiceProgress': 'اكتمل {completed} من {total}',
  'practiceTurnRhythmTitle': 'إيقاع الدور',
  'practiceTurnRhythmSummary': 'اسحب، العب إن استطعت، ثم ارم لإنهاء دورك.',
  'practicePendingDiscardTitle': 'أخذ الرمية',
  'practicePendingDiscardSummary':
      'الرمية المأخوذة يجب استخدامها في لعبة أو إرجاعها قبل السحب.',
  'practiceMeldPickerTitle': 'اختيار مجموعة قانونية',
  'practiceMeldPickerSummary':
      'حوّل الأوراق المحددة إلى مجموعة أو تسلسل قانوني واحد بالضبط.',
  'practiceOpeningTitle': 'الافتتاح بـ 51',
  'practiceOpeningSummary': 'ضع مجموعات بقيمة شرط الافتتاح في دور واحد.',
  'practiceBenchmarkTitle': 'ضغط المعيار',
  'practiceBenchmarkSummary':
      'الافتتاح الأول العالي يرفع ما يجب على الآخرين بلوغه.',
  'practiceSequenceCoverTitle': 'تكميلات التسلسل',
  'practiceSequenceCoverSummary': 'مدّد تسلسلا على الطاولة بجيرانه المباشرين.',
  'practiceSetCoverTitle': 'تكميلات المجموعة',
  'practiceSetCoverSummary': 'مدّد مجموعة متشابهة بالشكل الناقص.',
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
  'practiceFiftyClaimTitle': 'توقيت الخمسين',
  'practiceFiftyClaimSummary': 'اطلب الخمسين من الرمية قبل انتهاء المهلة.',
  'practiceFiftyScoringTitle': 'حساب الخمسين',
  'practiceFiftyScoringSummary': 'مكافأة الفائز وعقوبة من رمى الورقة.',
  'practiceStrictnessTitle': 'مستويات صرامة الطاولة',
  'practiceStrictnessSummary':
      'ما تتوقعه منك مستويات التدريب والقياسي والصارم والطاولة.',
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
};
