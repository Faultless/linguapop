import 'package:flutter_test/flutter_test.dart';
import 'package:linguapop/services/sources/news_image_store.dart';
import 'package:linguapop/services/sources/source_import.dart';

void main() {
  group('absoluteImageUrl', () {
    const article = 'https://mainichi.jp/articles/20260831/k00/00m/020/033000c';

    test('passes absolute URLs through', () {
      expect(absoluteImageUrl('https://x.jp/a.jpg', article),
          'https://x.jp/a.jpg');
    });

    test('upgrades protocol-relative URLs', () {
      expect(absoluteImageUrl('//cdn.x.jp/a.jpg', article),
          'https://cdn.x.jp/a.jpg');
    });

    test('resolves a path against the article it came from', () {
      expect(absoluteImageUrl('/img/a.jpg', article),
          'https://mainichi.jp/img/a.jpg');
    });

    test('keeps data URIs', () {
      expect(absoluteImageUrl('data:image/png;base64,AAA', article),
          'data:image/png;base64,AAA');
    });

    test('gives up rather than storing something unrenderable', () {
      expect(absoluteImageUrl(null, article), isNull);
      expect(absoluteImageUrl('  ', article), isNull);
      expect(absoluteImageUrl('/img/a.jpg', null), isNull);
      expect(absoluteImageUrl('/img/a.jpg', 'not a url'), isNull);
    });
  });

  group('NewsImageStore addressing', () {
    test('recognises and unwraps its own scheme', () {
      expect(NewsImageStore.isLocal('local:abc'), isTrue);
      expect(NewsImageStore.isLocal('https://x.jp/a.jpg'), isFalse);
      expect(NewsImageStore.isLocal(null), isFalse);
      expect(NewsImageStore.keyOf('local:abc'), 'abc');
    });
  });
}
