import 'dart:async';

import 'source_import.dart';
import 'source_types.dart';

/// How much of a feed to pull in one pass.
enum FeedFetchMode {
  /// Everything published today (local time) that isn't imported yet.
  today,

  /// The newest 10 unimported items, whatever their date.
  latest10,

  /// The newest 30 unimported items.
  latest30,

  /// Everything published on one particular calendar day. Paired with the
  /// `day` argument to [FeedSync.run].
  day,

  /// Everything filed within the last N calendar days (today included).
  /// Paired with the `days` argument; what the automatic refresh uses.
  window,
}

extension FeedFetchModeLabel on FeedFetchMode {
  String get label => switch (this) {
        FeedFetchMode.today => "Today's paper",
        FeedFetchMode.latest10 => 'Latest 10',
        FeedFetchMode.latest30 => 'Latest 30',
        FeedFetchMode.day => 'A single day',
        FeedFetchMode.window => 'Recent days',
      };

  String get description => switch (this) {
        FeedFetchMode.today =>
          "Everything from today — or the latest edition if today's isn't out",
        FeedFetchMode.latest10 => 'The 10 newest stories you don\'t have yet',
        FeedFetchMode.latest30 => 'The 30 newest stories you don\'t have yet',
        FeedFetchMode.day => 'Every story a paper filed that day',
        FeedFetchMode.window => 'Every story from the last few days',
      };
}

class FeedSyncResult {
  final int added;
  final int considered;
  final List<String> failedSources;
  final bool cancelled;
  const FeedSyncResult({
    required this.added,
    required this.considered,
    this.failedSources = const [],
    this.cancelled = false,
  });

  /// One-line summary for a snackbar.
  String get summary {
    final b = StringBuffer();
    if (cancelled) {
      b.write(added == 0
          ? 'Stopped before anything was fetched.'
          : 'Stopped after $added stor${added == 1 ? "y" : "ies"}.');
    } else if (added == 0) {
      b.write(considered == 0
          ? 'Nothing new to fetch.'
          : 'Already up to date.');
    } else {
      b.write('Fetched $added new stor${added == 1 ? "y" : "ies"}.');
    }
    if (failedSources.isNotEmpty) {
      b.write(' (${failedSources.join(", ")} unreachable)');
    }
    return b.toString();
  }
}

/// One day's worth of back issues across the papers surveyed.
class DayAvailability {
  final DateTime day;
  int _available = 0;
  int _total = 0;

  DayAvailability({required this.day});

  /// Stories filed that day that aren't in the library yet.
  int get available => _available;

  /// Stories filed that day that the feeds are still carrying at all.
  int get total => _total;
}

/// Live progress of a running sync, so the UI can show which paper is being
/// fetched without threading four callbacks through.
class FeedSyncProgress {
  final String sourceName;
  final int done;
  final int total;
  const FeedSyncProgress(this.sourceName, this.done, this.total);

  double? get fraction => total == 0 ? null : done / total;
  String get label => total == 0 ? sourceName : '$sourceName · $done / $total';
}

/// Bulk "get me the paper" fetch across one or more feed sources.
///
/// This replaces the old per-article tapping in the browse screen for the
/// common case: pick a mode, pick the papers, and the articles land in the
/// rolling feed novels the news hub reads from.
class FeedSync {
  final SourceImporter _importer;

  /// Resolves the set of `sourceUrl`s already imported for a source id.
  final Future<Set<String>> Function(String sourceId) _imported;

  /// Politeness delay between two article fetches on the same source.
  static const _delay = Duration(milliseconds: 250);

  /// Hard ceiling on one pass, whatever the mode asks for — a first "today"
  /// sync on a busy wire service shouldn't pull a hundred articles.
  static const maxPerSource = 40;

  /// Ceiling for a [FeedFetchMode.window] pass, which may backfill two weeks.
  static const maxPerWindow = 120;

  /// Midnight starting a window of [days] calendar days ending today.
  static DateTime windowStart(int days, [DateTime? now]) {
    final n = now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day - (days < 1 ? 0 : days - 1));
  }

  FeedSync(this._importer, this._imported);

  Future<FeedSyncResult> run({
    required List<FeedSource> sources,
    required FeedFetchMode mode,
    DateTime? day,
    int days = 3,
    void Function(FeedSyncProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var added = 0;
    var considered = 0;
    final failed = <String>[];
    for (final source in sources) {
      if (isCancelled?.call() ?? false) {
        return FeedSyncResult(
            added: added,
            considered: considered,
            failedSources: failed,
            cancelled: true);
      }
      try {
        onProgress?.call(FeedSyncProgress(source.name, 0, 0));
        final stubs = await source.list();
        final imported = await _imported(source.id);
        final fresh =
            selectForMode(stubs, imported, mode, day: day, days: days);
        considered += fresh.length;
        if (fresh.isEmpty) continue;
        // One commit per source: the front page redraws once when the batch
        // lands, not once per article fetched.
        added += await _importer.importArticles(
          source: source,
          stubs: fresh,
          delay: _delay,
          isCancelled: isCancelled,
          onProgress: (done, total) =>
              onProgress?.call(FeedSyncProgress(source.name, done, total)),
        );
        if (isCancelled?.call() ?? false) {
          return FeedSyncResult(
              added: added,
              considered: considered,
              failedSources: failed,
              cancelled: true);
        }
      } catch (_) {
        failed.add(source.name);
      }
    }
    return FeedSyncResult(
        added: added, considered: considered, failedSources: failed);
  }

  /// Which stubs this pass should fetch: not already imported, newest first,
  /// filtered and capped per [mode].
  static List<ArticleStub> selectForMode(
    List<ArticleStub> stubs,
    Set<String> imported,
    FeedFetchMode mode, {
    DateTime? day,
    int days = 3,
    DateTime? now,
  }) {
    final fresh = stubs.where((s) => !imported.contains(s.sourceUrl)).toList()
      ..sort((a, b) => (b.publishedAt ?? 0).compareTo(a.publishedAt ?? 0));
    switch (mode) {
      case FeedFetchMode.today:
        final dated = fresh.where((s) => s.publishedAt != null).toList();
        // A feed with no timestamps at all still has to do something useful.
        if (dated.isEmpty) return fresh.take(10).toList();
        final now = DateTime.now();
        final todayStart =
            DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
        var chosen =
            dated.where((s) => s.publishedAt! >= todayStart).toList();
        if (chosen.isEmpty) {
          // Today's edition isn't out yet (NHK Easy publishes on a lag, and
          // a feed can simply be quiet). Give the reader the latest edition
          // instead — everything from the newest day the feed carries —
          // rather than an empty paper.
          chosen = _sameDayAs(dated, dated.first.publishedAt!);
        }
        return chosen.take(maxPerSource).toList();
      case FeedFetchMode.latest10:
        return fresh.take(10).toList();
      case FeedFetchMode.latest30:
        return fresh.take(30).toList();
      case FeedFetchMode.day:
        if (day == null) return const [];
        return _sameDayAs(
                fresh.where((s) => s.publishedAt != null).toList(),
                DateTime(day.year, day.month, day.day).millisecondsSinceEpoch)
            .take(maxPerSource)
            .toList();
      case FeedFetchMode.window:
        final dated = fresh.where((s) => s.publishedAt != null).toList();
        if (dated.isEmpty) return fresh.take(10).toList();
        var start = windowStart(days, now).millisecondsSinceEpoch;
        // A feed that's gone quiet for the whole window (NHK Easy lags) still
        // offers its latest edition, as in today; pruning keeps it the same way.
        final newest = stubs
            .map((s) => s.publishedAt ?? 0)
            .fold<int>(0, (a, b) => a > b ? a : b);
        if (newest > 0 && newest < start) start = dayStart(newest);
        return dated
            .where((s) => s.publishedAt! >= start)
            .take(maxPerWindow)
            .toList();
    }
  }

  /// What's on offer, grouped by the day it was filed.
  ///
  /// Lists every source once and buckets the stories not already imported by
  /// publication day, newest first. This is what makes fetching orderly: you
  /// pick "8月30日, 14 stories" instead of "the latest N of whatever the
  /// wires happen to be carrying".
  Future<List<DayAvailability>> survey({
    required List<FeedSource> sources,
    void Function(FeedSyncProgress)? onProgress,
  }) async {
    final byDay = <int, DayAvailability>{};
    for (final source in sources) {
      try {
        onProgress?.call(FeedSyncProgress(source.name, 0, 0));
        final stubs = await source.list();
        final imported = await _imported(source.id);
        for (final stub in stubs) {
          final at = stub.publishedAt;
          if (at == null) continue;
          final d = DateTime.fromMillisecondsSinceEpoch(at);
          final key =
              DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
          final entry = byDay[key] ??= DayAvailability(day: DateTime(d.year, d.month, d.day));
          entry._total++;
          if (!imported.contains(stub.sourceUrl)) entry._available++;
        }
      } catch (_) {
        // A paper that won't answer just doesn't contribute back issues.
      }
    }
    final out = byDay.values.toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    return out;
  }

  /// Local midnight of the day containing [epochMs].
  static int dayStart(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
  }

  /// Every stub published on the same calendar day as [epochMs].
  static List<ArticleStub> _sameDayAs(List<ArticleStub> stubs, int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final start = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    final end = start + const Duration(days: 1).inMilliseconds;
    return stubs
        .where((s) => s.publishedAt! >= start && s.publishedAt! < end)
        .toList();
  }
}
