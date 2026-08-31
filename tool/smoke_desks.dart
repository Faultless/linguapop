import 'package:linguapop/services/sources/session_client.dart';
import 'package:linguapop/services/sources/source_registry.dart';
import 'package:linguapop/services/sources/source_types.dart';

/// Lists, and fetches one article from, every feed source on the newsstand.
Future<void> main() async {
  final client = SessionClient();
  final registry = SourceRegistry(client);
  var bad = 0;
  for (final s in registry.feedSources) {
    try {
      final stubs = await s.list();
      if (stubs.isEmpty) {
        print('✗ ${s.id.padRight(16)} listed 0 articles');
        bad++;
        continue;
      }
      // Try a few: NHK expires individual articles off newsweb, and a batch
      // import skips those, so one 404 at the head of a feed isn't a failure.
      var chars = 0;
      var withImage = 0;
      var fetched = 0;
      for (final st in stubs.take(3)) {
        try {
          final ch = await s.fetch(st);
          if (ch.originalText.trim().length > 40) {
            fetched++;
            chars += ch.originalText.length;
            if (ch.imageUrl != null) withImage++;
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      final ok = fetched > 0;
      print('${ok ? "✓" : "✗"} ${s.id.padRight(16)} '
          '${stubs.length.toString().padLeft(3)} items · '
          '$fetched/3 fetched · ~${fetched == 0 ? 0 : chars ~/ fetched} chars · '
          '$withImage w/ image');
      if (!ok) bad++;
    } catch (e) {
      print('✗ ${s.id.padRight(16)} $e');
      bad++;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  client.close();
  print(bad == 0 ? 'All feed sources OK' : '$bad source(s) failed');
}
