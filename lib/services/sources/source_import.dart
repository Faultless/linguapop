import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../data/models/chapter.dart';
import '../../data/models/novel.dart';
import '../../providers/novels_provider.dart';
import '../dictionary/jlpt_estimator.dart';
import 'news_image_store.dart';
import 'source_types.dart';
import 'syosetu.dart';

const _uuid = Uuid();

/// Live status of an in-progress source import. Surfaced to the UI so the
/// user gets a progress bar + cancel button while long Syosetu novels fetch.
class ImportTask {
  final String taskId;
  final String sourceLabel;
  final String title;
  /// 0..1 progress; null while the work hasn't started or has indeterminate
  /// progress (e.g. listing chapters).
  double? progress;
  String status;
  bool _cancelled = false;

  ImportTask({
    required this.taskId,
    required this.sourceLabel,
    required this.title,
    this.progress,
    this.status = 'Preparing…',
  });

  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class SourceImporter {
  final NovelsNotifier _novels;

  /// Downloads article images through the adapters' authenticated client.
  /// Null when image capture isn't wanted (tests).
  final NewsImageStore? _images;

  /// Scores each article's difficulty once, at import, so the front page
  /// never has to run the tokenizer while the reader is scrolling.
  final JlptEstimator? _estimator;

  SourceImporter(this._novels, [this._images, this._estimator]);

  Future<void> _scoreDifficulty(Chapter chapter) async {
    if (_estimator == null) return;
    try {
      chapter.jlptStats = await _estimator.estimate(chapter.originalText);
    } catch (_) {
      // A cold or unavailable tokenizer just means the badge estimates later.
    }
  }

  /// Resolve a chapter's lead image to something that will actually render:
  /// absolute, and — where the host needs the feed's session cookie — pulled
  /// down now and stored locally. Clears the URL when neither works, so the
  /// front page shows a text-only story instead of a broken box.
  Future<void> _settleImage(Chapter chapter, ArticleStub stub) async {
    chapter.imageUrl ??= stub.imageUrl;
    final url = absoluteImageUrl(
        chapter.imageUrl, chapter.sourceUrl ?? stub.sourceUrl);
    if (url == null || _images == null || url.startsWith(NewsImageStore.scheme)) {
      chapter.imageUrl = url;
      return;
    }
    chapter.imageUrl = await _images.capture(url, '${stub.id}-${url.hashCode}');
  }

  /// Import a single NHK Easy-style article into a rolling "feed" novel
  /// keyed by `sourceId`. Re-importing the same article is a no-op.
  Future<String> importArticle({
    required FeedSource source,
    required ArticleStub stub,
  }) async {
    final chapter = await source.fetch(stub);
    await _settleImage(chapter, stub);
    await _scoreDifficulty(chapter);
    final feedNovelId = 'feed:${source.id}';

    // Try to find an existing rolling novel for this feed.
    final existing = _novels.findById(feedNovelId);
    if (existing != null) {
      // Dedup by sourceUrl — already imported.
      final body = await _novels.loadBody(feedNovelId);
      if (body == null) {
        // Re-create from scratch if body went missing.
        await _createFeedNovel(feedNovelId, source, [chapter]);
        return feedNovelId;
      }
      if (body.chapters.any((c) => c.sourceUrl == chapter.sourceUrl)) {
        return feedNovelId;
      }
      // Prepend new article so the latest is on top.
      final updated = NovelBody(
        id: feedNovelId,
        chapters: [chapter, ...body.chapters],
      );
      await _novels.saveBody(updated);
      await _novels.updateMeta(existing.copyWith(
        chapterCount: updated.chapters.length,
      ));
      return feedNovelId;
    }

    await _createFeedNovel(feedNovelId, source, [chapter]);
    return feedNovelId;
  }

  /// Import a run of articles from one feed in a single library write.
  ///
  /// Importing one at a time meant one Hive write and one provider
  /// invalidation per article, so a ten-article sync rebuilt the front page
  /// ten times while the user was looking at it. Here the network work happens
  /// first and the whole batch is committed once, so the page updates exactly
  /// once per source.
  ///
  /// Individual fetch failures are skipped rather than aborting the batch.
  /// Returns the number of articles actually added.
  Future<int> importArticles({
    required FeedSource source,
    required List<ArticleStub> stubs,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    final fetched = <Chapter>[];
    for (var i = 0; i < stubs.length; i++) {
      if (isCancelled?.call() ?? false) break;
      onProgress?.call(i + 1, stubs.length);
      try {
        final chapter = await source.fetch(stubs[i]);
        await _settleImage(chapter, stubs[i]);
        await _scoreDifficulty(chapter);
        fetched.add(chapter);
      } catch (_) {
        // One unreachable article shouldn't cost the reader the other nine.
      }
      if (i < stubs.length - 1) await Future<void>.delayed(delay);
    }
    if (fetched.isEmpty) return 0;

    final feedNovelId = 'feed:${source.id}';
    final existing = _novels.findById(feedNovelId);
    final body = existing == null ? null : await _novels.loadBody(feedNovelId);
    if (existing == null || body == null) {
      await _createFeedNovel(feedNovelId, source, fetched);
      return fetched.length;
    }
    final have = {
      for (final c in body.chapters)
        if (c.sourceUrl != null) c.sourceUrl!,
    };
    final fresh = <Chapter>[];
    for (final c in fetched) {
      if (c.sourceUrl != null && !have.add(c.sourceUrl!)) continue;
      fresh.add(c);
    }
    if (fresh.isEmpty) return 0;
    final updated = NovelBody(
      id: feedNovelId,
      chapters: [...fresh, ...body.chapters],
    );
    await _novels.saveBody(updated);
    await _novels.updateMeta(
        existing.copyWith(chapterCount: updated.chapters.length));
    return fresh.length;
  }

  /// Remove a single article (by its sourceUrl) from a feed's rolling novel.
  /// Deletes the rolling novel entirely when its last article is removed.
  Future<void> removeArticle({
    required String sourceId,
    required String sourceUrl,
  }) async {
    final feedNovelId = 'feed:$sourceId';
    final body = await _novels.loadBody(feedNovelId);
    if (body == null) return;
    final remaining =
        body.chapters.where((c) => c.sourceUrl != sourceUrl).toList();
    if (remaining.length == body.chapters.length) return; // not present
    for (final c in body.chapters) {
      if (c.sourceUrl == sourceUrl) await NewsImageStore.forget(c.imageUrl);
    }
    if (remaining.isEmpty) {
      await _novels.remove(feedNovelId);
      return;
    }
    await _novels.saveBody(NovelBody(id: feedNovelId, chapters: remaining));
    final meta = _novels.findById(feedNovelId);
    if (meta != null) {
      await _novels.updateMeta(meta.copyWith(
        chapterCount: remaining.length,
        lastReadChapter:
            meta.lastReadChapter.clamp(0, remaining.length - 1),
      ));
    }
  }

  /// Id of the imported book whose `sourceUrl` matches, or null.
  String? findBookIdByUrl(String url) {
    for (final m in _novels.all) {
      if (m.sourceUrl == url && m.sourceType == SourceType.web) return m.id;
    }
    return null;
  }

  /// Remove an imported web book by its source URL. No-op when not found.
  Future<void> removeBookByUrl(String url) async {
    final id = findBookIdByUrl(url);
    if (id != null) await _novels.remove(id);
  }

  Future<void> _createFeedNovel(
      String feedNovelId, FeedSource source, List<Chapter> chapters) async {
    final meta = NovelMeta(
      id: feedNovelId,
      title: source.name,
      author: null,
      sourceLanguage: source.language,
      targetLanguage: 'en',
      chapterCount: chapters.length,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      contentType: source.contentType,
      sourceType: SourceType.feed,
      sourceId: source.id,
      sourceUrl: source.homepageUrl,
    );
    await _novels.add(meta, NovelBody(id: feedNovelId, chapters: chapters));
  }

  /// Import an entire Syosetu-style book. Returns the new novel id when the
  /// import completes. The task's progress field updates as chapters arrive;
  /// callers should re-render whenever progress changes.
  ///
  /// [onTaskUpdate] is fired on every meaningful state change (status text or
  /// progress). [task] is created externally so the UI can hold a reference
  /// and call [ImportTask.cancel].
  Future<String> importBook({
    required SearchSource source,
    required BookStub book,
    required ImportTask task,
    required void Function(ImportTask) onTaskUpdate,
  }) async {
    task.status = 'Listing chapters…';
    onTaskUpdate(task);
    final stubs = await source.listChapters(book);
    if (stubs.isEmpty) {
      throw StateError(
          'Could not list chapters for "${book.title}" — the source layout may have changed.');
    }
    final chapters = <Chapter>[];
    task.progress = 0;
    task.status = '0 / ${stubs.length}';
    onTaskUpdate(task);

    final delayMs = source is SyosetuSource
        ? SyosetuSource.chapterFetchDelayMs
        : 100;

    for (var i = 0; i < stubs.length; i++) {
      if (task.isCancelled) {
        throw _CancelledError();
      }
      final c = await source.fetchChapter(book, stubs[i]);
      chapters.add(c);
      task.progress = (i + 1) / stubs.length;
      task.status = '${i + 1} / ${stubs.length}';
      onTaskUpdate(task);
      if (i < stubs.length - 1) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }

    final id = _uuid.v4();
    final meta = NovelMeta(
      id: id,
      title: book.title,
      author: book.author,
      coverUrl: book.imageUrl,
      sourceLanguage: source.language,
      targetLanguage: 'en',
      chapterCount: chapters.length,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      contentType: source.contentType,
      sourceType: SourceType.web,
      sourceId: source.id,
      sourceUrl: book.url,
      tags: book.tags.toList(),
    );
    await _novels.add(meta, NovelBody(id: id, chapters: chapters));
    return id;
  }
}

/// Resolve a feed-supplied image reference against the article it came from.
/// Returns null for anything that can't be made into an absolute http(s) URL.
String? absoluteImageUrl(String? raw, String? articleUrl) {
  final v = raw?.trim();
  if (v == null || v.isEmpty) return null;
  if (v.startsWith('http://') || v.startsWith('https://')) return v;
  if (v.startsWith('data:')) return v;
  if (v.startsWith('//')) return 'https:$v';
  if (articleUrl == null) return null;
  final base = Uri.tryParse(articleUrl);
  if (base == null || !base.hasScheme) return null;
  return base.resolve(v).toString();
}

class _CancelledError implements Exception {
  @override
  String toString() => 'Import cancelled';
}

