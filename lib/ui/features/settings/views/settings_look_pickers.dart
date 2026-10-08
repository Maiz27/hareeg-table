import 'package:flutter/material.dart';

import '../../../../l10n/app_strings.dart';
import '../../../core/cards/card_theme.dart';
import '../../../core/theme/lounge_tokens.dart';
import '../../../core/theme/table_surface_theme.dart';
import '../../game_table/widgets/table_background.dart';
import 'card_theme_preview.dart';
import 'meta_pill.dart';
import 'settings_controls.dart';
import 'settings_labels.dart';

/// Thumbnail picker of the table surfaces, each rendered live.
class TableSurfacePicker extends StatelessWidget {
  /// Creates a table surface picker.
  const TableSurfacePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TableSurfaceTheme value;
  final ValueChanged<TableSurfaceTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.table_restaurant_outlined,
          color: LoungeTokens.goldAccent,
        ),
        const SizedBox(width: LoungeTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.tableSurface, style: LoungeTokens.titleSmall),
              const SizedBox(height: 3),
              Text(
                strings.tableSurfaceDescription,
                style: LoungeTokens.bodyMuted,
              ),
              const SizedBox(height: LoungeTokens.space3),
              Wrap(
                spacing: LoungeTokens.space2,
                runSpacing: LoungeTokens.space3,
                children: [
                  for (final surface in TableSurfaceTheme.values)
                    _SurfaceTile(
                      surface: surface,
                      selected: surface == value,
                      onTap: () => onChanged(surface),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SurfaceTile extends StatelessWidget {
  const _SurfaceTile({
    required this.surface,
    required this.selected,
    required this.onTap,
  });

  final TableSurfaceTheme surface;
  final bool selected;
  final VoidCallback onTap;

  static const _tileWidth = 152.0;
  static const _previewHeight = 92.0;
  // Source canvas matches a landscape mobile aspect so motifs and frame
  // padding read at thumbnail scale instead of collapsing to single pixels.
  static const _sourceWidth = 520.0;
  static const _sourceHeight = 312.0;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final surfaceLabel = tableSurfaceLabel(surface, strings);
    final borderColor = selected
        ? LoungeTokens.goldAccent
        : LoungeTokens.sandLine.withValues(alpha: 0.28);
    return Semantics(
      button: true,
      selected: selected,
      label: surfaceLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LoungeTokens.radiusButton),
          child: SizedBox(
            width: _tileWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: _tileWidth,
                  height: _previewHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      LoungeTokens.radiusButton,
                    ),
                    border: Border.all(
                      color: borderColor,
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: LoungeTokens.goldAccent.withValues(
                                alpha: 0.32,
                              ),
                              blurRadius: 14,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: _sourceWidth,
                          height: _sourceHeight,
                          child: TableBackground(surface: surface),
                        ),
                      ),
                      if (selected)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: _SelectedBadge(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: LoungeTokens.space2),
                Text(
                  surfaceLabel,
                  style: TextStyle(
                    color: selected
                        ? LoungeTokens.goldAccent
                        : LoungeTokens.offWhiteText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: LoungeTokens.coffeeCharcoal,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.check_circle,
        color: LoungeTokens.goldAccent,
        size: 18,
      ),
    );
  }
}

/// List of card themes with previews, locked during an active match.
class CardThemePicker extends StatelessWidget {
  /// Creates a card theme picker.
  const CardThemePicker({
    super.key,
    required this.themes,
    required this.value,
    required this.locked,
    required this.onChanged,
  });

  final List<HareegCardTheme> themes;
  final String value;
  final bool locked;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Column(
      children: [
        for (final theme in themes) ...[
          _CardThemeRow(
            theme: theme,
            selected: theme.id == value,
            enabled: !locked && theme.available,
            onTap: () => onChanged(theme.id),
          ),
          if (theme != themes.last) const SettingsDivider(),
        ],
        if (locked)
          Padding(
            padding: const EdgeInsets.only(top: LoungeTokens.space3),
            child: Text(
              strings.themeLockedActiveMatch,
              style: LoungeTokens.bodyMuted,
            ),
          ),
      ],
    );
  }
}

class _CardThemeRow extends StatelessWidget {
  const _CardThemeRow({
    required this.theme,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final HareegCardTheme theme;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Opacity(
      opacity: enabled ? 1 : 0.64,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: LoungeTokens.space2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardThemePreview(theme: theme),
                const SizedBox(width: LoungeTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(theme.label, style: LoungeTokens.titleSmall),
                      const SizedBox(height: 2),
                      Text(theme.description, style: LoungeTokens.bodyMuted),
                      const SizedBox(height: LoungeTokens.space2),
                      Wrap(
                        spacing: LoungeTokens.space2,
                        runSpacing: LoungeTokens.space2,
                        children: [
                          MetaPill(
                            icon:
                                theme.source ==
                                    CardThemeAssetSource.codeRendered
                                ? Icons.brush_outlined
                                : Icons.collections_bookmark_outlined,
                            label:
                                theme.source ==
                                    CardThemeAssetSource.codeRendered
                                ? strings.codeRendered
                                : strings.bundledAsset,
                          ),
                          MetaPill(
                            icon: theme.readableOnCompactLayouts
                                ? Icons.check_circle_outline
                                : Icons.visibility_off_outlined,
                            label: theme.readableOnCompactLayouts
                                ? strings.smallTableReady
                                : strings.compactQaPending,
                          ),
                        ],
                      ),
                      if (theme.unavailableReason != null) ...[
                        const SizedBox(height: LoungeTokens.space2),
                        Text(
                          theme.unavailableReason!,
                          style: const TextStyle(
                            color: LoungeTokens.goldAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: LoungeTokens.space2),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? LoungeTokens.goldAccent
                      : LoungeTokens.mutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
