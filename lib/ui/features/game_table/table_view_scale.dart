import 'package:flutter/widgets.dart';

/// Exposes the live-table render scale to descendants.
///
/// On web the whole table is scaled up to fill the window (see the
/// `_ZoomToFillTable` wrapper in the game table screen). Widgets inside that
/// subtree ride the scale automatically because a single `FittedBox` transforms
/// them. Anything painted in the root [Overlay] — notably [Draggable] feedback
/// with `rootOverlay: true` — is detached from that transform and must scale
/// itself by [scale] to match the cards on the table. Defaults to 1.0 (native,
/// where the table is not scaled).
class TableViewScale extends InheritedWidget {
  /// Wraps [child] with the active table [scale].
  const TableViewScale({super.key, required this.scale, required super.child});

  /// Multiplier applied to the table's logical layout to fill the viewport.
  final double scale;

  /// The nearest table scale, or 1.0 when none is in scope.
  static double of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TableViewScale>();
    return scope?.scale ?? 1.0;
  }

  @override
  bool updateShouldNotify(TableViewScale oldWidget) => scale != oldWidget.scale;
}
