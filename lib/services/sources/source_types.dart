import '../../data/models/chapter.dart';
import '../../data/models/novel.dart' show ContentType;

/// Pluggable adapter interface for "browse-and-import" content sources.
///
/// Two adapter shapes (discriminated by [Source.kind]):
///
///   * **feed** — like NHK Easy. [FeedSource.list] returns the latest items;
///     each item becomes one chapter inside a shared, rolling feed-typed
///     novel. Re-importing dedupes by `sourceUrl`.
///
///   * **search** — like Syosetu. [SearchSource.search] returns book stubs;
///     each book has many chapters fetched via [SearchSource.listChapters]
///     plus [SearchSource.fetchChapter]. Importing creates one new novel.
abstract class Source {
  /// Stable adapter id; persisted into `NovelMeta.sourceId`.
  String get id;
  String get name;
  String? get description;
  /// ISO 639-1 source language code.
  String get language;
  ContentType get contentType;
  String? get homepageUrl;

  /// The outlet's name in its own script, used for the front-page masthead.
  /// Null falls back to [name].
  String? get nativeName => null;

  /// Whether a fresh install carries this source. The desk feeds (NHK 政治,
  /// 毎日 オピニオン, …) are off by default so the newsstand starts small;
  /// they're switched on in the source manager.
  bool get enabledByDefault => true;
}

abstract class FeedSource extends Source {
  /// Fetch the latest items.
  Future<List<ArticleStub>> list();
  /// Resolve one stub to a ready-to-store [Chapter].
  Future<Chapter> fetch(ArticleStub stub);
}

class ArticleStub {
  final String id;
  final String title;
  final String sourceUrl;
  final int? publishedAt; // ms-since-epoch
  final String? summary;
  final String? imageUrl;
  const ArticleStub({
    required this.id,
    required this.title,
    required this.sourceUrl,
    this.publishedAt,
    this.summary,
    this.imageUrl,
  });
}

abstract class SearchSource extends Source {
  /// Optional genre options surfaced in the search UI.
  List<GenreOption> get genres => const [];
  Future<List<BookStub>> search(SearchQuery query);
  Future<List<ChapterStub>> listChapters(BookStub book);
  Future<Chapter> fetchChapter(BookStub book, ChapterStub chapter);
}

enum SearchOrder { rating, bookmarks, weekly, newest, oldest, longest, shortest }
enum CompletionFilter { any, complete, ongoing }
enum LengthFilter { any, short, medium, long }

class SearchQuery {
  final String? word;
  final List<int> genres;
  final CompletionFilter completion;
  final LengthFilter length;
  final SearchOrder order;
  final int limit;
  final int offset;
  const SearchQuery({
    this.word,
    this.genres = const [],
    this.completion = CompletionFilter.any,
    this.length = LengthFilter.any,
    this.order = SearchOrder.rating,
    this.limit = 20,
    this.offset = 0,
  });
}

class BookStub {
  final String id;
  final String title;
  final String? author;
  final String? summary;
  final int? chapterCount;
  final int? charCount;
  final bool? isComplete;
  final String? url;
  final String? imageUrl;
  final List<String> tags;
  final Map<String, Object> extra;
  const BookStub({
    required this.id,
    required this.title,
    this.author,
    this.summary,
    this.chapterCount,
    this.charCount,
    this.isComplete,
    this.url,
    this.imageUrl,
    this.tags = const [],
    this.extra = const {},
  });
}

class ChapterStub {
  final String id;
  final String title;
  final String sourceUrl;
  final int? publishedAt;
  final String? groupTitle;
  const ChapterStub({
    required this.id,
    required this.title,
    required this.sourceUrl,
    this.publishedAt,
    this.groupTitle,
  });
}

class GenreOption {
  final int id;
  final String label;
  const GenreOption({required this.id, required this.label});
}
