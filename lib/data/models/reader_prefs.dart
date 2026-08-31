import 'reader_theme.dart';

enum ReaderLayout { scroll, paged }
enum ReaderViewMode { original, translated, parallel }
enum ReaderFontFamily { serif, sans, mono, dyslexic }
enum LibrarySort { recent, title, difficulty, progress }

/// How list-style screens (library, news) lay their entries out.
///   * grid — cover-forward media grid
///   * list — compact rows with a small thumbnail
///   * card — full-width rich cards
enum LibraryViewMode { grid, list, card }

enum JpPosCategory { noun, verb, adjective, adverb, particle, auxiliary, other }

class JlptColorRules {
  /// matrix[pos][level: 1..5] => highlight?
  final Map<JpPosCategory, Map<int, bool>> matrix;

  const JlptColorRules({required this.matrix});

  static const _defaultOn = {1: true, 2: true, 3: true, 4: true, 5: true};
  static const _defaultOff = {1: false, 2: false, 3: false, 4: false, 5: false};

  static JlptColorRules defaults() => JlptColorRules(matrix: {
        JpPosCategory.noun: Map.from(_defaultOn),
        JpPosCategory.verb: Map.from(_defaultOn),
        JpPosCategory.adjective: Map.from(_defaultOn),
        JpPosCategory.adverb: Map.from(_defaultOn),
        JpPosCategory.particle: Map.from(_defaultOff),
        JpPosCategory.auxiliary: Map.from(_defaultOff),
        JpPosCategory.other: Map.from(_defaultOff),
      });

  bool isHighlighted(JpPosCategory pos, int level) =>
      matrix[pos]?[level] ?? false;

  JlptColorRules setRule(JpPosCategory pos, int level, bool value) {
    final next = {
      for (final e in matrix.entries) e.key: Map<int, bool>.from(e.value),
    };
    next[pos]?[level] = value;
    return JlptColorRules(matrix: next);
  }

  Map<String, dynamic> toJson() => {
        'matrix': {
          for (final e in matrix.entries)
            e.key.name: {
              for (final lv in e.value.entries) lv.key.toString(): lv.value,
            },
        },
      };

  factory JlptColorRules.fromJson(Map<String, dynamic> j) {
    final defaults = JlptColorRules.defaults();
    final m = j['matrix'];
    if (m is! Map) return defaults;
    final result = {
      for (final e in defaults.matrix.entries)
        e.key: Map<int, bool>.from(e.value),
    };
    for (final entry in m.entries) {
      final pos = JpPosCategory.values.firstWhere(
        (p) => p.name == entry.key,
        orElse: () => JpPosCategory.other,
      );
      final lvMap = entry.value;
      if (lvMap is Map) {
        for (final lv in lvMap.entries) {
          final level = int.tryParse(lv.key.toString());
          if (level == null) continue;
          result[pos]?[level] = lv.value == true;
        }
      }
    }
    return JlptColorRules(matrix: result);
  }
}

class ReaderPrefs {
  final ReaderFontFamily fontFamily;
  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final double paragraphSpacing;
  final double maxWidth;
  final String themeId;
  final List<ReaderTheme> customThemes;
  final ReaderLayout layout;
  final ReaderViewMode viewMode;
  final bool tapToTranslate;
  final bool showRubies;
  final bool autoCacheTranslations;
  final double ttsRate;
  final bool coloriseJapanese;

  /// Colour content words that aren't in the bundled JLPT lists, using a
  /// level estimated from their kanji. Rendered with a dashed underline so
  /// an estimate never passes for a listed level.
  final bool highlightUnlisted;
  final JlptColorRules jlptColorRules;
  final LibrarySort librarySort;
  final LibraryViewMode libraryViewMode;
  final LibraryViewMode newsViewMode;
  /// Soft max characters per page in paged layout. Pages pack whole
  /// paragraphs and may slightly exceed this if a single paragraph is larger.
  final int pageCharLimit;
  /// When true (paged layout only): tapping left third = prev page,
  /// right third = next page, middle = toggle chrome. When false, any tap
  /// just toggles chrome and the user swipes to turn pages.
  final bool tapZonesEnabled;
  /// When true (paged layout only), horizontal swipe also turns pages. When
  /// false the user must rely on tap zones or the bottom-bar arrows.
  final bool swipeToTurnPage;

  const ReaderPrefs({
    required this.fontFamily,
    required this.fontSize,
    required this.lineHeight,
    required this.letterSpacing,
    required this.paragraphSpacing,
    required this.maxWidth,
    required this.themeId,
    required this.customThemes,
    required this.layout,
    required this.viewMode,
    required this.tapToTranslate,
    required this.showRubies,
    required this.autoCacheTranslations,
    required this.ttsRate,
    required this.coloriseJapanese,
    required this.highlightUnlisted,
    required this.jlptColorRules,
    required this.librarySort,
    required this.libraryViewMode,
    required this.newsViewMode,
    required this.pageCharLimit,
    required this.tapZonesEnabled,
    required this.swipeToTurnPage,
  });

  static ReaderPrefs defaults() => ReaderPrefs(
        fontFamily: ReaderFontFamily.serif,
        fontSize: 18,
        lineHeight: 1.7,
        letterSpacing: 0,
        paragraphSpacing: 1,
        maxWidth: 680,
        themeId: 'paper',
        customThemes: const [],
        layout: ReaderLayout.scroll,
        viewMode: ReaderViewMode.original,
        tapToTranslate: true,
        showRubies: true,
        autoCacheTranslations: true,
        ttsRate: 1,
        coloriseJapanese: true,
        highlightUnlisted: true,
        jlptColorRules: JlptColorRules.defaults(),
        librarySort: LibrarySort.recent,
        libraryViewMode: LibraryViewMode.grid,
        newsViewMode: LibraryViewMode.grid,
        pageCharLimit: 1200,
        tapZonesEnabled: true,
        swipeToTurnPage: true,
      );

  ReaderPrefs copyWith({
    ReaderFontFamily? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    double? paragraphSpacing,
    double? maxWidth,
    String? themeId,
    List<ReaderTheme>? customThemes,
    ReaderLayout? layout,
    ReaderViewMode? viewMode,
    bool? tapToTranslate,
    bool? showRubies,
    bool? autoCacheTranslations,
    double? ttsRate,
    bool? coloriseJapanese,
    bool? highlightUnlisted,
    JlptColorRules? jlptColorRules,
    LibrarySort? librarySort,
    LibraryViewMode? libraryViewMode,
    LibraryViewMode? newsViewMode,
    int? pageCharLimit,
    bool? tapZonesEnabled,
    bool? swipeToTurnPage,
  }) =>
      ReaderPrefs(
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
        maxWidth: maxWidth ?? this.maxWidth,
        themeId: themeId ?? this.themeId,
        customThemes: customThemes ?? this.customThemes,
        layout: layout ?? this.layout,
        viewMode: viewMode ?? this.viewMode,
        tapToTranslate: tapToTranslate ?? this.tapToTranslate,
        showRubies: showRubies ?? this.showRubies,
        autoCacheTranslations:
            autoCacheTranslations ?? this.autoCacheTranslations,
        ttsRate: ttsRate ?? this.ttsRate,
        coloriseJapanese: coloriseJapanese ?? this.coloriseJapanese,
        highlightUnlisted: highlightUnlisted ?? this.highlightUnlisted,
        jlptColorRules: jlptColorRules ?? this.jlptColorRules,
        librarySort: librarySort ?? this.librarySort,
        libraryViewMode: libraryViewMode ?? this.libraryViewMode,
        newsViewMode: newsViewMode ?? this.newsViewMode,
        pageCharLimit: pageCharLimit ?? this.pageCharLimit,
        tapZonesEnabled: tapZonesEnabled ?? this.tapZonesEnabled,
        swipeToTurnPage: swipeToTurnPage ?? this.swipeToTurnPage,
      );

  Map<String, dynamic> toJson() => {
        'fontFamily': fontFamily.name,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'letterSpacing': letterSpacing,
        'paragraphSpacing': paragraphSpacing,
        'maxWidth': maxWidth,
        'themeId': themeId,
        'customThemes': customThemes.map((t) => t.toJson()).toList(),
        'layout': layout.name,
        'viewMode': viewMode.name,
        'tapToTranslate': tapToTranslate,
        'showRubies': showRubies,
        'autoCacheTranslations': autoCacheTranslations,
        'ttsRate': ttsRate,
        'coloriseJapanese': coloriseJapanese,
        'highlightUnlisted': highlightUnlisted,
        'jlptColorRules': jlptColorRules.toJson(),
        'librarySort': librarySort.name,
        'libraryViewMode': libraryViewMode.name,
        'newsViewMode': newsViewMode.name,
        'pageCharLimit': pageCharLimit,
        'tapZonesEnabled': tapZonesEnabled,
        'swipeToTurnPage': swipeToTurnPage,
      };

  factory ReaderPrefs.fromJson(Map<String, dynamic> j) {
    final d = ReaderPrefs.defaults();
    return ReaderPrefs(
      fontFamily: ReaderFontFamily.values.firstWhere(
        (f) => f.name == j['fontFamily'],
        orElse: () => d.fontFamily,
      ),
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? d.fontSize,
      lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? d.lineHeight,
      letterSpacing:
          (j['letterSpacing'] as num?)?.toDouble() ?? d.letterSpacing,
      paragraphSpacing:
          (j['paragraphSpacing'] as num?)?.toDouble() ?? d.paragraphSpacing,
      maxWidth: (j['maxWidth'] as num?)?.toDouble() ?? d.maxWidth,
      themeId: j['themeId'] as String? ?? d.themeId,
      customThemes: ((j['customThemes'] as List?) ?? const [])
          .map((t) => ReaderTheme.fromJson(Map<String, dynamic>.from(t as Map)))
          .toList(),
      layout: ReaderLayout.values.firstWhere(
        (l) => l.name == j['layout'],
        orElse: () => d.layout,
      ),
      viewMode: ReaderViewMode.values.firstWhere(
        (v) => v.name == j['viewMode'],
        orElse: () => d.viewMode,
      ),
      tapToTranslate: j['tapToTranslate'] as bool? ?? d.tapToTranslate,
      showRubies: j['showRubies'] as bool? ?? d.showRubies,
      autoCacheTranslations:
          j['autoCacheTranslations'] as bool? ?? d.autoCacheTranslations,
      ttsRate: (j['ttsRate'] as num?)?.toDouble() ?? d.ttsRate,
      coloriseJapanese: j['coloriseJapanese'] as bool? ?? d.coloriseJapanese,
      highlightUnlisted:
          j['highlightUnlisted'] as bool? ?? d.highlightUnlisted,
      jlptColorRules: j['jlptColorRules'] is Map
          ? JlptColorRules.fromJson(
              Map<String, dynamic>.from(j['jlptColorRules'] as Map))
          : d.jlptColorRules,
      librarySort: LibrarySort.values.firstWhere(
        (l) => l.name == j['librarySort'],
        orElse: () => d.librarySort,
      ),
      libraryViewMode: LibraryViewMode.values.firstWhere(
        (v) => v.name == j['libraryViewMode'],
        orElse: () => d.libraryViewMode,
      ),
      newsViewMode: LibraryViewMode.values.firstWhere(
        (v) => v.name == j['newsViewMode'],
        orElse: () => d.newsViewMode,
      ),
      pageCharLimit: (j['pageCharLimit'] as num?)?.toInt() ?? d.pageCharLimit,
      tapZonesEnabled: j['tapZonesEnabled'] as bool? ?? d.tapZonesEnabled,
      swipeToTurnPage: j['swipeToTurnPage'] as bool? ?? d.swipeToTurnPage,
    );
  }
}
