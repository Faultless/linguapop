import '../../data/models/jlpt_stats.dart';
import '../../data/models/reader_prefs.dart' show JpPosCategory;
import '../tokenizer/jp_tokenizer.dart';
import 'jlpt_lookup.dart';

/// Estimates how difficult a Japanese text is by tokenizing it and bucketing
/// every content word against the JLPT vocab table. The result is a
/// [JlptStats] whose `difficultyBucket` gives the closest JLPT level
/// (5 = easiest … 1 = hardest).
///
/// Used by the sources browser (title + summary → rough estimate) and the
/// news hub (full article text → accurate estimate). Results are memoized by
/// text so list rebuilds are free.
class JlptEstimator {
  static const _maxCacheEntries = 300;

  /// How much of a text is analyzed. Long texts converge quickly, and this is
  /// also the window used when the estimate is precomputed at import time —
  /// both paths must agree or the same article would score differently
  /// depending on when it was imported.
  static const sampleChars = 1500;

  final JpTokenizer _tokenizer;
  final JlptLookup _lookup;

  /// LRU keyed on the analyzed text.
  final Map<String, JlptStats> _cache = {};

  JlptEstimator(this._tokenizer, this._lookup);

  /// Counted toward the difficulty estimate: the open word classes a learner
  /// actually has to know. Particles/auxiliaries are near-universal and would
  /// drag every estimate toward N5.
  static const _contentCategories = {
    JpPosCategory.noun,
    JpPosCategory.verb,
    JpPosCategory.adjective,
    JpPosCategory.adverb,
  };

  /// Returns null when the tokenizer is unavailable (e.g. web stub) or the
  /// text has no Japanese content words.
  Future<JlptStats?> estimate(String text) async {
    if (text.trim().isEmpty) return null;
    await _tokenizer.init();
    await _lookup.load();
    if (_tokenizer.status != TokenizerStatus.ready) return null;
    return estimateSync(text);
  }

  /// The leading slice of [text] that gets analyzed.
  static String sample(String text) =>
      text.length <= sampleChars ? text : text.substring(0, sampleChars);

  /// Synchronous variant for callers that already know the pipeline is warm.
  JlptStats? estimateSync(String text) {
    if (_tokenizer.status != TokenizerStatus.ready) return null;
    final key = sample(text);

    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // move to MRU position
      return hit;
    }

    var n5 = 0, n4 = 0, n3 = 0, n2 = 0, n1 = 0, unknown = 0, total = 0;
    for (final tk in _tokenizer.tokenize(key)) {
      if (tk.isFiller) continue;
      if (!_contentCategories.contains(tk.posCategory)) continue;
      total++;
      // Estimated levels count too: an article full of unlisted compounds is
      // hard, and scoring those as "unknown" collapsed every news estimate
      // toward the handful of listed words in it.
      final h = _lookup.estimate(
          base: tk.base, surface: tk.surface, reading: tk.reading);
      switch (h?.level) {
        case 5: n5++;
        case 4: n4++;
        case 3: n3++;
        case 2: n2++;
        case 1: n1++;
        default: unknown++;
      }
    }
    if (total == 0) return null;
    final stats = JlptStats(
        n5: n5, n4: n4, n3: n3, n2: n2, n1: n1, unknown: unknown, total: total);
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = stats;
    return stats;
  }
}
