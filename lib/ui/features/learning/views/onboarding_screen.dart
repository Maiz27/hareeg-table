import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../app/app_routes.dart';
import '../../../../data/persistence/learning_progress_repository.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/cards/showcase_card_fan.dart';
import '../../../core/motif/geometric_motif_painter.dart';
import '../../../core/theme/lounge_tokens.dart';

/// First-launch onboarding flow.
///
/// Orients a new player to Classic Hareeg in a few short portrait pages and
/// points them toward guided practice. Skipping or finishing both mark
/// onboarding as completed so it never interrupts normal play again; lesson
/// progress is untouched either way.
///
/// The home menu always sits beneath this route (the splash hand-off relies
/// on path-based initial route generation; reopen entry points push from
/// screens above home), so skip/finish simply pop back. The route argument
/// [firstRunArgument] only switches the final-page exit copy from "Done" to
/// "Start playing"; [fromPracticeArgument] makes "Try guided practice" pop
/// back to the hub that opened the replay instead of pushing a new one.
class OnboardingScreen extends StatefulWidget {
  /// Creates the onboarding flow.
  const OnboardingScreen({required this.learningRepository, super.key});

  /// Route argument marking the automatic first-launch presentation.
  static const firstRunArgument = 'first-run';

  /// Route argument marking a replay opened from the practice hub, so
  /// "Try guided practice" pops back to it instead of stacking a second hub.
  static const fromPracticeArgument = 'from-practice';

  /// Onboarding and practice progress persistence.
  final LearningProgressRepository learningRepository;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  var _pageIndex = 0;

  static const _pageCount = 4;

  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _onLastPage => _pageIndex == _pageCount - 1;

  Future<void> _persistCompletion() async {
    try {
      final progress = await widget.learningRepository.loadProgress();
      await widget.learningRepository.saveProgress(
        progress.copyWith(onboardingCompleted: true),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to save onboarding completion: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Marks onboarding completed and leaves the flow.
  ///
  /// [toPractice] continues into the guided practice checklist instead of
  /// stopping at the previous screen / home menu.
  Future<void> _finish({required bool toPractice}) async {
    final navigator = Navigator.of(context);
    final openedFromPractice =
        ModalRoute.of(context)?.settings.arguments ==
        OnboardingScreen.fromPracticeArgument;
    await _persistCompletion();
    if (!mounted) {
      return;
    }
    if (!navigator.canPop()) {
      // Defensive fallback: onboarding should never be the root route, but if
      // it ever is, hand off to home rather than stranding the player.
      unawaited(
        navigator.pushReplacementNamed(
          toPractice ? AppRoutes.practice : AppRoutes.home,
        ),
      );
      return;
    }
    if (toPractice && !openedFromPractice) {
      // Replace onboarding with the practice hub so backing out of practice
      // returns to wherever onboarding was opened from (home on first run).
      unawaited(navigator.popAndPushNamed(AppRoutes.practice));
    } else {
      // When the practice hub opened the intro, popping lands back on it.
      navigator.pop();
    }
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final firstRun =
        ModalRoute.of(context)?.settings.arguments ==
        OnboardingScreen.firstRunArgument;
    final pages = [
      _OnboardingPageData(
        hero: const _FanHero(),
        title: strings.onboardingWelcomeTitle,
        body: strings.onboardingWelcomeBody,
      ),
      _OnboardingPageData(
        hero: const _IconHero(icon: Icons.swap_horiz_outlined),
        title: strings.onboardingTurnTitle,
        body: strings.onboardingTurnBody,
      ),
      _OnboardingPageData(
        hero: const _IconHero(icon: Icons.school_outlined),
        title: strings.onboardingLearnTitle,
        body: strings.onboardingLearnBody,
      ),
      _OnboardingPageData(
        hero: const _IconHero(icon: Icons.play_circle_outline),
        title: strings.onboardingReadyTitle,
        body: strings.onboardingReadyBody,
      ),
    ];

    return Scaffold(
      backgroundColor: LoungeTokens.coffeeCharcoal,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _OnboardingBackdrop(),
            Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      LoungeTokens.space4,
                      LoungeTokens.space3,
                      LoungeTokens.space4,
                      0,
                    ),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _onLastPage ? 0 : 1,
                      child: TextButton(
                        onPressed: _onLastPage
                            ? null
                            : () => _finish(toPractice: false),
                        style: TextButton.styleFrom(
                          foregroundColor: LoungeTokens.mutedText,
                          // The theme minimum is full-width; hug the label.
                          minimumSize: const Size(0, 40),
                        ),
                        child: Text(strings.onboardingSkip),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: pages.length,
                    onPageChanged: (index) =>
                        setState(() => _pageIndex = index),
                    itemBuilder: (context, index) =>
                        _OnboardingPage(data: pages[index]),
                  ),
                ),
                _PageDots(count: _pageCount, activeIndex: _pageIndex),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LoungeTokens.space5,
                    LoungeTokens.space4,
                    LoungeTokens.space5,
                    LoungeTokens.space5,
                  ),
                  child: _onLastPage
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _finish(toPractice: true),
                              icon: const Icon(Icons.school_outlined),
                              label: Text(strings.onboardingStartPractice),
                            ),
                            const SizedBox(height: LoungeTokens.space3),
                            OutlinedButton(
                              onPressed: () => _finish(toPractice: false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: LoungeTokens.goldAccent,
                                side: BorderSide(
                                  color: LoungeTokens.goldAccent.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                                minimumSize: const Size.fromHeight(
                                  LoungeTokens.tapTargetPrimary,
                                ),
                              ),
                              child: Text(
                                firstRun
                                    ? strings.onboardingStartPlaying
                                    : strings.onboardingDone,
                              ),
                            ),
                          ],
                        )
                      : FilledButton(
                          onPressed: _next,
                          child: Text(strings.onboardingNext),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.hero,
    required this.title,
    required this.body,
  });

  final Widget hero;
  final String title;
  final String body;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});

  final _OnboardingPageData data;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: LoungeTokens.space6,
        vertical: LoungeTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: LoungeTokens.space4),
          data.hero,
          const SizedBox(height: LoungeTokens.space6),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: LoungeTokens.display,
          ),
          const SizedBox(height: LoungeTokens.space3),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: LoungeTokens.body.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _FanHero extends StatelessWidget {
  const _FanHero();

  @override
  Widget build(BuildContext context) {
    return const ShowcaseCardFan(
      width: 232,
      height: 132,
      motion: ShowcaseFanMotion.idle,
    );
  }
}

class _IconHero extends StatelessWidget {
  const _IconHero({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: LoungeTokens.feltGreen.withValues(alpha: 0.55),
        border: Border.all(color: LoungeTokens.sandLine.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, size: 48, color: LoungeTokens.goldAccent),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == activeIndex ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: i == activeIndex
                  ? LoungeTokens.goldAccent
                  : LoungeTokens.sandLine.withValues(alpha: 0.35),
            ),
          ),
      ],
    );
  }
}

class _OnboardingBackdrop extends StatelessWidget {
  const _OnboardingBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -52,
          left: -50,
          child: LoungeMotif(
            variant: LoungeMotifVariant.medallion,
            opacity: 0.06,
            strokeWidth: 1.0,
            density: 4,
            size: const Size.square(220),
          ),
        ),
        Positioned(
          bottom: -40,
          right: -56,
          child: LoungeMotif(
            variant: LoungeMotifVariant.medallion,
            opacity: 0.05,
            strokeWidth: 1.0,
            density: 5,
            size: const Size.square(200),
          ),
        ),
      ],
    );
  }
}
