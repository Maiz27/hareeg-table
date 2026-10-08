import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/app/app_routes.dart';
import 'package:hareeg_table/app/hareeg_table_app.dart';
import 'package:hareeg_table/data/persistence/preferences_repository.dart';
import 'package:hareeg_table/l10n/app_strings.dart';
import 'package:hareeg_table/ui/core/cards/showcase_card_fan.dart';
import 'package:hareeg_table/ui/features/match_reports/diagnostics_consent_notice.dart';
import 'package:hareeg_table/ui/features/match_reports/match_report_diagnostics.dart';

import '../../../support/fake_diagnostics.dart';
import '../../../support/test_fixtures.dart';

/// First-run disclosure and Settings opt-out gate every transmission (HT-56).
void main() {
  ShowcaseCardFan.disableLoopingMotionForTesting = true;
  final strings = AppStrings.english;

  Future<MemoryPreferencesRepository> pumpApp(
    WidgetTester tester, {
    required MatchReportDiagnostics diagnostics,
    GamePreferences? preferences,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository = MemoryPreferencesRepository();
    if (preferences != null) {
      repository.preferences = preferences;
    }
    await tester.pumpWidget(
      HareegTableApp(
        matchRepository: MemoryMatchRepository(),
        historyRepository: MemoryMatchHistoryRepository(),
        preferencesRepository: repository,
        initialRouteOverride: AppRoutes.home,
        diagnostics: diagnostics,
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('first run discloses reports before anything can be sent', (
    tester,
  ) async {
    final transport = FakeDiagnosticsTransport();
    await pumpApp(tester, diagnostics: fakeDiagnostics(transport));

    expect(find.byType(DiagnosticsConsentNotice), findsOneWidget);
    expect(find.text(strings.diagnosticsNoticeTitle), findsOneWidget);
    expect(
      transport.starts,
      0,
      reason: 'default-on must not be acted on before the disclosure',
    );
  });

  testWidgets('turning reports off at first run sends nothing, ever', (
    tester,
  ) async {
    final transport = FakeDiagnosticsTransport();
    final diagnostics = fakeDiagnostics(transport);
    final repository = await pumpApp(tester, diagnostics: diagnostics);

    await tester.tap(find.text(strings.diagnosticsNoticeTurnOff));
    await tester.pumpAndSettle();

    expect(find.byType(DiagnosticsConsentNotice), findsNothing);
    expect(repository.preferences.diagnosticsEnabled, isFalse);
    expect(repository.preferences.diagnosticsNoticeSeen, isTrue);
    expect(transport.starts, 0);
    expect(await diagnostics.sendUserReport(sampleMatchReport()), isFalse);
    expect(await diagnostics.captureError(StateError('boom'), null), isFalse);
    expect(transport.sent, isEmpty);
  });

  testWidgets('keeping reports on at first run starts diagnostics', (
    tester,
  ) async {
    final transport = FakeDiagnosticsTransport();
    final diagnostics = fakeDiagnostics(transport);
    final repository = await pumpApp(tester, diagnostics: diagnostics);

    await tester.tap(find.text(strings.diagnosticsNoticeKeepOn));
    await tester.pumpAndSettle();

    expect(repository.preferences.diagnosticsConsented, isTrue);
    expect(transport.isRunning, isTrue);
    expect(diagnostics.canSend, isTrue);
  });

  testWidgets('a build without a DSN shows no notice and starts nothing', (
    tester,
  ) async {
    final transport = FakeDiagnosticsTransport();
    await pumpApp(tester, diagnostics: fakeDiagnostics(transport, dsn: ''));

    expect(find.byType(DiagnosticsConsentNotice), findsNothing);
    expect(transport.starts, 0);
  });

  testWidgets('a returning player who already answered sees no notice', (
    tester,
  ) async {
    final transport = FakeDiagnosticsTransport();
    await pumpApp(
      tester,
      diagnostics: fakeDiagnostics(transport),
      preferences: GamePreferences.defaults().copyWith(
        diagnosticsNoticeSeen: true,
      ),
    );

    expect(find.byType(DiagnosticsConsentNotice), findsNothing);
    expect(transport.isRunning, isTrue);
  });

  testWidgets('the Settings opt-out stops diagnostics and blocks sends', (
    tester,
  ) async {
    final transport = FakeDiagnosticsTransport();
    final diagnostics = fakeDiagnostics(transport);
    final repository = await pumpApp(
      tester,
      diagnostics: diagnostics,
      preferences: GamePreferences.defaults().copyWith(
        diagnosticsNoticeSeen: true,
      ),
    );
    expect(transport.isRunning, isTrue);

    await tester.tap(find.byTooltip(strings.settings));
    await tester.pumpAndSettle();
    final list = find.byType(Scrollable).first;
    final section = find.text(strings.diagnosticsSectionTitle);
    await tester.scrollUntilVisible(section, 200, scrollable: list);
    await tester.tap(section);
    await tester.pumpAndSettle();
    final toggle = find.widgetWithText(
      SwitchListTile,
      strings.diagnosticsToggleTitle,
    );
    await tester.scrollUntilVisible(toggle, 200, scrollable: list);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(repository.preferences.diagnosticsEnabled, isFalse);
    expect(transport.isRunning, isFalse);
    expect(await diagnostics.sendUserReport(sampleMatchReport()), isFalse);
    expect(transport.sent, isEmpty);
  });
}
