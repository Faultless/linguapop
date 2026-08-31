import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reader_prefs.dart';
import '../../data/themes/builtin_themes.dart';
import '../../providers/prefs_provider.dart';

class ReaderSettingsScreen extends ConsumerWidget {
  const ReaderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(readerPrefsProvider);
    final notifier = ref.read(readerPrefsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Reader settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          _SectionTitle('Theme'),
          _ThemeGrid(prefs: prefs, onPick: notifier.setThemeId),

          const SizedBox(height: 24),
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

          const SizedBox(height: 24),
          _SectionTitle('Reading'),
          ListTile(
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
            title: const Text('Tap edge to turn page'),
            subtitle:
                const Text('Left third = previous, right third = next.'),
            value: prefs.tapZonesEnabled,
            onChanged: notifier.setTapZonesEnabled,
          ),
          SwitchListTile(
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
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Show furigana'),
            value: prefs.showRubies,
            onChanged: notifier.setShowRubies,
          ),
          SwitchListTile(
            title: const Text('Colorise Japanese by JLPT'),
            value: prefs.coloriseJapanese,
            onChanged: notifier.setColoriseJapanese,
          ),
          SwitchListTile(
            title: const Text('Estimate unlisted words'),
            subtitle: const Text(
                'Colour words outside the JLPT lists from their kanji '
                '(dashed underline)'),
            value: prefs.highlightUnlisted,
            onChanged:
                prefs.coloriseJapanese ? notifier.setHighlightUnlisted : null,
          ),

          const SizedBox(height: 24),
          _SectionTitle('JLPT highlight matrix'),
          _JlptMatrix(prefs: prefs, onChanged: notifier.setJlptRule),
        ],
      ),
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
