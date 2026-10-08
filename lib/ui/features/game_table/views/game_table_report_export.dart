part of 'game_table_screen.dart';

/// Match-report export from the pause overlay (an in-progress match) and the
/// match-over overlay (a completed one), plus the automatic diagnostics
/// captures the table makes when a freeze backstop trips or a turn throws.
extension _MatchReportExport on _GameTableScreenState {
  static const _exporter = MatchReportExporter();

  MatchReportDiagnostics get _diagnostics =>
      widget.diagnostics ?? MatchReportDiagnostics.instance;

  LiveMatchReportSource get _liveMatchReports =>
      widget.liveMatchReports ?? LiveMatchReportSource.instance;

  /// Whether this table feeds diagnostics: real matches only. Practice has no
  /// recorder, and replay/sandbox tables are hypothetical lines, not the
  /// player's match.
  bool get _capturesDiagnostics =>
      widget.session.mode == TableMode.live && _recorder != null;

  /// Registers this table's in-flight report so global error handlers can
  /// attach it. The builder reads the live fields, so it stays current across
  /// rounds and rematches without re-registering.
  void _registerLiveMatchReport() {
    if (!_capturesDiagnostics) {
      return;
    }
    _liveMatchReports.attach(
      this,
      () => _buildActiveMatchReport(DateTime.now().toUtc()),
    );
  }

  ClassicHareegMatchReport _buildActiveMatchReport(DateTime generatedAt) {
    return ClassicHareegMatchReport.active(
      app: HareegAppMetadata.reportMetadata,
      platform: currentMatchReportPlatform(),
      generatedAt: generatedAt,
      snapshot: _controller.toPositionSnapshot(savedAt: generatedAt),
      diagnostics: _recorder?.diagnostics,
      transcript: _recorder?.transcript,
    );
  }

  /// Reports a freeze/liveness backstop trip with the in-flight report.
  void _captureBackstop(String trigger, {Map<String, String> tags = const {}}) {
    if (!_capturesDiagnostics) {
      return;
    }
    unawaited(
      _diagnostics.captureBackstop(
        trigger: trigger,
        report: _liveMatchReports.current(),
        tags: tags,
      ),
    );
  }

  /// Reports the stock-exhaustion livelock draw the engine forced, once per
  /// round.
  void _captureLivelockBackstopOnce() {
    final controller = _controller;
    if (!controller.isRoundOver ||
        !controller.roundEndedByLivelockBackstop ||
        identical(_livelockReportedFor, controller)) {
      return;
    }
    _livelockReportedFor = controller;
    _captureBackstop(
      'livelock_forced_draw',
      tags: {'round': '${controller.roundNumber}'},
    );
  }

  /// Reports an error the table caught to keep play going.
  void _captureError(
    Object error,
    StackTrace stackTrace, {
    required String trigger,
  }) {
    if (!_capturesDiagnostics) {
      return;
    }
    unawaited(_diagnostics.captureError(error, stackTrace, trigger: trigger));
  }

  Future<void> _exportActiveMatchReport() {
    return _exportMatchReport(_buildActiveMatchReport);
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

  MatchReportSendAvailability get _sendAvailability {
    final diagnostics = _diagnostics;
    if (!diagnostics.isAvailable) {
      return MatchReportSendAvailability.unavailable;
    }
    return diagnostics.canSend
        ? MatchReportSendAvailability.available
        : MatchReportSendAvailability.disabled;
  }

  /// Confirms the export, builds the report via [buildReport] and sends it to
  /// the developer, or hands it to the share sheet or the clipboard, as the
  /// player chose.
  Future<void> _exportMatchReport(
    ClassicHareegMatchReport Function(DateTime generatedAt) buildReport,
  ) async {
    final choice = await showMatchReportConfirmation(
      context,
      highContrast: widget.preferences.highContrastCards,
      send: _sendAvailability,
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
      case MatchReportExportChoice.send:
        await _sendOrOfferShare(report);
      case MatchReportExportChoice.share:
        await _shareOrOfferCopy(report);
      case MatchReportExportChoice.copy:
        await _copyMatchReport(report);
    }
  }

  /// Sends [report] to diagnostics; on failure offers the share fallback.
  Future<void> _sendOrOfferShare(ClassicHareegMatchReport report) async {
    final strings = context.strings;
    final sent = await _diagnostics.sendUserReport(report);
    if (!mounted) {
      return;
    }
    if (sent) {
      showLoungeToast(context, message: strings.matchReportSent);
      return;
    }
    showLoungeToast(
      context,
      message: strings.matchReportSendFailed,
      icon: Icons.error_outline,
      isError: true,
      actionLabel: strings.shareReport,
      onActionPressed: () {
        unawaited(_shareOrOfferCopy(report));
      },
    );
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
