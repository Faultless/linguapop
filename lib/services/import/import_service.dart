import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/chapter.dart';
import '../../data/models/novel.dart';
import '../../providers/novels_provider.dart';
import '../../providers/prefs_provider.dart';
import 'epub_importer.dart';
import 'jp_detect.dart';
import 'novel_cleaner.dart';
import 'txt_importer.dart';

const _uuid = Uuid();

class ImportResult {
  final String novelId;
  final String title;
  final int chapterCount;
  const ImportResult({
    required this.novelId,
    required this.title,
    required this.chapterCount,
  });
}

class ImportService {
  final NovelsNotifier _novels;

  /// Whether the reader has opted in to online cover lookups.
  final bool Function() _fetchCovers;
  ImportService(this._novels, [this._fetchCovers = _never]);

  static bool _never() => false;

  Future<ImportResult> importFile({
    required String filename,
    required Uint8List bytes,
    Uint8List? translationBytes,
    String? translationFilename,
  }) async {
    final isEpub = filename.toLowerCase().endsWith('.epub');
    final isTxt = filename.toLowerCase().endsWith('.txt');
    if (!isEpub && !isTxt) {
      throw FormatException(
          'Unsupported file type: $filename (only .epub and .txt)');
    }

    final parsed = isEpub
        ? _fromEpub(bytes)
        : _fromTxt(bytes, filename);
    var chapters = pruneNovel(parsed.chapters);
    if (chapters.isEmpty) {
      // Be forgiving — if the cleanup killed everything (e.g. short stories),
      // fall back to the raw chapter list.
      chapters = parsed.chapters;
    }

    // Optional paired translation.
    if (translationBytes != null && translationFilename != null) {
      final isTransEpub = translationFilename.toLowerCase().endsWith('.epub');
      final transParsed = isTransEpub
          ? _fromEpub(translationBytes)
          : _fromTxt(translationBytes, translationFilename);
      final transChapters = pruneNovel(transParsed.chapters);
      chapters = alignChapters(chapters,
          transChapters.isEmpty ? transParsed.chapters : transChapters);
    }

    final sampleText = chapters.isEmpty ? '' : chapters.first.originalText;
    final isJa = (parsed.language?.toLowerCase().startsWith('ja') ?? false) ||
        looksJapanese(sampleText);

    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final hasTranslation = chapters.any((c) => c.translatedText != null);

    final meta = NovelMeta(
      id: id,
      title: parsed.title,
      author: parsed.author,
      coverUrl: parsed.coverDataUrl,
      sourceLanguage: isJa ? 'ja' : (parsed.language ?? 'en'),
      targetLanguage: 'en',
      chapterCount: chapters.length,
      addedAt: now,
      lastReadChapter: 0,
      lastReadOffset: 0,
      hasUserTranslation: hasTranslation,
      contentType: ContentType.novel,
      sourceType: isEpub ? SourceType.epub : SourceType.txt,
    );

    await _novels.add(meta, NovelBody(id: id, chapters: chapters));

    // Best-effort online cover lookup for books that didn't ship one (TXT, or
    // EPUBs with no embedded cover). Non-blocking — import succeeds regardless.
    if ((meta.coverUrl == null || meta.coverUrl!.isEmpty) && _fetchCovers()) {
      unawaited(_novels.autoFetchCover(id));
    }

    return ImportResult(
      novelId: id,
      title: parsed.title,
      chapterCount: chapters.length,
    );
  }

  static _Parsed _fromEpub(Uint8List bytes) {
    final p = parseEpub(bytes);
    return _Parsed(
      title: p.title,
      author: p.author,
      language: p.language,
      coverDataUrl: p.coverDataUrl,
      chapters: p.chapters,
    );
  }

  static _Parsed _fromTxt(Uint8List bytes, String filename) {
    final text = decodeText(bytes);
    final base = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return _Parsed(
      title: base.isEmpty ? 'Untitled' : base,
      chapters: splitTxtIntoChapters(text, fallbackTitle: base),
    );
  }

  static String decodeText(Uint8List bytes) {
    // UTF-8 first (BOM stripped); a file that isn't valid UTF-8 falls back to
    // the system encoding, then Latin-1, which never throws.
    try {
      return utf8.decode(bytes).replaceFirst('\uFEFF', '');
    } on FormatException {
      try {
        return systemEncoding.decode(bytes);
      } catch (_) {
        return latin1.decode(bytes);
      }
    }
  }
}

class _Parsed {
  final String title;
  final String? author;
  final String? language;
  final String? coverDataUrl;
  final List<Chapter> chapters;
  const _Parsed({
    required this.title,
    this.author,
    this.language,
    this.coverDataUrl,
    required this.chapters,
  });
}

final importServiceProvider = Provider<ImportService>((ref) {
  return ImportService(ref.read(novelsProvider.notifier),
      () => ref.read(readerPrefsProvider).fetchCoversOnline);
});
