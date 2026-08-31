import 'package:flutter_test/flutter_test.dart';
import 'package:linguapop/services/sources/feed_sync.dart';
import 'package:linguapop/services/sources/source_types.dart';

ArticleStub stub(String id, {DateTime? at}) => ArticleStub(
      id: id,
      title: 'Story $id',
      sourceUrl: 'https://example.com/$id',
      publishedAt: at?.millisecondsSinceEpoch,
    );

void main() {
  final now = DateTime.now();
  final todayMorning = DateTime(now.year, now.month, now.day, 7);
  final midnight = DateTime(now.year, now.month, now.day);
  // Fixed points inside yesterday and the day before, so the fixtures don't
  // straddle a day boundary when the suite runs just after midnight.
  final yesterday = midnight.subtract(const Duration(hours: 5));

  group('selectForMode', () {
    test('skips articles already imported', () {
      final picked = FeedSync.selectForMode(
        [stub('a', at: now), stub('b', at: now)],
        {'https://example.com/a'},
        FeedFetchMode.latest10,
      );
      expect(picked.map((s) => s.id), ['b']);
    });

    test('today keeps only stories published today', () {
      final picked = FeedSync.selectForMode(
        [
          stub('old', at: yesterday),
          stub('new', at: todayMorning),
        ],
        const {},
        FeedFetchMode.today,
      );
      expect(picked.map((s) => s.id), ['new']);
    });

    test('today falls back to the latest edition when today has nothing', () {
      final twoDaysAgo = midnight.subtract(const Duration(hours: 29));
      final picked = FeedSync.selectForMode(
        [
          stub('older', at: twoDaysAgo),
          stub('yesterday-a', at: yesterday),
          stub('yesterday-b', at: midnight.subtract(const Duration(hours: 20))),
        ],
        const {},
        FeedFetchMode.today,
      );
      // The whole of yesterday's edition, and nothing from before it.
      expect(picked.map((s) => s.id).toSet(), {'yesterday-a', 'yesterday-b'});
    });

    test('today falls back to the newest few when the feed has no dates', () {
      final picked = FeedSync.selectForMode(
        [for (var i = 0; i < 25; i++) stub('$i')],
        const {},
        FeedFetchMode.today,
      );
      expect(picked.length, 10);
    });

    test('latest N caps the pass and takes the newest first', () {
      final stubs = [
        for (var i = 0; i < 25; i++)
          stub('$i', at: now.subtract(Duration(minutes: i))),
      ];
      final picked =
          FeedSync.selectForMode(stubs, const {}, FeedFetchMode.latest10);
      expect(picked.length, 10);
      expect(picked.first.id, '0');
      expect(picked.last.id, '9');
    });

    test('one pass never exceeds the per-source ceiling', () {
      final stubs = [
        for (var i = 0; i < 200; i++) stub('$i', at: todayMorning),
      ];
      final picked =
          FeedSync.selectForMode(stubs, const {}, FeedFetchMode.today);
      expect(picked.length, FeedSync.maxPerSource);
    });
  });

  group('result summary', () {
    test('reports what was fetched', () {
      expect(const FeedSyncResult(added: 3, considered: 3).summary,
          'Fetched 3 new stories.');
      expect(const FeedSyncResult(added: 1, considered: 1).summary,
          'Fetched 1 new story.');
    });

    test('distinguishes "nothing new" from "up to date"', () {
      expect(const FeedSyncResult(added: 0, considered: 0).summary,
          'Nothing new to fetch.');
    });

    test('names unreachable sources', () {
      expect(
        const FeedSyncResult(
                added: 2, considered: 2, failedSources: ['Mainichi'])
            .summary,
        contains('Mainichi unreachable'),
      );
    });

    test('a cancelled pass says so', () {
      expect(const FeedSyncResult(added: 2, considered: 9, cancelled: true)
          .summary, 'Stopped after 2 stories.');
    });
  });
}
