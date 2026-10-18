import 'package:flutter_test/flutter_test.dart';
import 'package:linguapop/services/sources/feed_sync.dart';
import 'package:linguapop/services/sources/news_freshness.dart';
import 'package:linguapop/services/sources/source_types.dart';

ArticleStub stub(String id, DateTime at) => ArticleStub(
      id: id,
      title: 'Story $id',
      sourceUrl: 'https://example.com/$id',
      publishedAt: at.millisecondsSinceEpoch,
    );

void main() {
  final now = DateTime(2026, 10, 18, 9);
  DateTime daysAgo(int n) => DateTime(2026, 10, 18 - n, 8);

  group('window mode', () {
    test('windowStart is midnight N-1 days back', () {
      expect(FeedSync.windowStart(3, now), DateTime(2026, 10, 16));
      expect(FeedSync.windowStart(1, now), DateTime(2026, 10, 18));
    });

    test('takes every unimported story inside the window', () {
      final picked = FeedSync.selectForMode(
        [for (var i = 0; i < 5; i++) stub('d$i', daysAgo(i))],
        {'https://example.com/d1'},
        FeedFetchMode.window,
        days: 3,
        now: now,
      );
      // d1 is the cached yesterday; only today and the day before are fetched.
      expect(picked.map((s) => s.id), ['d0', 'd2']);
    });

    test('a feed quiet for the whole window offers its latest edition', () {
      final picked = FeedSync.selectForMode(
        [stub('old', daysAgo(6)), stub('latest', daysAgo(4))],
        const {},
        FeedFetchMode.window,
        days: 1,
        now: now,
      );
      expect(picked.map((s) => s.id), ['latest']);
    });
  });

  group('isStale', () {
    SyncStamp at(DateTime t, [int days = 3]) =>
        SyncStamp(t.millisecondsSinceEpoch, days);

    test('never synced is stale', () {
      expect(NewsFreshness.isStale(null, 3, now), isTrue);
    });

    test('a sync from yesterday is stale', () {
      expect(NewsFreshness.isStale(at(DateTime(2026, 10, 17, 23)), 3, now),
          isTrue);
    });

    test('a recent sync today is fresh', () {
      expect(NewsFreshness.isStale(at(DateTime(2026, 10, 18, 8)), 3, now),
          isFalse);
    });

    test('an old sync today is stale', () {
      expect(NewsFreshness.isStale(at(DateTime(2026, 10, 18, 6)), 3, now),
          isTrue);
    });

    test('widening the window makes a fresh sync stale', () {
      expect(NewsFreshness.isStale(at(DateTime(2026, 10, 18, 8), 3), 7, now),
          isTrue);
    });
  });
}
