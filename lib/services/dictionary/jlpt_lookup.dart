import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class JlptHit {
  final int level; // 1..5 (5 = easiest, 1 = hardest)
  final String? gloss;

  /// True when the level wasn't found in the bundled lists but was inferred
  /// (from the word's kanji, or from a script heuristic). Rendered with a
  /// dashed underline so the reader knows it's a guess.
  final bool approximate;

  const JlptHit({
    required this.level,
    this.gloss,
    this.approximate = false,
  });
}

/// Bundled-JLPT lookup. Loads two assets at app start:
///   * assets/jlpt/vocab.json    — ~8k entries from the Tanos / Jonathan Waller
///                                  list; tuple of (expression, reading, level, gloss).
///   * assets/jlpt/starter.json  — ~300 curated common entries (particles,
///                                  kana words) keyed by comma-separated surfaces.
///
/// Both expand to a single `String → JlptHit` map. When the same key exists at
/// multiple levels we keep the easier (higher number).
///
/// On top of the exact map there are two fallback layers, because an 8k-word
/// list covers only a fraction of real news prose:
///
///   1. **De-inflection** — potential/passive/causative stems and a handful of
///      productive noun suffixes (〜的 / 〜化 / 〜性 …) are reduced back to a
///      form that might be listed. Still an *exact* hit when it matches.
///   2. **Estimation** ([estimate]) — a word with no listed form is scored from
///      the JLPT levels of its individual kanji (derived from the bundled
///      vocabulary itself), so compounds like 経済成長 or 記者会見 still get a
///      plausible level instead of rendering colorless. Flagged
///      [JlptHit.approximate].
class JlptLookup {
  final Map<String, JlptHit> _map = {};

  /// kanji → easiest JLPT level it appears at across the bundled vocabulary.
  final Map<String, int> _kanjiLevel = {};

  bool _loaded = false;
  final List<void Function()> _listeners = [];

  bool get isLoaded => _loaded;
  int get size => _map.length;
  int get kanjiCount => _kanjiLevel.length;

  Future<void> load() async {
    if (_loaded) return;
    await Future.wait([
      _loadFullVocab(),
      _loadStarter(),
    ]);
    _loaded = true;
    _notify();
  }

  Future<void> _loadFullVocab() async {
    try {
      final raw = await rootBundle.loadString('assets/jlpt/vocab.json');
      ingestVocab(jsonDecode(raw) as List);
    } catch (_) {/* asset missing — fall through */}
  }

  Future<void> _loadStarter() async {
    try {
      final raw = await rootBundle.loadString('assets/jlpt/starter.json');
      ingestStarter(jsonDecode(raw) as List);
    } catch (_) {}
  }

  /// Parse the decoded `vocab.json` payload. Public so tests can feed the real
  /// asset in from disk without a Flutter binding.
  void ingestVocab(List entries) {
    for (final e in entries) {
      final m = e as Map<String, dynamic>;
      final level = (m['n'] as num).toInt();
      final gloss = m['g'] as String?;
      final key = m['k'] as String;
      _put(key, level, gloss);
      _harvestKanji(key, level);
      final reading = m['r'] as String?;
      if (reading != null && reading.isNotEmpty) {
        _put(reading, level, gloss);
      }
    }
  }

  /// Parse the decoded `starter.json` payload (comma-separated surfaces).
  void ingestStarter(List entries) {
    for (final e in entries) {
      final m = e as Map<String, dynamic>;
      final level = (m['n'] as num).toInt();
      final gloss = m['g'] as String?;
      for (final k in (m['k'] as String).split(',')) {
        final t = k.trim();
        if (t.isEmpty) continue;
        _put(t, level, gloss);
        _harvestKanji(t, level);
      }
    }
  }

  void _put(String key, int level, String? gloss) {
    final existing = _map[key];
    // Prefer the easier-level entry when duplicates exist (higher N number).
    if (existing != null && existing.level >= level) return;
    _map[key] = JlptHit(level: level, gloss: gloss);
  }

  /// Record every kanji of [word] as "seen at level [level]", keeping the
  /// easiest level a kanji ever appears at. 出 shows up in 出る (N5) and 提出
  /// (N2) — for a per-character difficulty proxy the N5 sighting is the
  /// meaningful one.
  void _harvestKanji(String word, int level) {
    for (final r in word.runes) {
      if (!_isKanjiRune(r)) continue;
      final c = String.fromCharCode(r);
      final existing = _kanjiLevel[c];
      if (existing == null || existing < level) _kanjiLevel[c] = level;
    }
  }

  /// Exact lookup: tries base → surface → reading, then a small set of
  /// de-inflections / suffix strips of the base form. Returns null when the
  /// word isn't in the bundled lists in any recognisable form.
  JlptHit? lookup({String? base, String? surface, String? reading}) {
    for (final k in [base, surface, reading]) {
      if (k == null || k.isEmpty) continue;
      final hit = _map[k];
      if (hit != null) return hit;
    }
    for (final k in [base, surface]) {
      if (k == null || k.isEmpty) continue;
      for (final v in _variants(k)) {
        final hit = _map[v];
        if (hit != null) return hit;
      }
    }
    return null;
  }

  /// [lookup], falling back to a per-kanji estimate so that content words
  /// outside the 8k list still get a level. Returns null only when there's
  /// nothing to go on (kana-only word with no listed form).
  ///
  /// The estimate is the *hardest* level among the word's kanji: 経済成長 is
  /// as hard as its hardest character, which is the level a reader will
  /// actually stumble on. Kanji that appear nowhere in the bundled list are
  /// treated as N1.
  JlptHit? estimate({String? base, String? surface, String? reading}) {
    final exact = lookup(base: base, surface: surface, reading: reading);
    if (exact != null) return exact;

    final word = (base != null && base.isNotEmpty) ? base : (surface ?? '');
    if (word.isEmpty) return null;

    var level = 6; // sentinel: easier than N5
    var kanji = 0;
    for (final r in word.runes) {
      if (!_isKanjiRune(r)) continue;
      kanji++;
      final lv = _kanjiLevel[String.fromCharCode(r)] ?? 1;
      if (lv < level) level = lv;
    }
    if (kanji > 0) {
      return JlptHit(level: level.clamp(1, 5), approximate: true);
    }

    // Katakana-only words are loanwords/technical terms; an unlisted one is
    // typically intermediate vocabulary. Only guess for words long enough to
    // be a real term rather than a particle or interjection.
    if (word.runes.length >= 3 && _isKatakanaOnly(word)) {
      return const JlptHit(level: 2, approximate: true);
    }
    return null;
  }

  /// Productive forms that reduce back to a listed dictionary entry.
  /// Everything yielded here is a *guess at spelling*, checked against the
  /// map — a wrong guess simply misses.
  Iterable<String> _variants(String w) sync* {
    if (w.length < 2) return;

    // 五段 potential: 読める → 読む, 書ける → 書く.
    if (w.endsWith('る')) {
      final stem = w.substring(0, w.length - 1);
      final u = _eRowToURow[stem.substring(stem.length - 1)];
      if (u != null) yield stem.substring(0, stem.length - 1) + u;
    }
    // Passive / potential / causative bases that survived as their own entry.
    for (final suffix in const ['られる', 'させる', 'せる', 'れる']) {
      if (w.length > suffix.length && w.endsWith(suffix)) {
        final stem = w.substring(0, w.length - suffix.length);
        yield '$stemる'; // 一段: 見られる → 見る
        final u = _aRowToURow[stem.substring(stem.length - 1)];
        if (u != null) {
          // 五段: 読ま(れる) → 読む
          yield stem.substring(0, stem.length - 1) + u;
        }
      }
    }
    // Productive affixes. する first: the conjugation merger hands us
    // 発表する as one token's base, and the JLPT list carries the bare noun.
    for (final suffix in const [
      'する', '的', '化', '性', '者', '感', '力', '度', '中', '達', 'たち',
    ]) {
      if (w.length > suffix.length && w.endsWith(suffix)) {
        yield w.substring(0, w.length - suffix.length);
      }
    }
    for (final prefix in const ['お', 'ご', '御', '再', '不', '無']) {
      if (w.length > prefix.length && w.startsWith(prefix)) {
        yield w.substring(prefix.length);
      }
    }
  }

  static const _eRowToURow = {
    'え': 'う', 'け': 'く', 'げ': 'ぐ', 'せ': 'す', 'ぜ': 'ず',
    'て': 'つ', 'ね': 'ぬ', 'へ': 'ふ', 'べ': 'ぶ', 'め': 'む',
    'れ': 'る',
  };

  static const _aRowToURow = {
    'あ': 'う', 'か': 'く', 'が': 'ぐ', 'さ': 'す', 'ざ': 'ず',
    'た': 'つ', 'な': 'ぬ', 'は': 'ふ', 'ば': 'ぶ', 'ま': 'む',
    'ら': 'る', 'わ': 'う',
  };

  static bool _isKanjiRune(int r) =>
      (r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF);

  static bool _isKatakanaOnly(String s) {
    for (final r in s.runes) {
      final katakana = (r >= 0x30A0 && r <= 0x30FF) || r == 0x30FC;
      if (!katakana) return false;
    }
    return true;
  }

  /// True when [word] has an exact entry in the bundled lists. Used by the
  /// tokenizer's noun-compound pass to decide whether a run of nouns is a
  /// dictionary word worth gluing back together.
  bool contains(String word) => _map.containsKey(word);

  /// Merge entries from an external source (e.g. cached Jisho lookups) into
  /// the live map. Notifies listeners exactly once if anything was added.
  void register(Iterable<({String key, int level, String? gloss})> entries) {
    var changed = false;
    for (final e in entries) {
      if (e.key.isEmpty) continue;
      final existing = _map[e.key];
      if (existing != null && existing.level >= e.level) continue;
      _map[e.key] = JlptHit(level: e.level, gloss: e.gloss);
      _harvestKanji(e.key, e.level);
      changed = true;
    }
    if (changed) _notify();
  }

  /// Subscribe to mutations of the lookup map (e.g. when Jisho fills in a
  /// previously-grey word). Returns an unsubscribe function.
  void Function() addListener(void Function() cb) {
    _listeners.add(cb);
    return () => _listeners.remove(cb);
  }

  void _notify() {
    for (final cb in List.of(_listeners)) {
      cb();
    }
  }
}
