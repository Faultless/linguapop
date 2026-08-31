import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/reader_prefs.dart';
import '../data/models/reader_theme.dart';
import '../data/storage/storage.dart';
import '../data/themes/builtin_themes.dart';

const _prefsKey = 'reader_prefs';

class ReaderPrefsNotifier extends StateNotifier<ReaderPrefs> {
  ReaderPrefsNotifier() : super(_load()) {
    // no-op
  }

  static ReaderPrefs _load() {
    try {
      final raw = Storage.prefs().get(_prefsKey);
      if (raw is String && raw.isNotEmpty) {
        return ReaderPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {/* fall through to defaults */}
    return ReaderPrefs.defaults();
  }

  Future<void> _persist() async {
    await Storage.prefs().put(_prefsKey, jsonEncode(state.toJson()));
  }

  Future<void> update(ReaderPrefs Function(ReaderPrefs) patch) async {
    state = patch(state);
    await _persist();
  }

  Future<void> setThemeId(String id) =>
      update((p) => p.copyWith(themeId: id));

  Future<void> setFontSize(double size) =>
      update((p) => p.copyWith(fontSize: size));

  Future<void> setLineHeight(double v) =>
      update((p) => p.copyWith(lineHeight: v));

  Future<void> setMaxWidth(double v) => update((p) => p.copyWith(maxWidth: v));

  Future<void> setFontFamily(ReaderFontFamily f) =>
      update((p) => p.copyWith(fontFamily: f));

  Future<void> setLayout(ReaderLayout l) =>
      update((p) => p.copyWith(layout: l));

  Future<void> setViewMode(ReaderViewMode v) =>
      update((p) => p.copyWith(viewMode: v));

  Future<void> setColoriseJapanese(bool v) =>
      update((p) => p.copyWith(coloriseJapanese: v));

  Future<void> setHighlightUnlisted(bool v) =>
      update((p) => p.copyWith(highlightUnlisted: v));

  Future<void> setSimpleMode(bool v) =>
      update((p) => p.copyWith(simpleMode: v));

  /// Toggle one feed source on the newsstand.
  ///
  /// An empty list means "whatever the app ships on by default", so a source
  /// added in a later version appears without the user opting in. The first
  /// deviation from the defaults materialises the list.
  Future<void> setSourceEnabled(
          String id, bool enabled, List<String> defaultIds) =>
      update((p) {
        final current =
            p.enabledSourceIds.isEmpty ? defaultIds : p.enabledSourceIds;
        final next = [...current];
        if (enabled) {
          if (!next.contains(id)) next.add(id);
        } else {
          next.remove(id);
        }
        // Back to exactly the defaults: store the sentinel again.
        if (next.length == defaultIds.length &&
            next.toSet().containsAll(defaultIds)) {
          return p.copyWith(enabledSourceIds: const []);
        }
        return p.copyWith(enabledSourceIds: next);
      });

  /// Ids of the feeds actually carried, resolving the "empty = defaults"
  /// sentinel. [defaultIds] comes from the source registry.
  static Set<String> carriedSources(
          ReaderPrefs prefs, Iterable<String> defaultIds) =>
      prefs.enabledSourceIds.isEmpty
          ? defaultIds.toSet()
          : prefs.enabledSourceIds.toSet();

  Future<void> setShowRubies(bool v) => update((p) => p.copyWith(showRubies: v));

  Future<void> setTtsRate(double r) => update((p) => p.copyWith(ttsRate: r));

  Future<void> setLibrarySort(LibrarySort s) =>
      update((p) => p.copyWith(librarySort: s));

  Future<void> setLibraryViewMode(LibraryViewMode v) =>
      update((p) => p.copyWith(libraryViewMode: v));

  Future<void> setNewsViewMode(LibraryViewMode v) =>
      update((p) => p.copyWith(newsViewMode: v));

  Future<void> setPageCharLimit(int n) =>
      update((p) => p.copyWith(pageCharLimit: n));

  Future<void> setTapZonesEnabled(bool v) =>
      update((p) => p.copyWith(tapZonesEnabled: v));

  Future<void> setSwipeToTurnPage(bool v) =>
      update((p) => p.copyWith(swipeToTurnPage: v));

  Future<void> setJlptRule(JpPosCategory pos, int level, bool value) =>
      update((p) => p.copyWith(
          jlptColorRules: p.jlptColorRules.setRule(pos, level, value)));

  Future<void> addCustomTheme(ReaderTheme t) => update((p) {
        final filtered = p.customThemes.where((x) => x.id != t.id).toList();
        return p.copyWith(customThemes: [
          ...filtered,
          ReaderTheme(
              id: t.id,
              name: t.name,
              bg: t.bg,
              fg: t.fg,
              accent: t.accent,
              muted: t.muted,
              dark: t.dark,
              custom: true),
        ]);
      });

  Future<void> removeCustomTheme(String id) => update((p) => p.copyWith(
        customThemes: p.customThemes.where((x) => x.id != id).toList(),
        themeId: p.themeId == id ? kDefaultThemeId : p.themeId,
      ));
}

final readerPrefsProvider =
    StateNotifierProvider<ReaderPrefsNotifier, ReaderPrefs>(
  (ref) => ReaderPrefsNotifier(),
);

final activeThemeProvider = Provider<ReaderTheme>((ref) {
  final prefs = ref.watch(readerPrefsProvider);
  return resolveTheme(prefs.themeId, prefs.customThemes);
});
