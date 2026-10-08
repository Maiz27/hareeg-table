part of 'game_table_screen.dart';

/// Match-report export from the pause overlay (an in-progress match) and the
/// match-over overlay (a completed one).
extension _MatchReportExport on _GameTableScreenState {
  static const _exporter = MatchReportExporter();

  Future<void> _exportActiveMatchReport() {
    return _exportMatchReport(
      (generatedAt) => ClassicHareegMatchReport.active(
        app: HareegAppMetadata.reportMetadata,
        platform: currentMatchReportPlatform(),
        generatedAt: generatedAt,
        snapshot: _controller.toPositionSnapshot(savedAt: generatedAt),
        diagnostics: _recorder?.diagnostics,
        transcript: _recorder?.transcript,
      ),
    );
  }

  Future<void> _exportCompletedMatchReport(
    ClassicHareegRoundResultPresentation presentation,
  ) {
    return _exportMatchReport(
      (generatedAt) => ClassicHareegMatchReport.completed(
        app: HareegAppMetadata.reportMetadata,
        platform: currentMatchReportPlatform(),
        generatedAt: generatedAt,
        snapshot: _controller.toSnapshot(savedAt: generatedAt),
        roundResult: presentation.result,
        matchProgress: presentation.progress,
        diagnostics: _recorder?.diagnostics,
        transcript: _recorder?.transcript,
      ),
    );
  }

  /// Confirms the export, builds the report via [buildReport] and hands it to
  /// the share sheet or the clipboard, as the player chose.
  Future<void> _exportMatchReport(
    ClassicHareegMatchReport Function(DateTime generatedAt) buildReport,
  ) async {
    final choice = await showMatchReportConfirmation(
      context,
      highContrast: widget.preferences.highContrastCards,
    );
    if (!mounted || choice == null) {
      return;
    }
    final ClassicHareegMatchReport report;
    try {
      report = buildReport(DateTime.now().toUtc());
    } on Object catch (error, stackTrace) {
      debugPrint('[hareeg:reports] Failed to generate match report: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        showLoungeToast(
          context,
          message: context.strings.matchReportGenerationFailed,
          icon: Icons.error_outline,
          isError: true,
        );
      }
      return;
    }
    switch (choice) {
      case MatchReportExportChoice.share:
        await _shareOrOfferCopy(report);
      case MatchReportExportChoice.copy:
        await _copyMatchReport(report);
    }
  }

  Future<void> _shareOrOfferCopy(ClassicHareegMatchReport report) async {
    final strings = context.strings;
    final attempt = await _exporter.share(report);
    if (!mounted) {
      return;
    }
    if (attempt.shared) {
      showLoungeToast(
        context,
        message: strings.matchReportShareReady,
        actionLabel: strings.copyReport,
        onActionPressed: () {
          unawaited(_copyMatchReport(report));
        },
      );
      return;
    }
    showLoungeToast(
      context,
      message: strings.matchReportCopyFallback,
      icon: Icons.error_outline,
      isError: true,
      actionLabel: strings.copyReport,
      onActionPressed: () {
        unawaited(_copyMatchReport(report));
      },
    );
  }

  Future<void> _copyMatchReport(ClassicHareegMatchReport report) async {
    final strings = context.strings;
    try {
      await _exporter.copy(report);
      if (!mounted) {
        return;
      }
      showLoungeToast(context, message: strings.matchReportCopied);
    } on Object {
      if (!mounted) {
        return;
      }
      showLoungeToast(
        context,
        message: strings.matchReportCopyFailed,
        icon: Icons.error_outline,
        isError: true,
      );
    }
  }
}
