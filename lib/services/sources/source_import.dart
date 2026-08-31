import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../data/models/chapter.dart';
import '../../data/models/novel.dart';
import '../../providers/novels_provider.dart';
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
  SourceImporter(this._novels);

  /// Import a single NHK Easy-style article into a rolling "feed" novel
  /// keyed by `sourceId`. Re-importing the same article is a no-op.
  Future<String> importArticle({
    required FeedSource source,
    required ArticleStub stub,
  }) async {
    final chapter = await source.fetch(stub);
    // Fall back to the stub's image when the adapter didn't set one from the
    // article page itself, then make sure whatever we ended up with is an
    // absolute URL — feed payloads carry relative and protocol-relative
    // paths, which Image.network can't load.
    chapter.imageUrl ??= stub.imageUrl;
    chapter.imageUrl =
        absoluteImageUrl(chapter.imageUrl, chapter.sourceUrl ?? stub.sourceUrl);
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

