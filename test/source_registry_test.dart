import 'package:flutter_test/flutter_test.dart';
import 'package:linguapop/services/sources/session_client.dart';
import 'package:linguapop/services/sources/source_registry.dart';

void main() {
  late SourceRegistry registry;
  setUp(() => registry = SourceRegistry(SessionClient()));

  group('newsstand', () {
    test('every source id is unique', () {
      final ids = registry.all.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('carries a lot of papers, but only a few by default', () {
      expect(registry.feedSources.length, greaterThanOrEqualTo(10));
      expect(registry.defaultFeedIds.length, lessThan(5));
    });

    test('the ids of pre-desk feeds are unchanged', () {
      // Feed novels are keyed 'feed:<sourceId>', so renaming these would
      // orphan everything a user had already imported.
      final ids = registry.all.map((s) => s.id).toSet();
      expect(ids, containsAll(['nhk-easy', 'nhk-news', 'mainichi']));
    });

    test('the default papers are the flagships, not the desk feeds', () {
      expect(registry.defaultFeedIds.toSet(),
          {'nhk-easy', 'nhk-news', 'mainichi'});
    });

    test('every feed source has a native name for its masthead', () {
      for (final s in registry.feedSources) {
        expect(s.nativeName, isNotNull, reason: '${s.id} has no nativeName');
        expect(s.nativeName, isNotEmpty);
      }
    });

    test('every source describes itself for the source manager', () {
      for (final s in registry.all) {
        expect(s.description, isNotNull, reason: '${s.id} has no description');
      }
    });

    test('byId finds every registered source', () {
      for (final s in registry.all) {
        expect(registry.byId(s.id)?.id, s.id);
      }
      expect(registry.byId('nope'), isNull);
    });
  });
}
