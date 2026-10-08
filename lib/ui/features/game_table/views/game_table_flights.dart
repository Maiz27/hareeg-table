part of 'game_table_screen.dart';

// Single-card flights and the opening-deal overlay.

HareegCard _backSeed(int index) {
  return HareegCard.standard(
    rank: CardRank.ace,
    suit: CardSuit.spades,
    deckIndex: 700 + index,
  );
}

class _CardFlight {
  const _CardFlight({
    required this.serial,
    required this.card,
    required this.begin,
    required this.end,
    required this.duration,
    this.faceDown = false,
    this.beginHandSlot,
    this.endHandSlot,
    this.endMeldSlot,
  });

  final int serial;
  final HareegCard card;
  final Alignment begin;
  final Alignment end;
  final Duration duration;
  final bool faceDown;
  final SeatHandFlightSlot? beginHandSlot;
  final SeatHandFlightSlot? endHandSlot;
  final TableMeldFlightSlot? endMeldSlot;
}

class _CardFlightOverlay extends StatelessWidget {
  const _CardFlightOverlay({required this.flight, required this.theme});

  final _CardFlight flight;
  final HareegCardTheme theme;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final cardSize = constraints.maxHeight <= 390
              ? const Size(44, 62)
              : const Size(58, 82);
          final begin = resolveFlightAnchor(
            flight.begin,
            size,
            cardSize,
            handSlot: flight.beginHandSlot,
          );
          final end = resolveFlightAnchor(
            flight.end,
            size,
            cardSize,
            handSlot: flight.endHandSlot,
            meldSlot: flight.endMeldSlot,
          );
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: flight.duration,
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              final lifted = math.sin(value * math.pi) * 24;
              final offset = Offset.lerp(begin, end, value)!;
              return Stack(
                children: [
                  Positioned(
                    left: offset.dx,
                    top: offset.dy - lifted,
                    child: Transform.rotate(
                      angle: (1 - value) * -0.10,
                      child: Opacity(
                        opacity: (1 - (value * 0.18))
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        child: child,
                      ),
                    ),
                  ),
                ],
              );
            },
            child: Material(
              color: Colors.transparent,
              elevation: 14,
              borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
              child: HareegCardView(
                theme: theme,
                card: flight.card,
                size: cardSize,
                faceDown: flight.faceDown,
                visualState: CardVisualState.selected,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OpeningDealOverlay extends StatelessWidget {
  const _OpeningDealOverlay({
    required this.sequence,
    required this.progress,
    required this.theme,
    required this.flightDuration,
    required this.stagger,
  });

  final DealSequence sequence;
  final double progress;
  final HareegCardTheme theme;
  final Duration flightDuration;
  final Duration stagger;

  @override
  Widget build(BuildContext context) {
    final curve = MotionScope.of(context).curve(Curves.easeOutCubic);
    final elapsed = sequence.elapsedAt(
      progress: progress,
      flightDuration: flightDuration,
      stagger: stagger,
    );
    return IgnorePointer(
      key: const ValueKey('opening-deal-overlay'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final cardSize = constraints.maxHeight <= 390
              ? const Size(44, 62)
              : const Size(58, 82);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final step in sequence.steps)
                if (dealStepProgress(
                      elapsed: elapsed,
                      step: step,
                      flightDuration: flightDuration,
                      stagger: stagger,
                    )
                    case final localProgress?)
                  _OpeningDealFlightCard(
                    key: ValueKey('opening-deal-flight-${step.orderIndex}'),
                    step: step,
                    progress: curve.transform(localProgress),
                    theme: theme,
                    viewportSize: size,
                    cardSize: cardSize,
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _OpeningDealFlightCard extends StatelessWidget {
  const _OpeningDealFlightCard({
    super.key,
    required this.step,
    required this.progress,
    required this.theme,
    required this.viewportSize,
    required this.cardSize,
  });

  final DealStep step;
  final double progress;
  final HareegCardTheme theme;
  final Size viewportSize;
  final Size cardSize;

  @override
  Widget build(BuildContext context) {
    final begin = resolveFlightAnchor(
      TableFlightAnchors.stock,
      viewportSize,
      cardSize,
    );
    final end = resolveFlightAnchor(
      TableFlightAnchors.seatLane(step.seat),
      viewportSize,
      cardSize,
      handSlot: step.endHandSlot,
    );
    final value = progress.clamp(0.0, 1.0).toDouble();
    final dx = end.dx - begin.dx;
    final dy = end.dy - begin.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    // Throw height tracks distance so cross-table deals look airborne and
    // self-deals only get a small hop. Clamped so very long flights stay
    // grounded enough to read.
    final arcHeight = (distance * 0.16).clamp(28.0, 84.0).toDouble();
    final lifted = math.sin(value * math.pi) * arcHeight;
    final offset = Offset.lerp(begin, end, value)!;
    // Landing settle: a tiny scale punch in the last sliver of flight so
    // cards feel like they actually meet the felt.
    final double landingScale;
    if (value < 0.86) {
      landingScale = 1.0;
    } else if (value < 0.93) {
      landingScale = 1.0 + (value - 0.86) / 0.07 * 0.045;
    } else {
      landingScale = 1.045 - (value - 0.93) / 0.07 * 0.045;
    }
    // Shadow tapers as the card settles, so it collapses onto the table at
    // touchdown. Drawn as a [BoxShadow] rather than `Material(elevation: ...)`
    // — Material's per-frame elevation recompute multiplied across ~57
    // simultaneous flight cards was a measurable hit on lower-end devices.
    final shadowBlur = 10 + (1 - value) * 8;
    final shadowOffset = Offset(0, 4 + (1 - value) * 4);
    return Positioned(
      left: offset.dx,
      top: offset.dy - lifted,
      child: Transform.rotate(
        angle: (1 - value) * -0.10,
        child: Transform.scale(
          scale: landingScale,
          child: Opacity(
            opacity: (1 - (value * 0.18)).clamp(0.0, 1.0).toDouble(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(LoungeTokens.radiusCard),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x66000000),
                    blurRadius: shadowBlur,
                    offset: shadowOffset,
                  ),
                ],
              ),
              child: HareegCardView(
                theme: theme,
                card: step.card,
                size: cardSize,
                faceDown: step.faceDown,
                visualState: CardVisualState.selected,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Turns presentation flight plans into concrete card flights: which card
/// flies, from which anchor or hand slot, to which.
extension _TableFlightPlanning on _GameTableScreenState {
  _CardFlight? _flightForPlan(
    TableActionFlightPlan? plan, {
    required Duration duration,
  }) {
    final serial = _flightSerial + 1;
    final realization = TableCardFlightPlanner.realize(
      presentation: plan,
      stockBack: _backSeed(serial),
      topDiscard: _controller.topDiscard,
      pendingDiscard: _controller.pendingDiscard,
      handCardFor: _cardInHand,
      southHandCardSlotFor: _southHandCardSlot,
      appendHandSlotFor: _appendHandSlotForSeat,
      lastHandSlotFor: _lastHandSlotForSeat,
    );
    final card = realization.card;
    final presentation = realization.presentation;
    if (!realization.canRender || card == null || presentation == null) {
      return null;
    }
    _flightSerial = serial;

    // Carry the target lane's meld card counts so a cover/replacement flight
    // lands on the meld it targets rather than the lane centre (the same
    // arrangement the lane renders from).
    final endMeldSlot = realization.endMeldSlot;
    return _CardFlight(
      serial: serial,
      card: card,
      faceDown: realization.faceDown,
      begin: _flightBegin(presentation),
      end: _flightEnd(presentation),
      duration: duration,
      beginHandSlot: realization.beginHandSlot,
      endHandSlot: realization.endHandSlot,
      endMeldSlot: endMeldSlot == null
          ? null
          : TableMeldFlightSlot(
              seat: endMeldSlot.seat,
              index: endMeldSlot.index,
              laneMeldCardCounts: [
                for (final meld in _controller.tableMeldsFor(endMeldSlot.seat))
                  meld.cards.length,
              ],
            ),
    );
  }

  /// Animates a `play-meld` action via [MeldFlightController]. The
  /// orchestrator owns the per-set decomposition and inter-set sequencing;
  /// the screen just supplies durations and the sound hook.
  Future<bool> _playMeldFlight({
    required PlayerSeat seat,
    required String actionId,
    TableSoundEvent? sound,
  }) {
    return _meldFlight.playMeld(
      seat: seat,
      actionId: actionId,
      flightDuration: _meldFlightDuration,
      interSetDelay: _meldInterSetDelay,
      onSoundPlay: () =>
          unawaited(_playSound(sound ?? TableSoundEvent.meldPlace)),
    );
  }

  Duration get _meldInterSetDelay => widget.preferences.fastCpuTurns
      ? _scaledDelay(TableMotion.meldInterSetDelayFast)
      : _scaledDelay(TableMotion.meldInterSetDelayNormal);

  Alignment _flightBegin(TableActionFlightPlan plan) {
    return switch (plan.source) {
      TableActionFlightSource.stockBack => TableFlightAnchors.stock,
      TableActionFlightSource.topDiscard => TableFlightAnchors.discard,
      TableActionFlightSource.pendingDiscard ||
      TableActionFlightSource.handCard => TableFlightAnchors.seatHand(
        plan.seat,
      ),
    };
  }

  Alignment _flightEnd(TableActionFlightPlan plan) {
    return switch (plan.destination) {
      TableActionFlightDestination.seatHand => TableFlightAnchors.seatHand(
        plan.seat,
      ),
      TableActionFlightDestination.discardPile => TableFlightAnchors.discard,
      TableActionFlightDestination.tableMeld => TableFlightAnchors.seatHand(
        plan.seat,
      ),
    };
  }

  SeatHandFlightSlot _southHandAppendSlot() {
    final count = _controller.handFor(PlayerSeat.south).length + 1;
    return SeatHandFlightSlot(
      seat: PlayerSeat.south,
      index: count - 1,
      count: count,
    );
  }

  SeatHandFlightSlot? _southHandCardSlot(String cardId) {
    final cards = _orderedSouthHand();
    final index = cards.indexWhere((card) => card.id == cardId);
    if (index == -1) {
      return null;
    }
    return SeatHandFlightSlot(
      seat: PlayerSeat.south,
      index: index,
      count: cards.length,
    );
  }

  SeatHandFlightSlot _appendHandSlotForSeat(PlayerSeat seat) {
    if (seat == PlayerSeat.south) {
      return _southHandAppendSlot();
    }
    final count = _controller.cardCountFor(seat) + 1;
    return SeatHandFlightSlot(seat: seat, index: count - 1, count: count);
  }

  SeatHandFlightSlot? _lastHandSlotForSeat(PlayerSeat seat) {
    if (seat == PlayerSeat.south) {
      final cards = _orderedSouthHand();
      if (cards.isEmpty) return null;
      return SeatHandFlightSlot(
        seat: PlayerSeat.south,
        index: cards.length - 1,
        count: cards.length,
      );
    }
    final count = _controller.cardCountFor(seat);
    if (count <= 0) return null;
    return SeatHandFlightSlot(seat: seat, index: count - 1, count: count);
  }

  HareegCard? _cardInHand(PlayerSeat seat, String id) {
    for (final card in _controller.handFor(seat)) {
      if (card.id == id) return card;
    }
    return null;
  }
}
