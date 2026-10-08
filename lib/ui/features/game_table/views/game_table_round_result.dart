part of 'game_table_screen.dart';

// The between-rounds score overlay.

class _RoundResultOverlay extends StatelessWidget {
  const _RoundResultOverlay({
    required this.eliminationScore,
    required this.presentation,
    required this.onContinueNow,
    required this.onReturnToMenu,
    required this.onDismiss,
  });

  final int eliminationScore;
  final ClassicHareegRoundResultPresentation presentation;
  final VoidCallback? onContinueNow;
  final VoidCallback? onReturnToMenu;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final highContrast = CardContrastScope.enabledOf(context);
    final seats = PlayerSeat.values.toList();
    final compact = MediaQuery.sizeOf(context).height < 390;
    final winner = presentation.progress.matchWinner;
    return GestureDetector(
      key: const ValueKey('round-result-overlay'),
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: highContrast ? 0.72 : 0.50),
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 14 : 22,
                  vertical: compact ? 10 : 18,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compact ? 620 : 700,
                    maxHeight: MediaQuery.sizeOf(context).height - 24,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: highContrast
                          ? Colors.black.withValues(alpha: 0.98)
                          : LoungeTokens.coffeeCharcoal.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: highContrast
                            ? const Color(0xFFFFD400)
                            : LoungeTokens.goldAccent.withValues(alpha: 0.34),
                        width: highContrast ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.36),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 12 : 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RoundResultHeader(
                            headline: _roundHeadline(
                              presentation.result,
                              strings,
                            ),
                            detail: _roundDetail(presentation, strings),
                            compact: compact,
                          ),
                          SizedBox(height: compact ? 10 : 14),
                          Flexible(
                            child: SingleChildScrollView(
                              child: _RoundScoreBreakdown(
                                eliminationScore: eliminationScore,
                                seats: seats,
                                presentation: presentation,
                                compact: compact,
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 10 : 14),
                          if (winner == null)
                            _RoundAdvanceLine(
                              nextStarter: presentation.progress.nextStarter,
                              onContinueNow: onContinueNow,
                              compact: compact,
                            )
                          else
                            _MatchWinnerLine(
                              winner: winner,
                              onReturnToMenu: onReturnToMenu,
                              compact: compact,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundResultHeader extends StatelessWidget {
  const _RoundResultHeader({
    required this.headline,
    required this.detail,
    required this.compact,
  });

  final String headline;
  final String detail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final medallion = compact ? 36.0 : 44.0;
    return Row(
      children: [
        Container(
          width: medallion,
          height: medallion,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.3, -0.45),
              colors: [Color(0xFF3A2A1C), LoungeTokens.coffeeCharcoal],
            ),
            border: Border.all(color: LoungeTokens.goldAccent),
            boxShadow: [
              BoxShadow(
                color: LoungeTokens.goldAccent.withValues(alpha: 0.3),
                blurRadius: 12,
              ),
            ],
          ),
          child: Icon(
            Icons.menu_book_outlined,
            color: LoungeTokens.goldAccent,
            size: compact ? 18 : 22,
          ),
        ),
        SizedBox(width: compact ? 10 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.strings.roundScore,
                style: LoungeTokens.overline.copyWith(
                  color: LoungeTokens.goldAccent,
                  fontSize: compact ? 9.5 : 10.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                headline,
                style: LoungeTokens.display.copyWith(
                  fontSize: compact ? 19 : 24,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: LoungeTokens.bodyMuted.copyWith(
                  fontSize: compact ? 11.5 : 13,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundScoreBreakdown extends StatelessWidget {
  const _RoundScoreBreakdown({
    required this.eliminationScore,
    required this.seats,
    required this.presentation,
    required this.compact,
  });

  final int eliminationScore;
  final List<PlayerSeat> seats;
  final ClassicHareegRoundResultPresentation presentation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            LoungeTokens.feltSpotlight.withValues(alpha: 0.55),
            LoungeTokens.feltGreen.withValues(alpha: 0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < seats.length; index++) ...[
            _RoundScoreRow(
              eliminationScore: eliminationScore,
              seat: seats[index],
              before: presentation.previousScores[seats[index]] ?? 0,
              after: presentation.progress.scores[seats[index]] ?? 0,
              cards: presentation.result.remainingCardCounts[seats[index]],
              eliminated: !presentation.progress.activeSeats.contains(
                seats[index],
              ),
              compact: compact,
            ),
            if (index < seats.length - 1)
              Divider(
                height: 1,
                color: LoungeTokens.sandLine.withValues(alpha: 0.16),
              ),
          ],
        ],
      ),
    );
  }
}

class _RoundScoreRow extends StatelessWidget {
  const _RoundScoreRow({
    required this.eliminationScore,
    required this.seat,
    required this.before,
    required this.after,
    required this.cards,
    required this.eliminated,
    required this.compact,
  });

  final int eliminationScore;
  final PlayerSeat seat;
  final int before;
  final int after;
  final int? cards;
  final bool eliminated;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final delta = after - before;
    final deltaText = delta > 0 ? '+$delta' : '$delta';
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 7 : 10,
      ),
      child: Row(
        children: [
          // The seat on a lacquered medallion; its ring shows how close the
          // round has carried it to elimination (the totals sit at the end
          // of the row).
          Opacity(
            opacity: eliminated ? 0.5 : 1,
            child: Container(
              width: compact ? 28 : 34,
              height: compact ? 28 : 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.45),
                  colors: [Color(0xFF3A2A1C), LoungeTokens.coffeeCharcoal],
                ),
                border: Border.all(
                  width: 2,
                  color: Color.lerp(
                    LoungeTokens.sandLine.withValues(alpha: 0.4),
                    LoungeTokens.fiftyFlame,
                    eliminationScore <= 0
                        ? 0
                        : (after / eliminationScore).clamp(0.0, 1.0),
                  )!,
                ),
              ),
              child: Icon(
                seat == PlayerSeat.south
                    ? Icons.person_outline
                    : Icons.smart_toy_outlined,
                size: compact ? 14 : 17,
                color: LoungeTokens.sandLine,
              ),
            ),
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  strings.seatLabel(seat),
                  style: TextStyle(
                    color: eliminated
                        ? LoungeTokens.mutedText
                        : LoungeTokens.offWhiteText,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w800,
                    decoration: eliminated ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (cards != null)
                  _MiniResultTag(
                    label: strings.cardsCountTag(cards!),
                    compact: compact,
                  ),
                if (eliminated)
                  _MiniResultTag(label: strings.out, compact: compact),
              ],
            ),
          ),
          Text('$before', style: _scoreNumberStyle(compact)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color:
                    (delta <= 0
                            ? LoungeTokens.goldAccent
                            : LoungeTokens.fiftyFlame)
                        .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(LoungeTokens.radiusPill),
              ),
              child: Text(
                delta == 0 ? '+0' : deltaText,
                style: LoungeTokens.numericChip.copyWith(
                  color: delta <= 0
                      ? LoungeTokens.goldAccent
                      : LoungeTokens.fiftyFlame,
                  fontSize: compact ? 12 : 14,
                ),
              ),
            ),
          ),
          Text(
            '$after',
            style: _scoreNumberStyle(compact).copyWith(
              color: eliminated
                  ? LoungeTokens.mutedText
                  : LoungeTokens.goldAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniResultTag extends StatelessWidget {
  const _MiniResultTag({required this.label, required this.compact});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LoungeTokens.coffeeCharcoal.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: LoungeTokens.sandLine.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: LoungeTokens.offWhiteText.withValues(alpha: 0.72),
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _RoundAdvanceLine extends StatelessWidget {
  const _RoundAdvanceLine({
    required this.nextStarter,
    required this.onContinueNow,
    required this.compact,
  });

  final PlayerSeat nextStarter;
  final VoidCallback? onContinueNow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Row(
      children: [
        Expanded(
          child: Text(
            strings.nextRoundStartsWith(nextStarter),
            style: TextStyle(
              color: LoungeTokens.offWhiteText.withValues(alpha: 0.76),
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: onContinueNow,
          style: _roundResultActionStyle(compact),
          child: Text(strings.nextNow),
        ),
      ],
    );
  }
}

class _MatchWinnerLine extends StatelessWidget {
  const _MatchWinnerLine({
    required this.winner,
    required this.onReturnToMenu,
    required this.compact,
  });

  final PlayerSeat winner;
  final VoidCallback? onReturnToMenu;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Row(
      children: [
        Expanded(
          child: Text(
            strings.playerWinsMatch(winner),
            style: TextStyle(
              color: LoungeTokens.goldAccent,
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton(
          onPressed: onReturnToMenu,
          style: _roundResultActionStyle(compact),
          child: Text(strings.menu),
        ),
      ],
    );
  }
}

ButtonStyle _roundResultActionStyle(bool compact) {
  return TextButton.styleFrom(
    fixedSize: Size(compact ? 92 : 108, compact ? 34 : 40),
    minimumSize: Size.zero,
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );
}

TextStyle _scoreNumberStyle(bool compact) {
  return TextStyle(
    color: LoungeTokens.offWhiteText,
    fontSize: compact ? 14 : 17,
    fontWeight: FontWeight.w900,
  );
}

String _roundHeadline(RoundProgressResult result, AppStrings strings) {
  return switch (result.type) {
    RoundOutcomeType.normalFinish => strings.playerFinished(result.winner!),
    RoundOutcomeType.fiftyFinish => strings.playerHitFifty(result.winner!),
    RoundOutcomeType.draw => strings.roundDrawn,
  };
}

String _roundDetail(
  ClassicHareegRoundResultPresentation presentation,
  AppStrings strings,
) {
  final result = presentation.result;
  return switch (result.type) {
    RoundOutcomeType.normalFinish => strings.roundResultDetailNormal(),
    RoundOutcomeType.fiftyFinish => strings.roundResultDetailFifty(
      firstRoundException: result.firstRoundFiftyException,
    ),
    RoundOutcomeType.draw => strings.roundResultDetailDraw(),
  };
}
