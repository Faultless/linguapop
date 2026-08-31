import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/novel.dart' show SourceType;
import '../services/sources/feed_sync.dart';
import '../services/sources/session_client.dart';
import '../services/sources/source_import.dart';
import '../services/sources/source_registry.dart';
import 'novels_provider.dart';

/// Single long-lived HTTP client used by all source adapters in the app.
/// Holds cookie state across calls — important for NHK Easy's session
/// handshake. Disposed implicitly when the app exits.
final sessionClientProvider = Provider<SessionClient>((ref) {
  final client = SessionClient();
  ref.onDispose(client.close);
  return client;
});

final sourceRegistryProvider = Provider<SourceRegistry>(
    (ref) => SourceRegistry(ref.read(sessionClientProvider)));

final sourceImporterProvider = Provider<SourceImporter>(
    (ref) => SourceImporter(ref.read(novelsProvider.notifier)));

/// Bulk feed fetcher ("today's paper", "latest 10") shared by the news hub
/// and the browse screen.
final feedSyncProvider = Provider<FeedSync>((ref) => FeedSync(
      ref.read(sourceImporterProvider),
      (sourceId) => ref.read(importedArticleUrlsProvider(sourceId).future),
    ));

/// Source URLs of every article already imported into the rolling feed novel
/// of the given feed source. Recomputes whenever the library changes, so
/// "added" checkmarks in the browse UI stay in sync.
final importedArticleUrlsProvider =
    FutureProvider.family<Set<String>, String>((ref, sourceId) async {
  ref.watch(novelsProvider); // invalidate on any library mutation
  final body =
      await ref.read(novelsProvider.notifier).loadBody('feed:$sourceId');
  if (body == null) return const <String>{};
  return {
    for (final c in body.chapters)
      if (c.sourceUrl != null) c.sourceUrl!,
  };
});

/// Source URLs of every imported web book (Syosetu etc.).
final importedBookUrlsProvider = Provider<Set<String>>((ref) {
  final metas = ref.watch(novelsProvider);
  return {
    for (final m in metas)
      if (m.sourceUrl != null && m.sourceType == SourceType.web) m.sourceUrl!,
  };
});
