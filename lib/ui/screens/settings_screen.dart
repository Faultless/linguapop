import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/reader_prefs.dart';
import '../../data/themes/builtin_themes.dart';
import '../../providers/prefs_provider.dart';
import 'source_manager_screen.dart';

/// Settings hub. One row per area rather than one long scroll, so the
/// everyday settings (theme, text size) aren't buried under the JLPT
/// highlight matrix.
///
/// Sub-screens are pushed onto the ambient Navigator rather than routed:
/// they're leaves, nothing deep-links to them, and this keeps `/settings` and
/// `/reader/:id/settings` from each needing a parallel set of child routes.
class ReaderSettingsScreen extends ConsumerWidget {
  const ReaderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(readerPrefsProvider);
    final notifier = ref.read(readerPrefsProvider.notifier);
    final simple = prefs.simpleMode;

    void push(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _SimpleModeTile(
                value: simple, onChanged: notifier.setSimpleMode),
          ),
          const Divider(height: 24),
          _NavTile(
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: _themeName(prefs),
            onTap: () => push(const ThemeSettingsScreen()),
          ),
          _NavTile(
            icon: Icons.text_fields,
            title: 'Text & layout',
            subtitle:
                '${prefs.fontSize.round()} pt · ${prefs.fontFamily.name} · ${prefs.layout.name}',
            onTap: () => push(const TextSettingsScreen()),
          ),
          _NavTile(
            icon: Icons.translate,
            title: 'Japanese',
            subtitle: prefs.coloriseJapanese
                ? 'JLPT colouring on'
                : 'JLPT colouring off',
            onTap: () => push(const JapaneseSettingsScreen()),
          ),
          _NavTile(
            icon: Icons.newspaper_outlined,
            title: 'Papers',
            subtitle: prefs.enabledSourceIds.isEmpty
                ? 'Default papers on the stand'
                : '${prefs.enabledSourceIds.length} on the stand',
            onTap: () => push(const SourceManagerScreen()),
          ),
          if (!simple) ...[
            const Divider(height: 24),
            _NavTile(
              icon: Icons.style_outlined,
              title: 'Saved vocabulary',
              subtitle: 'Review and export to Anki',
              onTap: () => context.go('/vocab'),
            ),
            _NavTile(
              icon: Icons.travel_explore,
              title: 'Browse sources',
              subtitle: 'Search Syosetu, add individual articles',
              onTap: () => context.go('/sources'),
            ),
          ],
        ],
      ),
    );
  }

  static String _themeName(ReaderPrefs prefs) {
    for (final t in [...kBuiltinThemes, ...prefs.customThemes]) {
      if (t.id == prefs.themeId) return t.name;
    }
    return prefs.themeId;
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.6))),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

// ─────────── leaves ───────────

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(readerPrefsProvider);
    final notifier = ref.read(readerPrefsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        children: [
          _ThemeGrid(prefs: prefs, onPick: notifier.setThemeId),
        ],
      ),
    );
  }
}

class TextSettingsScreen extends ConsumerWidget {
  const TextSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(readerPrefsProvider);
    final notifier = ref.read(readerPrefsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Text & layout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          _SectionTitle('Typography'),
          _Slider(
            label: 'Font size',
            value: prefs.fontSize,
            min: 12,
            max: 32,
            divisions: 20,
            display: (v) => v.round().toString(),
            onChanged: notifier.setFontSize,
          ),
          _Slider(
            label: 'Line height',
            value: prefs.lineHeight,
            min: 1.2,
            max: 2.4,
            divisions: 12,
            display: (v) => v.toStringAsFixed(2),
            onChanged: notifier.setLineHeight,
          ),
          _Slider(
            label: 'Column width',
            value: prefs.maxWidth,
            min: 360,
            max: 1100,
            divisions: 37,
            display: (v) => '${v.round()} px',
            onChanged: notifier.setMaxWidth,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Font family'),
            trailing: DropdownButton<ReaderFontFamily>(
              value: prefs.fontFamily,
              onChanged: (v) {
                if (v != null) notifier.setFontFamily(v);
              },
              items: ReaderFontFamily.values
                  .map((f) => DropdownMenuItem(value: f, child: Text(f.name)))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('Layout'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Layout'),
            trailing: DropdownButton<ReaderLayout>(
              value: prefs.layout,
              onChanged: (v) {
                if (v != null) notifier.setLayout(v);
              },
              items: ReaderLayout.values
                  .map((l) => DropdownMenuItem(value: l, child: Text(l.name)))
                  .toList(),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('View mode'),
            trailing: DropdownButton<ReaderViewMode>(
              value: prefs.viewMode,
              onChanged: (v) {
                if (v != null) notifier.setViewMode(v);
              },
              items: ReaderViewMode.values
                  .map((v) => DropdownMenuItem(value: v, child: Text(v.name)))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          _SectionTitle('Page turns (paged layout)'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tap edge to turn page'),
            subtitle: const Text('Left third = previous, right third = next.'),
            value: prefs.tapZonesEnabled,
            onChanged: notifier.setTapZonesEnabled,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Swipe to turn page'),
            subtitle: const Text('Horizontal swipe across the page.'),
            value: prefs.swipeToTurnPage,
            onChanged: notifier.setSwipeToTurnPage,
          ),
          _Slider(
            label: 'Page size',
            value: prefs.pageCharLimit.toDouble(),
            min: 600,
            max: 3000,
            divisions: 24,
            display: (v) => '${v.round()} chars',
            onChanged: (v) => notifier.setPageCharLimit(v.round()),
          ),
        ],
      ),
    );
  }
}

class JapaneseSettingsScreen extends ConsumerWidget {
  const JapaneseSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(readerPrefsProvider);
    final notifier = ref.read(readerPrefsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Japanese')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show furigana'),
            value: prefs.showRubies,
            onChanged: notifier.setShowRubies,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Colorise Japanese by JLPT'),
            value: prefs.coloriseJapanese,
            onChanged: notifier.setColoriseJapanese,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Estimate unlisted words'),
            subtitle: const Text(
                'Colour words outside the JLPT lists from their kanji '
                '(dashed underline)'),
            value: prefs.highlightUnlisted,
            onChanged:
                prefs.coloriseJapanese ? notifier.setHighlightUnlisted : null,
          ),
          if (!prefs.simpleMode) ...[
            const SizedBox(height: 20),
            _SectionTitle('JLPT highlight matrix'),
            _JlptMatrix(prefs: prefs, onChanged: notifier.setJlptRule),
          ],
        ],
      ),
    );
  }
}

/// The one switch that changes the shape of the app.
class _SimpleModeTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SimpleModeTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.auto_stories_outlined),
      title: const Text('Reading mode'),
      subtitle: const Text(
          'Shelves, the front page and the reader. Swipe to change paper.'),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.primary,
          )),
    );
  }
}

class _Slider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) display;
  final ValueChanged<double> onChanged;
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(display(value),
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7))),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: display(value),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ThemeGrid extends StatelessWidget {
  final ReaderPrefs prefs;
  final ValueChanged<String> onPick;
  const _ThemeGrid({required this.prefs, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final allThemes = [...kBuiltinThemes, ...prefs.customThemes];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final t in allThemes)
          GestureDetector(
            onTap: () => onPick(t.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 92,
              height: 64,
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  width: t.id == prefs.themeId ? 2 : 1,
                  color: t.id == prefs.themeId
                      ? t.accent
                      : t.fg.withValues(alpha: 0.18),
                ),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Aあ字',
                      style: TextStyle(
                          fontSize: 16,
                          color: t.fg,
                          fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: t.accent,
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 6),
                      Text(t.name,
                          style: TextStyle(fontSize: 10.5, color: t.muted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _JlptMatrix extends StatelessWidget {
  final ReaderPrefs prefs;
  final Future<void> Function(JpPosCategory, int, bool) onChanged;
  const _JlptMatrix({required this.prefs, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final rules = prefs.jlptColorRules;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 88),
                for (final lv in const [5, 4, 3, 2, 1])
                  Expanded(
                    child: Center(
                      child: Text('N$lv',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: kJlptColors[lv])),
                    ),
                  ),
              ],
            ),
            for (final pos in JpPosCategory.values)
              Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(pos.name,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  for (final lv in const [5, 4, 3, 2, 1])
                    Expanded(
                      child: Checkbox(
                        value: rules.isHighlighted(pos, lv),
                        onChanged: (v) => onChanged(pos, lv, v ?? false),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
