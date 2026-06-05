import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/learning_progress_repository.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/learning/views/onboarding_screen.dart';
import 'package:hareeg_table/ui/features/splash/views/splash_screen.dart';

import '../../../support/test_fixtures.dart';

void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;

  testWidgets('first launch routes the splash into onboarding', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(
      _testApp(learning: learning, initialRoute: AppRoutes.splash),
    );
    await tester.pump();

    // Tap-to-skip the splash dwell.
    await tester.tap(find.byType(SplashScreen));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Welcome to the table'), findsOneWidget);
  });

  testWidgets('completed onboarding routes the splash straight home', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository(
      progress: LearningProgress.defaults().copyWith(
        onboardingCompleted: true,
      ),
    );
    await tester.pumpWidget(
      _testApp(learning: learning, initialRoute: AppRoutes.splash),
    );
    await tester.pump();

    await tester.tap(find.byType(SplashScreen));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('New Game'), findsOneWidget);
  });

  testWidgets('skipping onboarding lands on home and persists completion '
      'without touching lessons', (tester) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(
      _testApp(learning: learning, initialRoute: AppRoutes.splash),
    );
    await tester.pump();
    await tester.tap(find.byType(SplashScreen));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();

    expect(find.text('New Game'), findsOneWidget);
    expect(learning.progress.onboardingCompleted, isTrue);
    expect(
      learning.progress.statusFor('turn-rhythm'),
      PracticeLessonStatus.notStarted,
    );
    expect(learning.progress.completedCount(['turn-rhythm', 'opening-51']), 0);
  });

  testWidgets('finishing onboarding pages through and lands on home', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(
      _testApp(learning: learning, initialRoute: AppRoutes.splash),
    );
    await tester.pump();
    await tester.tap(find.byType(SplashScreen));
    await tester.pumpAndSettle();

    for (var page = 0; page < 3; page++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Ready when you are'), findsOneWidget);
    await tester.tap(find.text('Start playing'));
    await tester.pumpAndSettle();

    expect(find.text('New Game'), findsOneWidget);
    expect(learning.progress.onboardingCompleted, isTrue);
  });

  testWidgets('finishing onboarding into guided practice opens the hub', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository();
    await tester.pumpWidget(
      _testApp(learning: learning, initialRoute: AppRoutes.splash),
    );
    await tester.pump();
    await tester.tap(find.byType(SplashScreen));
    await tester.pumpAndSettle();

    for (var page = 0; page < 3; page++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Try guided practice'));
    await tester.pumpAndSettle();

    expect(find.text('Guided practice'), findsWidgets);
    expect(learning.progress.onboardingCompleted, isTrue);

    // Home sits beneath the hub so backing out never strands the player.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('New Game'), findsOneWidget);
  });

  testWidgets('onboarding can be reopened from Rules/Help and popped back', (
    tester,
  ) async {
    final learning = MemoryLearningProgressRepository(
      progress: LearningProgress.defaults().copyWith(
        onboardingCompleted: true,
      ),
    );
    await tester.pumpWidget(_testApp(learning: learning));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rules / Help'));
    await tester.pumpAndSettle();
    expect(find.text('New to Hareeg?'), findsOneWidget);

    await tester.tap(find.text('Replay intro'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    for (var page = 0; page < 3; page++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    // Reopened mode labels the exit "Done" and pops back to the opener.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Classic Hareeg rules'), findsWidgets);
  });

  testWidgets('home exposes the guided practice entry', (tester) async {
    final learning = MemoryLearningProgressRepository(
      progress: LearningProgress.defaults().copyWith(
        onboardingCompleted: true,
      ),
    );
    await tester.pumpWidget(_testApp(learning: learning));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Guided practice'));
    await tester.pumpAndSettle();

    expect(find.text('0 of 15 completed'), findsOneWidget);
  });

  testWidgets('rules/help exposes the guided practice entry', (tester) async {
    final learning = MemoryLearningProgressRepository(
      progress: LearningProgress.defaults().copyWith(
        onboardingCompleted: true,
      ),
    );
    await tester.pumpWidget(_testApp(learning: learning));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rules / Help'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guided practice'));
    await tester.pumpAndSettle();

    expect(find.text('0 of 15 completed'), findsOneWidget);
  });
}

Widget _testApp({
  required MemoryLearningProgressRepository learning,
  String initialRoute = AppRoutes.home,
}) {
  return HareegTableApp(
    preferencesRepository: MemoryPreferencesRepository(),
    matchRepository: MemoryMatchRepository(),
    learningProgressRepository: learning,
    initialRouteOverride: initialRoute,
  );
}
