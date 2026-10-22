import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/data/updates/update_cache_repository.dart';
import 'package:hareeg_table/data/updates/update_service.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/updates/widgets/update_available_panel.dart';

import '../../../data/updates/update_test_doubles.dart';
import '../../../support/test_fixtures.dart';

void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;
  final strings = AppStrings.english;

  Future<MemoryPreferencesRepository> pumpHome(
    WidgetTester tester, {
    required FakeUpdateChannel channel,
    GamePreferences? preferences,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prefs = MemoryPreferencesRepository()
      ..preferences = preferences ?? GamePreferences.defaults();
    await tester.pumpWidget(
      HareegTableApp(
        matchRepository: MemoryMatchRepository(),
        historyRepository: MemoryMatchHistoryRepository(),
        preferencesRepository: prefs,
        updateService: UpdateService(
          channel: channel,
          installedVersion: const FakeInstalledVersionSource('1.0.0-alpha.12'),
          cache: UpdateCacheRepository(store: MemoryKeyValueStore()),
          supported: true,
        ),
        initialRouteOverride: AppRoutes.home,
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('a newer release shows the panel; Skip hides and persists it', (
    tester,
  ) async {
    final channel = FakeUpdateChannel(
      release: fakeRelease(
        'v1.0.0-alpha.13',
        notes: '## New\n- **Faster** CPUs',
      ),
    );
    final prefs = await pumpHome(tester, channel: channel);

    expect(find.byType(UpdateAvailablePanel), findsOneWidget);
    expect(
      find.text(strings.updateAvailableTitle('1.0.0-alpha.13')),
      findsOneWidget,
    );
    expect(find.text('New Faster CPUs'), findsOneWidget);
    expect(find.text(strings.updateDownload), findsOneWidget);
    expect(find.text(strings.updateReleaseNotes), findsOneWidget);
    // The menu is still all there.
    expect(find.text(strings.newGame), findsOneWidget);

    await tester.tap(find.text(strings.updateSkipVersion));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateAvailablePanel), findsNothing);
    expect(prefs.preferences.skippedUpdateVersion, '1.0.0-alpha.13');
  });

  testWidgets('a skipped release does not prompt', (tester) async {
    final channel = FakeUpdateChannel(release: fakeRelease('v1.0.0-alpha.13'));
    await pumpHome(
      tester,
      channel: channel,
      preferences: GamePreferences.defaults().copyWith(
        skippedUpdateVersion: '1.0.0-alpha.13',
      ),
    );

    expect(channel.fetchCount, 1);
    expect(find.byType(UpdateAvailablePanel), findsNothing);
  });

  testWidgets('automatic checks switched off never reach the channel', (
    tester,
  ) async {
    final channel = FakeUpdateChannel(release: fakeRelease('v1.0.0-alpha.13'));
    await pumpHome(
      tester,
      channel: channel,
      preferences: GamePreferences.defaults().copyWith(
        updateCheckEnabled: false,
      ),
    );

    expect(channel.fetchCount, 0);
    expect(find.byType(UpdateAvailablePanel), findsNothing);
  });

  testWidgets('Later collapses the panel without skipping', (tester) async {
    final channel = FakeUpdateChannel(release: fakeRelease('v1.0.0-alpha.13'));
    final prefs = await pumpHome(tester, channel: channel);

    await tester.tap(find.byTooltip(strings.updateLater));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateAvailablePanel), findsNothing);
    expect(prefs.preferences.skippedUpdateVersion, isNull);
  });
}
