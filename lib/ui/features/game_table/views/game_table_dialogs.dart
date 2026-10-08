part of 'game_table_screen.dart';

/// Modal questions the table asks the player mid-turn.
extension _TableDialogs on _GameTableScreenState {
  Future<bool?> _confirmGiveUpFifty() {
    final strings = context.strings;
    final body = _controller.setup.tableStrictness == TableStrictness.table
        ? strings.giveUpFiftyBodyTable
        : strings.giveUpFiftyBodyPenalty;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogStrings = dialogContext.strings;
        return AlertDialog(
          key: const ValueKey('give-up-fifty-dialog'),
          title: Text(dialogStrings.giveUpFiftyTitle),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogStrings.keepTrying),
            ),
            FilledButton(
              key: const ValueKey('give-up-fifty-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogStrings.giveUpFiftyConfirm),
            ),
          ],
        );
      },
    );
  }

  Future<TableInteractionJokerChoice?> _showJokerChoiceDialog(
    List<TableInteractionJokerChoice> choices,
  ) {
    final theme = CardThemeScope.of(context);
    return showDialog<TableInteractionJokerChoice>(
      context: context,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          key: const ValueKey('joker-choice-dialog'),
          title: Text(strings.chooseJokerIdentity),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final choice in choices)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: OutlinedButton(
                        key: ValueKey('joker-choice-${choice.identity.key}'),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(choice),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(strings.jokerAs(choice.identity)),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  for (final card in choice.cards)
                                    HareegCardView(
                                      theme: theme,
                                      card: card,
                                      jokerDisplay: JokerDisplay.assisted,
                                      size: const Size(30, 42),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
