import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/data/updates/update_cache_repository.dart';
import 'package:hareeg_table/data/updates/update_service.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/updates/widgets/update_available_dialog.dart';

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

  testWidgets('a newer release opens the dialog; Skip closes and persists it', (
    tester,
  ) async {
    final channel = FakeUpdateChannel(
      releases: [
        fakeRelease(
          'v1.0.0-alpha.13',
          notes:
              '## [1.0.0-alpha.13](https://x.test) (2026-10-20)\n\n'
              '### Features\n\n'
              '* **cpu:** faster CPUs ([abc1234](https://x.test/c))\n'
              '### Bug Fixes\n\n'
              '* the round ends\n',
        ),
        fakeRelease('v1.0.0-alpha.12', notes: '* already installed'),
      ],
    );
    final prefs = await pumpHome(tester, channel: channel);

    expect(find.byType(UpdateAvailableDialog), findsOneWidget);
    expect(
      find.text(strings.updateAvailableTitle('1.0.0-alpha.13')),
      findsOneWidget,
    );
    expect(
      find.text(strings.updateInstalledVersion('1.0.0-alpha.12')),
      findsOneWidget,
    );
    // Notes are headed bullets, not one run-on line.
    expect(find.text('Features'), findsOneWidget);
    expect(find.text('cpu: faster CPUs'), findsOneWidget);
    expect(find.text('Bug Fixes'), findsOneWidget);
    expect(find.text('the round ends'), findsOneWidget);
    // One release: the title names it, so no version heading, and the
    // installed release is listed, so nothing is missing.
    expect(find.text('1.0.0-alpha.13'), findsNothing);
    expect(find.text('already installed'), findsNothing);
    expect(find.text(strings.updateEarlierReleasesUnlisted), findsNothing);
    expect(find.text(strings.updateDownload), findsOneWidget);
    expect(find.text(strings.updateReleaseNotes), findsOneWidget);
    // The menu is still underneath, not pushed around.
    expect(find.text(strings.newGame), findsOneWidget);

    await tester.tap(find.text(strings.updateSkipVersion));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateAvailableDialog), findsNothing);
    expect(prefs.preferences.skippedUpdateVersion, '1.0.0-alpha.13');
  });

  testWidgets('two releases behind shows both, each under its version', (
    tester,
  ) async {
    final channel = FakeUpdateChannel(
      releases: [
        fakeRelease('v1.0.0-alpha.14', notes: '### Features\n* newest change'),
        fakeRelease('v1.0.0-alpha.13', notes: '### Bug Fixes\n* older fix'),
        fakeRelease('v1.0.0-alpha.12', notes: '* already installed'),
      ],
    );
    final prefs = await pumpHome(tester, channel: channel);

    expect(
      find.text(strings.updateAvailableTitle('1.0.0-alpha.14')),
      findsOneWidget,
    );
    final newest = find.text('1.0.0-alpha.14');
    final older = find.text('1.0.0-alpha.13');
    expect(newest, findsOneWidget);
    expect(older, findsOneWidget);
    expect(find.text('newest change'), findsOneWidget);
    expect(find.text('older fix'), findsOneWidget);
    expect(find.text('already installed'), findsNothing);
    // Newest first.
    expect(tester.getTopLeft(newest).dy, lessThan(tester.getTopLeft(older).dy));
    expect(
      tester.getTopLeft(find.text('newest change')).dy,
      lessThan(tester.getTopLeft(older).dy),
    );
    expect(find.text(strings.updateEarlierReleasesUnlisted), findsNothing);

    // Skip records the newest version, not one of the older ones.
    await tester.tap(find.text(strings.updateSkipVersion));
    await tester.pumpAndSettle();
    expect(prefs.preferences.skippedUpdateVersion, '1.0.0-alpha.14');
  });

  testWidgets('says so when a truncated listing may miss older releases', (
    tester,
  ) async {
    final channel = FakeUpdateChannel(
      releases: [
        fakeRelease('v1.0.0-alpha.15', notes: '* fifteen'),
        fakeRelease('v1.0.0-alpha.14', notes: '* fourteen'),
      ],
      mayBeTruncated: true,
    );
    await pumpHome(tester, channel: channel);

    expect(find.byType(UpdateAvailableDialog), findsOneWidget);
    expect(find.text('fifteen'), findsOneWidget);
    expect(find.text('fourteen'), findsOneWidget);
    expect(find.text(strings.updateEarlierReleasesUnlisted), findsOneWidget);
  });

  testWidgets('a complete listing never says releases are missing', (
    tester,
  ) async {
    final channel = FakeUpdateChannel(
      releases: [
        fakeRelease('v1.0.0-alpha.15', notes: '* fifteen'),
        fakeRelease('v1.0.0-alpha.14', notes: '* fourteen'),
      ],
    );
    await pumpHome(tester, channel: channel);

    expect(find.byType(UpdateAvailableDialog), findsOneWidget);
    expect(find.text('fifteen'), findsOneWidget);
    expect(find.text(strings.updateEarlierReleasesUnlisted), findsNothing);
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
    expect(find.byType(UpdateAvailableDialog), findsNothing);
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
    expect(find.byType(UpdateAvailableDialog), findsNothing);
  });

  testWidgets('Later closes the dialog without skipping', (tester) async {
    final channel = FakeUpdateChannel(release: fakeRelease('v1.0.0-alpha.13'));
    final prefs = await pumpHome(tester, channel: channel);

    await tester.tap(find.byTooltip(strings.updateLater));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateAvailableDialog), findsNothing);
    expect(prefs.preferences.skippedUpdateVersion, isNull);
  });

  testWidgets('tapping outside the dialog counts as Later', (tester) async {
    final channel = FakeUpdateChannel(release: fakeRelease('v1.0.0-alpha.13'));
    final prefs = await pumpHome(tester, channel: channel);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateAvailableDialog), findsNothing);
    expect(prefs.preferences.skippedUpdateVersion, isNull);
  });

  testWidgets('Download closes the dialog without skipping the release', (
    tester,
  ) async {
    final channel = FakeUpdateChannel(release: fakeRelease('v1.0.0-alpha.13'));
    final prefs = await pumpHome(tester, channel: channel);

    await tester.tap(find.text(strings.updateDownload));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateAvailableDialog), findsNothing);
    expect(prefs.preferences.skippedUpdateVersion, isNull);
  });
}
