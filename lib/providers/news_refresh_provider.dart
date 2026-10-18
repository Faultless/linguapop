import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sources/feed_sync.dart';
import '../services/sources/news_freshness.dart';
import '../services/sources/source_types.dart';
import 'prefs_provider.dart';
import 'sources_provider.dart';

/// Keeps the carried papers current without the reader asking.
///
/// State is the set of source ids refreshing right now, so the front page can
/// show a quiet progress line. Runs on cold start, on resume, and when a paper
/// is opened; each paper is only synced when [NewsFreshness.isStale] says so,
/// and only stories it doesn't already have are fetched.
class NewsRefreshNotifier extends StateNotifier<Set<String>> {
  final Ref _ref;
  NewsRefreshNotifier(this._ref) : super(const {});

  List<FeedSource> _carried() {
    final registry = _ref.read(sourceRegistryProvider);
    final carried = ReaderPrefsNotifier.carriedSources(
        _ref.read(readerPrefsProvider), registry.defaultFeedIds);
    return registry.feedSources.where((s) => carried.contains(s.id)).toList();
  }

  /// Refresh every paper on the stand that's stale.
  Future<void> refreshCarried() => refresh(_carried());

  /// Refresh the stale ones among [sources] and trim every one of them to the
  /// configured window.
  Future<void> refresh(List<FeedSource> sources) async {
    if (kIsWeb) return;
    final days = _ref.read(readerPrefsProvider).newsWindowDays;
    final cutoff = FeedSync.windowStart(days).millisecondsSinceEpoch;
    final stamps = NewsFreshness.load();
    final now = DateTime.now();
    final due = [
      for (final s in sources)
        if (!state.contains(s.id) &&
            NewsFreshness.isStale(stamps[s.id], days, now))
          s,
    ];
    if (due.isNotEmpty) state = {...state, for (final s in due) s.id};
    final importer = _ref.read(sourceImporterProvider);
    for (final s in sources) {
      if (due.contains(s)) {
        var ok = false;
        try {
          final result = await _ref.read(feedSyncProvider).run(
              sources: [s], mode: FeedFetchMode.window, days: days);
          ok = result.failedSources.isEmpty;
          if (ok) {
            await NewsFreshness.stamp(
                s.id, SyncStamp(now.millisecondsSinceEpoch, days));
          }
        } finally {
          if (mounted) state = {...state}..remove(s.id);
        }
        // Offline: keep yesterday's paper rather than trimming it to nothing.
        if (!ok) continue;
      }
      await importer.pruneBefore(sourceId: s.id, cutoffMs: cutoff);
    }
  }
}

final newsRefreshProvider =
    StateNotifierProvider<NewsRefreshNotifier, Set<String>>(
        (ref) => NewsRefreshNotifier(ref));
