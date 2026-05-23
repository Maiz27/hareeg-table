import 'package:flutter/widgets.dart';

import '../domain/classic_hareeg/models/player_seat.dart';
import '../domain/classic_hareeg/models/playing_card.dart';

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
  String get homeSubtitle => _v('homeSubtitle');
  String get newGame => _v('newGame');
  String get continueGame => _v('continueGame');
  String get settings => _v('settings');
  String get rulesHelp => _v('rulesHelp');
  String get noSavedMatch => _v('noSavedMatch');
  String get checkingSavedMatch => _v('checkingSavedMatch');
  String get resumeSavedMatch => _v('resumeSavedMatch');
  String get abandonSavedMatch => _v('abandonSavedMatch');
  String get seatsLabel => _v('seatsLabel');
  String get openingLabel => _v('openingLabel');
  String get fiftyLabel => _v('fiftyLabel');
  String get plannedModes => _v('plannedModes');
  String get hareeg14 => _v('hareeg14');
  String get fifties => _v('fifties');
  String get comingSoon => _v('comingSoon');
  String get classicModeTitle => _v('classicModeTitle');
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
  String get rulesReady => _v('rulesReady');
  String get cpuReady => _v('cpuReady');
  String get persistenceReady => _v('persistenceReady');
  String get splashTagline => _v('splashTagline');
  String get splashTapToContinue => _v('splashTapToContinue');
  String get scores => _v('scores');
  String get pauseTable => _v('pauseTable');
  String get scoresTitle => _v('scoresTitle');
  String get pauseTitle => _v('pauseTitle');
  String get resumeTable => _v('resumeTable');
  String get leaveTable => _v('leaveTable');
  String get pauseInMatchControls => _v('pauseInMatchControls');
  String get aidsLabel => _v('aidsLabel');
  String get aidsHelp => _v('aidsHelp');
  String get motionSpeedLabel => _v('motionSpeedLabel');
  String get fastCpuTurns => _v('fastCpuTurns');
  String get fastCpuTurnsDescription => _v('fastCpuTurnsDescription');
  String get hapticsLabel => _v('hapticsLabel');
  String get hapticsHelp => _v('hapticsHelp');
  String get soundLabel => _v('soundLabel');
  String get soundHelp => _v('soundHelp');
  String get cardThemeLabel => _v('cardThemeLabel');
  String get cardThemeHelp => _v('cardThemeHelp');
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
  String get aidGuidedDescription => _v('aidGuidedDescription');
  String get aidStandardDescription => _v('aidStandardDescription');
  String get aidTableModeDescription => _v('aidTableModeDescription');
  String get openScoresButton => _v('openScoresButton');
  String get openPauseButton => _v('openPauseButton');
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
  String get assistance => _v('assistance');
  String get assistanceDescription => _v('assistanceDescription');
  String get memoryJokerDisplay => _v('memoryJokerDisplay');
  String get memoryJokerDisplayDescription =>
      _v('memoryJokerDisplayDescription');
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
  String get rulePreset => _v('rulePreset');
  String get assisted => _v('assisted');
  String get penalties => _v('penalties');
  String get hard17 => _v('hard17');
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
  String get guided => _v('guided');
  String get standard => _v('standard');
  String get tableMode => _v('tableMode');
  String get sandlineLounge => _v('sandlineLounge');
  String get darkFelt => _v('darkFelt');
  String get lightWood => _v('lightWood');
  String get midnightSapphire => _v('midnightSapphire');
  String get crimsonClay => _v('crimsonClay');
  String get close => _v('close');
  String get empty => _v('empty');
  String get noMeldsYet => _v('noMeldsYet');
  String get roundSummary => _v('roundSummary');
  String get continueNextRound => _v('continueNextRound');
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

  String decksValue(int value) => isRtl ? '$value رزم' : '$value decks';

  String fiftySecondsValue(int value) => isRtl ? '$value ثوان' : '${value}s';

  String houseRulesSummary({
    required int deckCount,
    required int fiftyTimerSeconds,
    required String aidsLabel,
  }) {
    if (isRtl) {
      return '$deckCount رزم  ·  $fiftyTimerSeconds ثوان للخمسين  ·  مساعدات $aidsLabel';
    }
    return '$deckCount decks  ·  ${fiftyTimerSeconds}s fifty  ·  $aidsLabel aids';
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

  String roundSummaryDetailNormal() {
    return isRtl
        ? 'الفائز يسجل -1. بقية اللاعبين النشطين يسجلون عدد أوراقهم المتبقية.'
        : 'Winner scores -1. Other active players score their remaining card count.';
  }

  String roundSummaryDetailFifty({required bool firstRoundException}) {
    if (isRtl) {
      return firstRoundException
          ? 'استثناء خمسين الجولة الأولى: الفائز يسجل -1؛ الرامي يأخذ الأوراق المتبقية زائد 3.'
          : 'فائز الخمسين يسجل -3؛ الرامي يأخذ الأوراق المتبقية زائد 3.';
    }
    return firstRoundException
        ? 'First-round Fifty exception: winner scores -1; discarder takes remaining cards plus 3.'
        : 'Fifty winner scores -3; discarder takes remaining cards plus 3.';
  }

  String roundSummaryDetailDraw() {
    return isRtl
        ? 'لا توجد تغييرات في النقاط. نفس اللاعب يبدأ مرة أخرى.'
        : 'No score changes. The same starter deals again.';
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
      'Assisted mode blocks this illegal action.' =>
        'وضع المساعدة يمنع هذه الحركة غير القانونية.',
      'Table penalty: +3.' => 'عقوبة الطاولة: +3.',
      'Hard table mistake: +17 and out of this round.' =>
        'خطأ الطاولة الصعبة: +17 وخروج من هذه الجولة.',
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
  'homeSubtitle': 'Offline Classic Hareeg',
  'newGame': 'New Game',
  'continueGame': 'Continue',
  'settings': 'Settings',
  'rulesHelp': 'Rules / Help',
  'noSavedMatch': 'No saved match yet',
  'checkingSavedMatch': 'Checking saved match...',
  'resumeSavedMatch': 'Resume saved Classic Hareeg table',
  'abandonSavedMatch': 'Abandon saved match',
  'seatsLabel': 'Seats',
  'openingLabel': 'Opening',
  'fiftyLabel': 'Fifty',
  'plannedModes': 'Planned modes',
  'hareeg14': 'Hareeg 14',
  'fifties': 'Fifties',
  'comingSoon': 'Coming soon',
  'classicModeTitle': 'Classic Hareeg',
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
      'After a discard, only the immediate next player can claim Fifty, and only before the timer expires. The discarded card must be part of a legal finish, including hand melds, table covers, or chained covers. In Assisted mode, the Fifty action appears only when valid. If the timer is missed, the player may still take the discard normally when legal, but the finish scores as normal instead of Fifty.',
  'helpScoringTitle': 'Scoring',
  'helpScoringBody':
      'Normal winners score -1. In Fifty, the winner scores -3, except the first dealt round uses -1, and the discarder adds remaining cards plus 3. Other active players add remaining card count. Drawn rounds do not change scores. Players at 31 or more are eliminated, and the last remaining player wins.',
  'helpMistakePresetsTitle': 'Mistake presets',
  'helpMistakePresetsBody':
      'Assisted blocks illegal actions. Table penalties allow selected mistakes with +3. Hard table 17 allows selected mistakes with +17 and removes that player from the current round. Normal joker discard stays blocked in every preset.',
  'helpPauseResumeTitle': 'Pause and resume',
  'helpPauseResumeBody':
      'The app saves active Classic Hareeg table state locally at safe table changes. Continue resumes the saved hands, stock, discard pile, turn phase, pending discard, and setup. Abandon saved match clears the local save.',
  'helpPlannedModesTitle': 'Planned modes',
  'helpPlannedModesBody':
      'Hareeg 14 and a dedicated Fifties mode are planned future modes. The first release focuses on Classic Hareeg.',
  'rulesReady': 'Pure Dart rules core',
  'cpuReady': 'CPU strategy boundary',
  'persistenceReady': 'Local preferences boundary',
  'splashTagline': 'Offline Classic Hareeg',
  'splashTapToContinue': 'Tap to continue',
  'scores': 'Scores',
  'pauseTable': 'Pause',
  'scoresTitle': 'Match scores',
  'pauseTitle': 'Paused',
  'resumeTable': 'Resume table',
  'leaveTable': 'Leave table',
  'pauseInMatchControls': 'In-match settings',
  'aidsLabel': 'Table aids',
  'aidsHelp':
      'Aids only change which hints the app shows. Scoring stays the same.',
  'motionSpeedLabel': 'Motion speed',
  'fastCpuTurns': 'Fast CPU turns',
  'fastCpuTurnsDescription':
      'Shorten CPU pauses and card flights so opponent turns resolve faster.',
  'hapticsLabel': 'Table haptics',
  'hapticsHelp': 'Light vibrations on taps, drops, and Fifty.',
  'soundLabel': 'Table sounds',
  'soundHelp': 'Play card movement and table feedback sounds.',
  'cardThemeLabel': 'Card theme',
  'cardThemeHelp': 'Themes can only be changed outside an active match.',
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
  'aidGuidedDescription':
      'Full hints. Legal targets glow, pending warnings show, invalid moves explain themselves, Fifty prompts appear when valid.',
  'aidStandardDescription': 'Meld picker remains; fewer proactive hints.',
  'aidTableModeDescription':
      'Minimal aids while preserving accessibility and state feedback.',
  'openScoresButton': 'Scores',
  'openPauseButton': 'Pause',
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
  'assistance': 'Assistance',
  'assistanceDescription': 'Hints and joker memory display.',
  'memoryJokerDisplay': 'Memory joker display',
  'memoryJokerDisplayDescription': 'Briefly show represented joker identities.',
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
  'rulePreset': 'Rule preset',
  'assisted': 'Assisted',
  'penalties': 'Penalties',
  'hard17': 'Hard 17',
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
  'guided': 'Guided',
  'standard': 'Standard',
  'tableMode': 'Table mode',
  'sandlineLounge': 'Sandline Lounge',
  'darkFelt': 'Dark felt',
  'lightWood': 'Light wood',
  'midnightSapphire': 'Midnight sapphire',
  'crimsonClay': 'Crimson clay',
  'close': 'Close',
  'empty': 'Empty',
  'noMeldsYet': 'No melds yet',
  'roundSummary': 'Round summary',
  'continueNextRound': 'Continue next round',
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
};

const _arabicValues = {
  'appTitle': 'طاولة حريق',
  'homeTitle': 'طاولة حريق',
  'homeSubtitle': 'حريق كلاسيكي دون اتصال',
  'newGame': 'لعبة جديدة',
  'continueGame': 'متابعة',
  'settings': 'الإعدادات',
  'rulesHelp': 'القواعد / المساعدة',
  'noSavedMatch': 'لا توجد مباراة محفوظة بعد',
  'checkingSavedMatch': 'جار فحص المباراة المحفوظة...',
  'resumeSavedMatch': 'استئناف طاولة حريق الكلاسيكية المحفوظة',
  'abandonSavedMatch': 'حذف المباراة المحفوظة',
  'seatsLabel': 'المقاعد',
  'openingLabel': 'الافتتاح',
  'fiftyLabel': 'الخمسين',
  'plannedModes': 'أطوار مخططة',
  'hareeg14': 'حريق 14',
  'fifties': 'الخمسينات',
  'comingSoon': 'قريبا',
  'classicModeTitle': 'حريق الكلاسيكي',
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
      'بعد الرمي، اللاعب التالي مباشرة فقط يستطيع إعلان الخمسين، وذلك قبل انتهاء المؤقت. يجب أن تكون الورقة المرمية جزءا من إنهاء قانوني، سواء عبر مجموعات اليد أو تكميلات الطاولة أو التكميلات المتتابعة. في وضع المساعدة يظهر إجراء الخمسين فقط عندما يكون صحيحا. إذا انتهى المؤقت يمكن للاعب أخذ الرمية بشكل عادي عند قانونيتها، لكن الإنهاء يسجل كإنهاء عادي وليس خمسين.',
  'helpScoringTitle': 'التسجيل',
  'helpScoringBody':
      'الفائز العادي يسجل -1. في الخمسين يسجل الفائز -3، ما عدا الجولة الأولى الموزعة فتستخدم -1، ويضيف الرامي الأوراق المتبقية لديه زائد 3. بقية اللاعبين النشطين يضيفون عدد أوراقهم المتبقية. الجولات المسحوبة لا تغير النقاط. اللاعب الذي يصل إلى 31 أو أكثر يخرج، وآخر لاعب باق يفوز.',
  'helpMistakePresetsTitle': 'إعدادات الأخطاء',
  'helpMistakePresetsBody':
      'وضع المساعدة يمنع الإجراءات غير القانونية. عقوبات الطاولة تسمح بأخطاء محددة مع +3. طاولة 17 الصعبة تسمح بأخطاء محددة مع +17 وتخرج ذلك اللاعب من الجولة الحالية. رمي الجوكر العادي يبقى ممنوعا في كل الإعدادات.',
  'helpPauseResumeTitle': 'الإيقاف والاستئناف',
  'helpPauseResumeBody':
      'يحفظ التطبيق حالة طاولة حريق الكلاسيكية محليا عند تغييرات الطاولة الآمنة. المتابعة تستعيد الأيدي، كومة السحب، كومة الرمي، مرحلة الدور، الرمية المعلقة، والإعدادات. حذف المباراة المحفوظة يمسح الحفظ المحلي.',
  'helpPlannedModesTitle': 'أطوار مخططة',
  'helpPlannedModesBody':
      'حريق 14 وطور مخصص للخمسينات مخططان لاحقا. الإصدار الأول يركز على حريق الكلاسيكي.',
  'rulesReady': 'نواة قواعد Dart صافية',
  'cpuReady': 'حدود استراتيجية اللاعب الآلي',
  'persistenceReady': 'حدود تفضيلات محلية',
  'splashTagline': 'حريق كلاسيكي دون اتصال',
  'splashTapToContinue': 'اضغط للمتابعة',
  'scores': 'النقاط',
  'pauseTable': 'إيقاف',
  'scoresTitle': 'نقاط المباراة',
  'pauseTitle': 'متوقفة',
  'resumeTable': 'استئناف الطاولة',
  'leaveTable': 'مغادرة الطاولة',
  'pauseInMatchControls': 'إعدادات أثناء المباراة',
  'aidsLabel': 'مساعدات الطاولة',
  'aidsHelp': 'المساعدات تغير التلميحات فقط. التسجيل لا يتغير.',
  'motionSpeedLabel': 'سرعة الحركة',
  'hapticsLabel': 'اهتزازات الطاولة',
  'hapticsHelp': 'اهتزازات خفيفة عند الضغط، الإفلات، والخمسين.',
  'soundLabel': 'أصوات الطاولة',
  'soundHelp': 'شغّل أصوات حركة الأوراق وتنبيهات الطاولة.',
  'cardThemeLabel': 'سمة الأوراق',
  'cardThemeHelp': 'يمكن تغيير السمات خارج المباراة النشطة فقط.',
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
  'aidGuidedDescription':
      'تلميحات كاملة. الأهداف القانونية تتوهج، التحذيرات المعلقة تظهر، الحركات الخاطئة تشرح نفسها، وتظهر مطالبات الخمسين عند صحتها.',
  'aidStandardDescription': 'يبقى منتقي المجموعات مع تلميحات استباقية أقل.',
  'aidTableModeDescription':
      'مساعدات قليلة مع الحفاظ على الوصولية وتغذية حالة اللعب.',
  'openScoresButton': 'النقاط',
  'openPauseButton': 'إيقاف',
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
  'assistance': 'المساعدة',
  'assistanceDescription': 'تلميحات وعرض ذاكرة الجوكر.',
  'memoryJokerDisplay': 'عرض ذاكرة الجوكر',
  'memoryJokerDisplayDescription': 'اعرض هويات الجوكر الممثلة لفترة قصيرة.',
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
  'rulePreset': 'إعداد القواعد',
  'assisted': 'مساعدة',
  'penalties': 'عقوبات',
  'hard17': 'صعبة 17',
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
  'guided': 'موجهة',
  'standard': 'قياسية',
  'tableMode': 'وضع الطاولة',
  'sandlineLounge': 'Sandline Lounge',
  'darkFelt': 'لباد داكن',
  'lightWood': 'خشب فاتح',
  'midnightSapphire': 'ياقوت ليلي',
  'crimsonClay': 'طين قرمزي',
  'close': 'إغلاق',
  'empty': 'فارغ',
  'noMeldsYet': 'لا توجد مجموعات بعد',
  'roundSummary': 'ملخص الجولة',
  'continueNextRound': 'متابعة الجولة التالية',
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
};
