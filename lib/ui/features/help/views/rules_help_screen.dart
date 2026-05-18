import 'package:flutter/material.dart';

import '../../../../app/app_orientation.dart';
import '../../../../l10n/app_strings.dart';

/// Player-facing Classic Hareeg help.
class RulesHelpScreen extends StatefulWidget {
  /// Creates the help screen.
  const RulesHelpScreen({super.key});

  @override
  State<RulesHelpScreen> createState() => _RulesHelpScreenState();
}

class _RulesHelpScreenState extends State<RulesHelpScreen> {
  @override
  void initState() {
    super.initState();
    AppOrientation.usePortrait();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.helpTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            _HelpSection(
              title: 'Setup',
              body:
                  'Classic Hareeg uses four seats, one human player, three CPU players, and anti-clockwise turns. The app defaults to two decks and two jokers so there are enough cards for a four-seat deal. The starter receives 15 cards and skips the first draw.',
            ),
            _HelpSection(
              title: 'Turn flow',
              body:
                  'The starter begins in action phase. Other turns begin by drawing from stock or taking the previous discard. A taken discard becomes pending: it must be used in a valid play that turn or returned before drawing from stock.',
            ),
            _HelpSection(
              title: 'Opening and benchmark',
              body:
                  'The default opening requirement is 51, with 75 available as a setup option. A player opens by placing one or more new melds whose combined value reaches the current requirement. Covers do not count toward opening. The first opener owns the benchmark and can raise it until a second player opens, then the benchmark locks.',
            ),
            _HelpSection(
              title: 'Covers',
              body:
                  'A cover is a card that can extend an existing table meld right now. Sequence covers are direct neighbors only; after a card is placed, chained covers may become legal. Covers cannot normally be discarded by opened or unopened players, but a cover may be the final discard when finishing.',
            ),
            _HelpSection(
              title: 'Jokers',
              body:
                  'Jokers represent a chosen card identity when placed in a meld or cover. If several identities are legal, the human player must choose; CPU players choose deterministically. Opened players may replace a table joker with the represented card and take the joker. Normal joker discard is always blocked, but a joker may be the final discard.',
            ),
            _HelpSection(
              title: 'Fifty / Khamsin',
              body:
                  'After a discard, only the immediate next player can claim Fifty, and only before the timer expires. The discarded card must be part of a legal finish, including hand melds, table covers, or chained covers. In Assisted mode, the Fifty action appears only when valid. If the timer is missed, the player may still take the discard normally when legal, but the finish scores as normal instead of Fifty.',
            ),
            _HelpSection(
              title: 'Scoring',
              body:
                  'Normal winners score -1. In Fifty, the winner scores -3, except the first dealt round uses -1, and the discarder adds remaining cards plus 3. Other active players add remaining card count. Drawn rounds do not change scores. Players at 31 or more are eliminated, and the last remaining player wins.',
            ),
            _HelpSection(
              title: 'Mistake presets',
              body:
                  'Assisted blocks illegal actions. Table penalties can allow selected mistakes with +3. Hard table 17 can allow selected mistakes with +17 and removes that player from the current round. Normal joker discard stays blocked in every preset.',
            ),
            _HelpSection(
              title: 'Pause and resume',
              body:
                  'The app saves active Classic Hareeg table state locally at safe table changes. Continue resumes the saved hands, stock, discard pile, turn phase, pending discard, and setup. Abandon saved match clears the local save.',
            ),
            _HelpSection(
              title: 'Planned modes',
              body:
                  'Hareeg 14 and a dedicated Fifties mode are planned future modes. The first release focuses on Classic Hareeg.',
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body),
        ],
      ),
    );
  }
}
