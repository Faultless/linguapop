import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:linguapop/services/sources/feed_sync.dart';
import 'package:linguapop/services/sources/news_freshness.dart';
import 'package:linguapop/services/sources/nhk_news.dart';
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

  test('window caps each day, so a busy day leaves room for the rest', () {
    final picked = FeedSync.selectForMode(
      [
        for (var i = 0; i < 30; i++) stub('t$i', daysAgo(0)),
        for (var i = 0; i < 5; i++) stub('y$i', daysAgo(1)),
      ],
      const {},
      FeedFetchMode.window,
      days: 3,
      now: now,
    );
    expect(picked.where((s) => s.id.startsWith('t')).length, FeedSync.maxPerDay);
    expect(picked.where((s) => s.id.startsWith('y')).length, 5);
  });

  group('NHK playlist', () {
    const body = '第一段落の本文です。これは十分に長い記事の本文になるように書かれています。'
        '\n\n\n第二段落です。ここにも本文が続きます。さらに文章を足して八十文字を超えるようにします。';
    final json = '''{"count":2,"result":[
      {"id":"nd-20261018de61247","headline":"見出し","datePublished":"2026-10-18T19:00:32+09:00",
       "canonical":"https://news.web.nhk/newsweb/na/nd-20261018de61247",
       "image":{"icon":{"url":"https://imgu.web.nhk/s.jpg"},"medium":{"url":"https://imgu.web.nhk/l.jpg"}},
       "articleBody":${jsonEncode(body)}},
      {"id":"nd-flash","headline":"速報","datePublished":"2026-10-18T19:00:32+09:00","articleBody":"短い"}
    ]}''';

    test('carries the body, normalised to one blank line per paragraph', () {
      final stubs = NhkNewsSource.parsePlaylist(json);
      expect(stubs.map((s) => s.id), ['nd-20261018de61247']);
      final s = stubs.single;
      expect(s.body!.split('\n\n'), hasLength(2));
      expect(s.imageUrl, 'https://imgu.web.nhk/s.jpg');
      expect(s.sourceUrl, 'https://news.web.nhk/newsweb/na/nd-20261018de61247');
      expect(s.publishedAt,
          DateTime.parse('2026-10-18T19:00:32+09:00').millisecondsSinceEpoch);
    });
  });

  group('isStale', () {
    test('a stamp from an older sync version is stale', () {
      expect(
          NewsFreshness.isStale(
              SyncStamp(DateTime(2026, 10, 18, 8).millisecondsSinceEpoch, 3, 1),
              3,
              now),
          isTrue);
    });

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
