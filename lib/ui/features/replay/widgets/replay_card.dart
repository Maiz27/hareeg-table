import 'package:flutter/material.dart';

import '../../../../domain/classic_hareeg/replay/replay_review_state.dart';
import '../../../../l10n/app_strings.dart';
import '../../../core/motion/motion_speed.dart';
import '../../../core/panels/lounge_medallion.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../replay_card_layout.dart';
import 'replay_transport.dart';

/// Which optional sections of the replay card are shown.
///
/// Decided from measured heights, in the contract's order: when the card is
/// out of room the analysis section goes first (after trimming the event line
/// to one line, so a switched-on section is not lost to a second line of
/// narration), then the event line loses its second line, then the event line
/// itself. The position, the scrubber and the transport row are never given
/// up.
@immutable
class ReplayCardSections {
  /// Creates a section decision.
  const ReplayCardSections({
    required this.narrationLines,
    required this.analysis,
  });

  /// Event lines shown: 0, 1 or 2.
  final int narrationLines;

  /// Whether the analysis section is shown.
  final bool analysis;
}

/// The replay card: where the reviewer is, what just happened, and how to
/// move — the replay's counterpart of the live table's coach card, and the
/// one place every transport control lives.
///
/// An L3 lounge card. [arrangement] decides the shape: stacked in the
/// top-start corner (and in portrait), or a band with the scrubber between the
/// two halves of the transport row. The analysis section opens inside the same
/// card, under the transport, so opening it never moves a control.
class ReplayCard extends StatelessWidget {
  /// Creates the card.
  const ReplayCard({
    required this.arrangement,
    required this.maxHeight,
    required this.review,
    required this.positionLabel,
    required this.narration,
    required this.onSeek,
    required this.analysisOpen,
    required this.analysis,
    super.key,
  });

  /// The shape the card takes.
  final ReplayCardArrangement arrangement;

  /// The tallest the card may grow.
  final double maxHeight;

  /// Current review position.
  final ReplayReviewState review;

  /// Localized "Round 3 · 214 of 1721" line.
  final String positionLabel;

  /// Localized description of the current frame.
  final String narration;

  /// Requests a jump to a frame index.
  final ValueChanged<int> onSeek;

  /// Whether the capsule's Analysis toggle is on.
  final bool analysisOpen;

  /// The analysis content, shown when open and when it fits.
  final Widget analysis;

  static TextStyle _overlineStyle() => LoungeTokens.overline.copyWith(
    color: LoungeTokens.goldAccent,
    letterSpacing: 0.8,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle _narrationStyle() =>
      LoungeTokens.body.copyWith(fontWeight: FontWeight.w600);

  /// The sections that fit in [maxHeight] for a card [width] wide.
  static ReplayCardSections sectionsFor({
    required ReplayCardArrangement arrangement,
    required double width,
    required double maxHeight,
    required String narration,
    required bool analysisOpen,
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: narration, style: _narrationStyle()),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 2,
    )..layout(maxWidth: width - ReplayCardMetrics.textPadding * 2);
    final lines = painter.computeLineMetrics().length.clamp(1, 2);
    painter.dispose();
    final lineHeight = ReplayCardMetrics.narrationLineHeight(textScaler);

    final fixed = arrangement == ReplayCardArrangement.band
        ? ReplayCardMetrics.padBottom * 2 +
              ReplayCardMetrics.bandRowHeight(textScaler)
        : ReplayCardMetrics.padTop +
              ReplayCardMetrics.overlineHeight(textScaler) +
              ReplayCardMetrics.lineGap +
              ReplayCardMetrics.sliderHeight +
              ReplayCardMetrics.tapTarget +
              ReplayCardMetrics.padBottom;
    final room = maxHeight - fixed;

    // An opened analysis section may take the event line's second line, but
    // never the whole event line: when even one line and the section do not
    // fit together, the section is what goes.
    if (analysisOpen) {
      for (var shown = lines; shown > 0; shown--) {
        if (room >= shown * lineHeight + ReplayCardMetrics.minAnalysisHeight) {
          return ReplayCardSections(narrationLines: shown, analysis: true);
        }
      }
    }
    for (var shown = lines; shown > 0; shown--) {
      if (room >= shown * lineHeight) {
        return ReplayCardSections(narrationLines: shown, analysis: false);
      }
    }
    return const ReplayCardSections(narrationLines: 0, analysis: false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final motion = MotionScope.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = strings.textDirection;

    return LayoutBuilder(
      builder: (context, constraints) {
        final sections = sectionsFor(
          arrangement: arrangement,
          width: constraints.maxWidth,
          maxHeight: maxHeight,
          narration: narration,
          analysisOpen: analysisOpen,
          textScaler: textScaler,
          textDirection: direction,
        );

        final position = Text(
          positionLabel,
          key: const ValueKey('replay-card-position'),
          // A collapsed event line is still read out, with the position.
          semanticsLabel: sections.narrationLines == 0
              ? '$positionLabel. $narration'
              : null,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: direction,
          style: _overlineStyle(),
        );
        final event = sections.narrationLines == 0
            ? null
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ReplayCardMetrics.textPadding,
                ),
                child: Text(
                  narration,
                  key: const ValueKey('replay-card-narration'),
                  maxLines: sections.narrationLines,
                  overflow: TextOverflow.ellipsis,
                  textDirection: direction,
                  style: _narrationStyle(),
                ),
              );
        final buttons = replayTransportButtons(
          strings: strings,
          review: review,
          onSeek: onSeek,
        );

        final children = <Widget>[
          if (arrangement == ReplayCardArrangement.band) ...[
            const SizedBox(height: ReplayCardMetrics.padBottom),
            _BandRow(
              buttons: buttons,
              position: position,
              scrubber: ReplayScrubber(review: review, onSeek: onSeek),
              height: ReplayCardMetrics.bandRowHeight(textScaler),
            ),
            ?event,
          ] else ...[
            const SizedBox(height: ReplayCardMetrics.padTop),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ReplayCardMetrics.textPadding,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: position,
              ),
            ),
            const SizedBox(height: ReplayCardMetrics.lineGap),
            ?event,
            SizedBox(
              height: ReplayCardMetrics.sliderHeight,
              child: ReplayScrubber(review: review, onSeek: onSeek),
            ),
            _StackedRow(buttons: buttons),
          ],
          if (sections.analysis)
            Flexible(
              child: _AnalysisSection(
                key: const ValueKey('replay-card-analysis'),
                child: analysis,
              ),
            ),
          const SizedBox(height: ReplayCardMetrics.padBottom),
        ];

        final column = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: DecoratedBox(
            decoration: loungeLitPanel(strength: 0.12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(LoungeTokens.radiusPanel),
              // Reduced motion opens the section in place.
              child: motion.reduced
                  ? column
                  : AnimatedSize(
                      duration: motion.scale(LoungeTokens.motionStandard),
                      curve: motion.curve(Curves.easeOutCubic),
                      alignment: Alignment.topCenter,
                      child: column,
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// The stacked arrangement's transport: one row, the gold step pair centred
/// between the round jumps and the ends.
class _StackedRow extends StatelessWidget {
  const _StackedRow({required this.buttons});

  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ReplayCardMetrics.rowPadding,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: buttons.sublist(0, 2),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: buttons.sublist(2, 4),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: buttons.sublist(4)),
          ],
        ),
      ),
    );
  }
}

/// The band arrangement's transport: one row, the position and the scrubber
/// between the backward and the forward halves, so each step sits beside the
/// scrubber it moves.
class _BandRow extends StatelessWidget {
  const _BandRow({
    required this.buttons,
    required this.position,
    required this.scrubber,
    required this.height,
  });

  final List<Widget> buttons;
  final Widget position;
  final Widget scrubber;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ReplayCardMetrics.rowPadding,
          ),
          child: Row(
            children: [
              ...buttons.sublist(0, 3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    position,
                    Expanded(child: scrubber),
                  ],
                ),
              ),
              ...buttons.sublist(3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The analysis section: a brass hairline, then the analysis content, which
/// scrolls inside whatever room the card has left.
class _AnalysisSection extends StatelessWidget {
  const _AnalysisSection({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ReplayCardMetrics.padBottom),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(
            horizontal: ReplayCardMetrics.textPadding,
          ),
          color: LoungeTokens.goldAccent.withValues(alpha: 0.3),
        ),
        Flexible(child: SingleChildScrollView(child: child)),
      ],
    );
  }
}
