import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_orientation.dart';
import 'app/hareeg_table_app.dart';
import 'ui/features/match_reports/match_report_diagnostics.dart';

/// Starts the Hareeg Table Flutter application.
///
/// Runs inside [runZonedGuarded] so an error that escapes every other handler
/// still reaches diagnostics (with the in-flight match report attached). The
/// gateway is a no-op until the app shell applies the player's consent, and
/// stays one forever in a build without a `SENTRY_DSN` define. Framework and
/// platform-dispatcher errors are captured by the SDK's own handlers once it
/// starts.
void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await AppOrientation.usePortrait();

      runApp(const HareegTableApp());
    },
    (error, stackTrace) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stackTrace),
      );
      unawaited(
        MatchReportDiagnostics.instance.captureError(error, stackTrace),
      );
    },
  );
}
