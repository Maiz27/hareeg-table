part of 'game_table_screen.dart';

// The long-press card inspection overlay and its copy.

class _CardInspectOverlay extends StatelessWidget {
  const _CardInspectOverlay({
    required this.card,
    required this.theme,
    required this.strictness,
    required this.onClose,
  });

  final HareegCard card;
  final HareegCardTheme theme;
  final TableStrictness strictness;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final highContrast = CardContrastScope.enabledOf(context);
    final revealsRepresented = strictness.longPressRevealsRepresented;
    final title = _inspectTitle(
      card,
      strings,
      revealsRepresented: revealsRepresented,
    );
    final body = _inspectBody(card, strictness, strings: strings);
    final inspectJokerDisplay = revealsRepresented
        ? JokerDisplay.assisted
        : JokerDisplay.unassigned;
    return Positioned.fill(
      key: const ValueKey('card-inspect-overlay'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Material(
          color: Colors.black.withValues(alpha: highContrast ? 0.68 : 0.48),
          child: SafeArea(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < 560 || constraints.maxHeight < 390;
                  final cardSize = compact
                      ? const Size(88, 124)
                      : const Size(128, 180);
                  final details = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: compact
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        key: const ValueKey('card-inspect-title'),
                        textAlign: compact ? TextAlign.center : TextAlign.start,
                        style: TextStyle(
                          color: LoungeTokens.offWhiteText,
                          fontSize: compact ? 17 : 20,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      if (body != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          body,
                          key: const ValueKey('card-inspect-body'),
                          textAlign: compact
                              ? TextAlign.center
                              : TextAlign.start,
                          style: TextStyle(
                            color: LoungeTokens.offWhiteText.withValues(
                              alpha: 0.82,
                            ),
                            fontSize: compact ? 12 : 13,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  );

                  final content = compact
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HareegCardView(
                              theme: theme,
                              card: card,
                              size: cardSize,
                              jokerDisplay: inspectJokerDisplay,
                            ),
                            const SizedBox(height: 12),
                            details,
                          ],
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HareegCardView(
                              theme: theme,
                              card: card,
                              size: cardSize,
                              jokerDisplay: inspectJokerDisplay,
                            ),
                            const SizedBox(width: 18),
                            Flexible(child: details),
                          ],
                        );

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: math.max(
                          0.0,
                          math.min(constraints.maxWidth - 28, 520.0),
                        ),
                        maxHeight: math.max(0.0, constraints.maxHeight - 28),
                      ),
                      margin: const EdgeInsets.all(14),
                      padding: EdgeInsets.fromLTRB(
                        compact ? 14 : 18,
                        compact ? 14 : 18,
                        compact ? 14 : 18,
                        compact ? 16 : 18,
                      ),
                      decoration: BoxDecoration(
                        color: highContrast
                            ? Colors.black.withValues(alpha: 0.98)
                            : LoungeTokens.coffeeCharcoal.withValues(
                                alpha: 0.96,
                              ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: highContrast
                              ? const Color(0xFFFFD400)
                              : LoungeTokens.goldAccent.withValues(alpha: 0.36),
                          width: highContrast ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.34),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SingleChildScrollView(
                            child: Padding(
                              padding: EdgeInsets.only(right: compact ? 0 : 28),
                              child: content,
                            ),
                          ),
                          Positioned(
                            top: -8,
                            right: -8,
                            child: Tooltip(
                              message: strings.close,
                              child: IconButton(
                                key: const ValueKey('card-inspect-close'),
                                onPressed: onClose,
                                icon: const Icon(Icons.close_rounded),
                                color: LoungeTokens.offWhiteText,
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _inspectTitle(
  HareegCard card,
  AppStrings strings, {
  required bool revealsRepresented,
}) {
  final identity = card.identity;
  if (identity != null) {
    return strings.cardName(identity);
  }

  if (!revealsRepresented) {
    return strings.joker;
  }

  final represented = card.representedIdentity;
  if (represented != null) {
    return strings.jokerAs(represented);
  }

  return strings.joker;
}

String? _inspectBody(
  HareegCard card,
  TableStrictness strictness, {
  required AppStrings strings,
}) {
  if (card.isJoker && !strictness.longPressRevealsRepresented) {
    return null;
  }

  final isCoaching = strictness.inspectVerbosity == InspectVerbosity.coaching;
  final identity = card.effectiveIdentity;
  if (identity == null) {
    return isCoaching ? strings.unassignedJokerGuided : strings.unassignedJoker;
  }

  final value = identity.rank.value;
  if (card.isJoker) {
    return isCoaching
        ? strings.representedJokerGuided(strings.cardName(identity))
        : '${strings.representedJoker(strings.cardName(identity))} '
              '${strings.cardValue(value)}';
  }

  if (isCoaching) {
    return strings.cardValueGuided(value);
  }
  return strings.cardValueWithSuit(value, strings.suitWord(identity.suit));
}
