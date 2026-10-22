import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/data/updates/update_cache_repository.dart';
import 'package:hareeg_table/data/updates/update_channel.dart';
import 'package:hareeg_table/data/updates/update_service.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/card_theme_registry.dart';
import 'package:hareeg_table/ui/features/settings/models/settings_section.dart';
import 'package:hareeg_table/ui/features/settings/views/licenses_screen.dart';
import 'package:hareeg_table/ui/features/settings/views/settings_screen.dart';
import 'package:hareeg_table/ui/features/updates/update_prompt_controller.dart';
import 'package:hareeg_table/ui/features/updates/widgets/update_available_dialog.dart';

import '../../../data/updates/update_test_doubles.dart';
import '../../../support/test_fixtures.dart';

void main() {
  final strings = AppStrings.english;

  UpdatePromptController controllerOver(FakeUpdateChannel channel) {
    final controller = UpdatePromptController(
      service: UpdateService(
        channel: channel,
        installedVersion: const FakeInstalledVersionSource('1.0.0-alpha.12'),
        cache: UpdateCacheRepository(store: MemoryKeyValueStore()),
        supported: true,
      ),
      preferences: () async => GamePreferences.defaults(),
      onSkip: (_) async {},
      openUrl: (_) async => true,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('Settings: Updates section', () {
    Future<void> pumpSettings(
      WidgetTester tester, {
      UpdatePromptController? updates,
      bool showUpdateSettings = true,
      ValueChanged<GamePreferences>? onUpdate,
    }) async {
      var preferences = GamePreferences.defaults();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => SettingsScreen(
              preferences: preferences,
              onUpdate: (value) {
                onUpdate?.call(value);
                setState(() => preferences = value);
              },
              cardThemes: CardThemeRegistry.all(),
              isMatchActive: false,
              initialSection: SettingsSection.updates,
              showUpdateSettings: showUpdateSettings,
              updates: updates,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the switch is on by default and saves when turned off', (
      tester,
    ) async {
      final saves = <GamePreferences>[];
      await pumpSettings(tester, onUpdate: saves.add);
      final toggle = find.text(strings.updateCheckAutomatically);
      await tester.scrollUntilVisible(toggle, 160);
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch).last;
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(saves, hasLength(1));
      expect(saves.single.updateCheckEnabled, isFalse);
    });

    testWidgets('the manual check row asks the channel and offers a release', (
      tester,
    ) async {
      final channel = FakeUpdateChannel(
        release: fakeRelease('v1.0.0-alpha.13'),
      );
      await pumpSettings(tester, updates: controllerOver(channel));
      final row = find.text(strings.checkForUpdates);
      await tester.scrollUntilVisible(row, 160);
      await tester.pumpAndSettle();
      expect(
        find.text(strings.updateInstalledVersion('1.0.0-alpha.12')),
        findsOneWidget,
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(channel.fetchCount, 1);
      expect(find.byType(UpdateAvailableDialog), findsOneWidget);

      // Closing it leaves a way to see the offer again.
      await tester.tap(find.byTooltip(strings.updateLater));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateAvailableDialog), findsNothing);
      await tester.tap(find.text(strings.updateViewOffer));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateAvailableDialog), findsOneWidget);
    });

    testWidgets('the section is hidden where updates are unsupported', (
      tester,
    ) async {
      await pumpSettings(tester, showUpdateSettings: false);
      await tester.scrollUntilVisible(find.text(strings.aboutLicenses), 160);
      expect(find.text(strings.updatesSectionTitle), findsNothing);
      expect(find.text(strings.checkForUpdates), findsNothing);
    });
  });

  group('About: Check for updates', () {
    Future<void> pumpAbout(WidgetTester tester, FakeUpdateChannel channel) {
      return tester.pumpWidget(
        MaterialApp(
          home: LicensesScreen(
            themes: CardThemeRegistry.all(),
            updates: controllerOver(channel),
          ),
        ),
      );
    }

    testWidgets('shows the installed version and reports up to date', (
      tester,
    ) async {
      final channel = FakeUpdateChannel(
        release: fakeRelease('v1.0.0-alpha.12'),
      );
      await pumpAbout(tester, channel);
      await tester.pumpAndSettle();

      expect(
        find.text(strings.updateInstalledVersion('1.0.0-alpha.12')),
        findsOneWidget,
      );
      await tester.tap(find.text(strings.checkForUpdates));
      await tester.pumpAndSettle();

      expect(channel.fetchCount, 1);
      expect(find.text(strings.updateUpToDate), findsOneWidget);
    });

    testWidgets('a newer release opens the update dialog', (tester) async {
      final channel = FakeUpdateChannel(
        release: fakeRelease('v1.0.0-alpha.13'),
      );
      await pumpAbout(tester, channel);
      await tester.pumpAndSettle();

      await tester.tap(find.text(strings.checkForUpdates));
      await tester.pumpAndSettle();

      expect(find.byType(UpdateAvailableDialog), findsOneWidget);
      expect(find.text(strings.updateDownload), findsOneWidget);
    });

    testWidgets('reports a failed check', (tester) async {
      final channel = FakeUpdateChannel(
        failure: const UpdateCheckException(UpdateCheckFailureKind.network),
      );
      await pumpAbout(tester, channel);
      await tester.pumpAndSettle();

      await tester.tap(find.text(strings.checkForUpdates));
      await tester.pumpAndSettle();

      expect(find.text(strings.updateCheckFailed), findsOneWidget);
    });
  });
}
