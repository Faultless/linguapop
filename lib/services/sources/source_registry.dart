import 'mainichi.dart';
import 'nhk_easy.dart';
import 'nhk_news.dart';
import 'session_client.dart';
import 'source_types.dart';
import 'syosetu.dart';

/// Built-in source adapters. Order is the order shown in the picker.
class SourceRegistry {
  final SessionClient _client;
  /// The newsstand. NHK Easy and the two flagship feeds are carried by
  /// default; the desk feeds are here to be switched on in the source
  /// manager, so the stand starts readable rather than exhaustive.
  late final List<Source> all = [
    NhkEasySource(_client),
    for (final desk in NhkDesk.all) NhkNewsSource(_client, desk: desk),
    for (final desk in MainichiDesk.all) MainichiSource(_client, desk: desk),
    SyosetuSource(_client),
  ];

  /// Ids a fresh install carries.
  Iterable<String> get defaultFeedIds =>
      feedSources.where((s) => s.enabledByDefault).map((s) => s.id);

  SourceRegistry(this._client);

  Iterable<SearchSource> get searchSources =>
      all.whereType<SearchSource>();
  Iterable<FeedSource> get feedSources => all.whereType<FeedSource>();

  Source? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }
}
