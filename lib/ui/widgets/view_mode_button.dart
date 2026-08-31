import 'package:flutter/material.dart';

import '../../data/models/reader_prefs.dart';

/// App-bar button that picks the list layout (grid / list / card). Shows the
/// current mode's icon and opens a small menu of the three standard options.
class ViewModeButton extends StatelessWidget {
  final LibraryViewMode mode;
  final ValueChanged<LibraryViewMode> onChanged;

  /// Per-screen renames — the news front page calls `grid` "Front page"
  /// rather than "Media", because there it means a two-column broadsheet.
  final Map<LibraryViewMode, String> labelOverrides;
  final Map<LibraryViewMode, IconData> iconOverrides;

  const ViewModeButton({
    super.key,
    required this.mode,
    required this.onChanged,
    this.labelOverrides = const {},
    this.iconOverrides = const {},
  });

  IconData _icon(LibraryViewMode m) => iconOverrides[m] ?? iconFor(m);
  String _label(LibraryViewMode m) => labelOverrides[m] ?? labelFor(m);

  static IconData iconFor(LibraryViewMode m) {
    switch (m) {
      case LibraryViewMode.grid:
        return Icons.grid_view_rounded;
      case LibraryViewMode.list:
        return Icons.view_list_rounded;
      case LibraryViewMode.card:
        return Icons.view_agenda_outlined;
    }
  }

  static String labelFor(LibraryViewMode m) {
    switch (m) {
      case LibraryViewMode.grid:
        return 'Media';
      case LibraryViewMode.list:
        return 'List';
      case LibraryViewMode.card:
        return 'Cards';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LibraryViewMode>(
      tooltip: 'View',
      icon: Icon(_icon(mode)),
      onSelected: onChanged,
      itemBuilder: (ctx) => [
        for (final m in LibraryViewMode.values)
          PopupMenuItem(
            value: m,
            child: Row(
              children: [
                Icon(_icon(m),
                    size: 18,
                    color: m == mode
                        ? Theme.of(ctx).colorScheme.primary
                        : null),
                const SizedBox(width: 12),
                Text(_label(m)),
                if (m == mode) ...[
                  const Spacer(),
                  Icon(Icons.check,
                      size: 16, color: Theme.of(ctx).colorScheme.primary),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
