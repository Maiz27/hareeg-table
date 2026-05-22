import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../domain/classic_hareeg/models/playing_card.dart';
import '../../../../domain/classic_hareeg/models/player_seat.dart';
import '../../../core/audio/table_audio.dart';
import '../../../core/motion/motion_speed.dart';

/// One card landing in a seat's hand during a flight.
///
/// Shared between [DealChoreography] and the per-turn card-flight overlay; the
/// slot describes "the i-th card in a seat's hand of size count," which both
/// the deal and the turn flight need to resolve a screen position.
@immutable
class SeatHandFlightSlot {
  /// Creates a hand-slot reference.
  const SeatHandFlightSlot({
    required this.seat,
    required this.index,
    required this.count,
  });

  /// Owning seat.
  final PlayerSeat seat;

  /// Zero-based slot inside the seat's hand strip.
  final int index;

  /// Total slot count visible in that seat at the moment of resolution.
  final int count;
}

/// One step in the opening-deal animation: which card lands where.
@immutable
class DealStep {
  /// Creates a deal step.
  const DealStep({
    required this.orderIndex,
    required this.seat,
    required this.card,
    required this.faceDown,
    required this.endHandSlot,
  });

  /// Step index inside the deal sequence; used to compute stagger offsets.
  final int orderIndex;

  /// Seat receiving the card.
  final PlayerSeat seat;

  /// The card flown in (used for the south reveal; other seats render
  /// face-down stand-ins).
  final HareegCard card;

  /// Whether the card lands face-down on its seat strip.
  final bool faceDown;

  /// Resolved landing slot inside the seat's hand.
  final SeatHandFlightSlot endHandSlot;
}

/// All the data needed to animate (and inspect mid-flight) one opening deal.
///
/// This is pure data — no controller, no audio. The [DealChoreography] takes
/// a sequence + timing + audio gateway and drives the animation.
@immutable
class DealSequence {
  /// Creates a deal sequence.
  const DealSequence({
    required this.steps,
    required this.finalStockCount,
    required this.orderedSouthCards,
  });

  /// Ordered deal steps, first step at index 0.
  final List<DealStep> steps;

  /// Stock count once the deal has fully landed.
  final int finalStockCount;

  /// South hand in its final display order; used to reveal the right card
  /// during each south-bound flight.
  final List<HareegCard> orderedSouthCards;

  /// Total number of cards dealt.
  int get totalDealt => steps.length;

  /// Total animation duration given a per-card flight time and stagger.
  Duration totalDuration({
    required Duration flightDuration,
    required Duration stagger,
  }) {
    if (steps.isEmpty) {
      return Duration.zero;
    }
    return _durationTimes(stagger, steps.length - 1) + flightDuration;
  }

  /// Maps a `[0, 1]` controller progress to elapsed time within the sequence.
  Duration elapsedAt({
    required double progress,
    required Duration flightDuration,
    required Duration stagger,
  }) {
    final duration = totalDuration(
      flightDuration: flightDuration,
      stagger: stagger,
    );
    return Duration(
      microseconds: (duration.inMicroseconds * progress.clamp(0.0, 1.0))
          .round(),
    );
  }

  /// Per-seat card counts visible at [elapsed].
  Map<PlayerSeat, int> cardCountsAt({
    required Duration elapsed,
    required Duration flightDuration,
    required Duration stagger,
    required Map<PlayerSeat, int> fallbackCounts,
  }) {
    final duration = totalDuration(
      flightDuration: flightDuration,
      stagger: stagger,
    );
    if (elapsed >= duration) {
      return fallbackCounts;
    }
    final counts = {for (final seat in PlayerSeat.values) seat: 0};
    for (final step in steps) {
      final landedAt =
          _durationTimes(stagger, step.orderIndex) + flightDuration;
      if (elapsed >= landedAt) {
        counts[step.seat] = (counts[step.seat] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Stock count visible at [elapsed]: full stock minus steps that have begun.
  int stockCountAt({required Duration elapsed, required Duration stagger}) {
    var started = 0;
    for (final step in steps) {
      if (elapsed > _durationTimes(stagger, step.orderIndex)) {
        started += 1;
      }
    }
    return finalStockCount + totalDealt - started;
  }
}

/// Snapshot of what the table looks like at one point of the deal.
@immutable
class DealFrame {
  /// Creates a deal frame.
  const DealFrame({
    required this.stockCount,
    required this.cardCounts,
    required this.southCards,
  });

  /// Stock count to draw under the deck stamp.
  final int stockCount;

  /// Per-seat card counts.
  final Map<PlayerSeat, int> cardCounts;

  /// South cards revealed so far, in display order.
  final List<HareegCard> southCards;
}

/// Local progress of one [DealStep] given the elapsed sequence time, or
/// `null` if the step hasn't started or has already landed.
double? dealStepProgress({
  required Duration elapsed,
  required DealStep step,
  required Duration flightDuration,
  required Duration stagger,
}) {
  final start = _durationTimes(stagger, step.orderIndex);
  // Handle the zero-duration case first — otherwise the window guard below
  // (start == end) makes `elapsed >= end` always true and the branch never
  // runs. Instant flights snap to a normalized 1.0 once the step starts.
  if (flightDuration == Duration.zero) {
    return elapsed >= start ? 1 : null;
  }
  final end = start + flightDuration;
  if (elapsed < start || elapsed >= end) {
    return null;
  }
  return (elapsed - start).inMicroseconds / flightDuration.inMicroseconds;
}

Duration _durationTimes(Duration duration, int factor) {
  return Duration(microseconds: duration.inMicroseconds * factor);
}

/// Default per-step stagger for the opening deal.
const Duration kDealStagger = Duration(milliseconds: 48);

/// Owns the deal animation's controller, timing, and audio firing.
///
/// The visual stagger and the audio stagger are *one value* on this module —
/// callers can't get one without the other, so they cannot drift. The screen
/// instantiates one [DealChoreography] per round, listens to [progress] for
/// per-frame rebuilds, and awaits [play] to know when the deal finishes.
///
/// The deletion test: if you remove this module, the screen would have to
/// reinvent the visual+audio sync invariant inline — that's a concentration
/// of real complexity here, not a pass-through.
class DealChoreography {
  /// Creates a choreography for one opening deal.
  DealChoreography({
    required TickerProvider vsync,
    required this.audio,
    required MotionSettings motion,
    required this.sequence,
    Duration stagger = kDealStagger,
    Duration flight = const Duration(milliseconds: 220),
  }) : flightDuration = motion.scale(flight),
       stagger = motion.scale(stagger) {
    totalDuration = sequence.totalDuration(
      flightDuration: flightDuration,
      stagger: this.stagger,
    );
    _controller = AnimationController(vsync: vsync, duration: totalDuration);
  }

  /// Audio gateway used to fire shuffle + per-card sounds in time with the
  /// visual stagger.
  final TableAudio audio;

  /// Data for this deal.
  final DealSequence sequence;

  /// Per-card flight duration after motion scaling.
  final Duration flightDuration;

  /// Per-card stagger after motion scaling.
  final Duration stagger;

  /// Total deal duration after motion scaling.
  late final Duration totalDuration;

  late final AnimationController _controller;
  bool _disposed = false;

  /// `[0, 1]` progress across the whole deal. Add a listener for per-frame
  /// rebuilds; current value is suitable for hand-off to the deal overlay.
  Animation<double> get progress => _controller;

  /// Plays the deal: forward animation + interleaved sound effects.
  ///
  /// Completes when the animation finishes or when [dispose] is called.
  Future<void> play() async {
    if (sequence.steps.isEmpty) {
      return;
    }
    unawaited(_playAudio());
    try {
      await _controller.forward();
    } on TickerCanceled {
      // Disposed mid-flight; nothing more to do.
    }
  }

  Future<void> _playAudio() async {
    await audio.play(TableSoundEvent.openingShuffle);
    for (var i = 0; i < sequence.steps.length; i += 1) {
      if (_disposed) return;
      unawaited(audio.play(TableSoundEvent.dealCard));
      if (i < sequence.steps.length - 1 && stagger > Duration.zero) {
        await Future<void>.delayed(stagger);
      }
    }
  }

  /// Resolves the current frame state — what to render for stock, per-seat
  /// counts, and revealed south cards.
  DealFrame frameAt({
    required Map<PlayerSeat, int> fallbackCounts,
    required List<HareegCard> fallbackSouthCards,
  }) {
    final elapsed = sequence.elapsedAt(
      progress: _controller.value,
      flightDuration: flightDuration,
      stagger: stagger,
    );
    final cardCounts = sequence.cardCountsAt(
      elapsed: elapsed,
      flightDuration: flightDuration,
      stagger: stagger,
      fallbackCounts: fallbackCounts,
    );
    final southCount = cardCounts[PlayerSeat.south] ?? 0;
    final orderedSouth = sequence.orderedSouthCards.isEmpty
        ? fallbackSouthCards
        : sequence.orderedSouthCards;
    return DealFrame(
      stockCount: sequence.stockCountAt(elapsed: elapsed, stagger: stagger),
      cardCounts: cardCounts,
      southCards: orderedSouth.take(southCount).toList(growable: false),
    );
  }

  /// Releases the controller. Safe to call after the deal completes or while
  /// it's still running (mid-flight disposal is treated as cancellation).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.dispose();
  }
}
