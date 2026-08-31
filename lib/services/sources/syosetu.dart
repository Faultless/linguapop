import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import '../../data/models/chapter.dart';
import '../../data/models/novel.dart' show ContentType;
import 'session_client.dart';
import 'source_types.dart';

const _apiUrl = 'https://api.syosetu.com/novelapi/api/';
const _siteBase = 'https://ncode.syosetu.com';
const _homepage = 'https://syosetu.com/';

const _genres = <GenreOption>[
  GenreOption(id: 1, label: '恋愛 — Romance'),
  GenreOption(id: 2, label: 'ファンタジー — Fantasy'),
  GenreOption(id: 3, label: '文芸 — Literary'),
  GenreOption(id: 4, label: 'SF'),
  GenreOption(id: 99, label: 'その他 — Other'),
  GenreOption(id: 98, label: 'ノンジャンル — Non-genre'),
];

const _orderMap = <SearchOrder, String>{
  SearchOrder.rating: 'hyoka',
  SearchOrder.bookmarks: 'favnovelcnt',
  SearchOrder.weekly: 'weekly',
  SearchOrder.newest: 'new',
  SearchOrder.oldest: 'old',
  SearchOrder.longest: 'lengthdesc',
  SearchOrder.shortest: 'lengthasc',
};

class SyosetuSource extends SearchSource {
  final SessionClient _client;
  SyosetuSource(this._client);

  @override
  String get id => 'syosetu';
  @override
  String get name => 'Syosetu (小説家になろう)';

  @override
  String? get nativeName => '小説家になろう';
  @override
  String? get description =>
      'Largest Japanese web-novel platform — 1M+ works, free, no signup';
  @override
  String get language => 'ja';
  @override
  ContentType get contentType => ContentType.webNovel;
  @override
  String? get homepageUrl => _homepage;
  @override
  List<GenreOption> get genres => _genres;

  /// Default delay between consecutive chapter fetches (ms). Syosetu doesn't
  /// publish a rate limit, but ~600ms keeps us comfortably under what looks
  /// like the IP-throttle threshold and is friendly to other readers.
  static const int chapterFetchDelayMs = 600;

  @override
  Future<List<BookStub>> search(SearchQuery query) async {
    final p = <String, String>{
      'out': 'json',
      'lim': query.limit.clamp(1, 500).toString(),
      'order': _orderMap[query.order] ?? 'hyoka',
    };
    if (query.offset > 0) p['st'] = (query.offset + 1).toString();
    if (query.word != null && query.word!.trim().isNotEmpty) {
      p['word'] = query.word!.trim();
    }
    if (query.genres.isNotEmpty) {
      p['biggenre'] = query.genres.join('-');
    }
    switch (query.completion) {
      case CompletionFilter.complete:
        p['type'] = 'er';
      case CompletionFilter.ongoing:
        p['type'] = 'r';
      case CompletionFilter.any:
        p['type'] = 'ter';
    }
    switch (query.length) {
      case LengthFilter.short:
        p['length'] = '-30000';
      case LengthFilter.medium:
        p['length'] = '30000-100000';
      case LengthFilter.long:
        p['length'] = '100000-';
      case LengthFilter.any:
        break;
    }
    final url = Uri.parse(_apiUrl).replace(queryParameters: p);
    final res = await _client.get(url);
    if (!res.ok) {
      throw Exception('Syosetu API HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! List || decoded.length < 2) return const [];
    final works = decoded.sublist(1);
    final out = <BookStub>[];
    for (final raw in works) {
      if (raw is! Map) continue;
      final ncode = raw['ncode'] as String?;
      final title = raw['title'] as String?;
      if (ncode == null || title == null) continue;
      out.add(_workToStub(Map<String, dynamic>.from(raw)));
    }
    return out;
  }

  @override
  Future<List<ChapterStub>> listChapters(BookStub book) async {
    final isSerial = book.extra['isSerial'] == true;
    if (!isSerial) {
      // Short stories (novel_type === 2) live at the root URL with no /1/ suffix.
      return [
        ChapterStub(
          id: '1',
          title: book.title,
          sourceUrl: _rootUrl(book),
        )
      ];
    }
    final res = await _client.get(Uri.parse(_rootUrl(book)));
    if (!res.ok) {
      throw Exception('Syosetu TOC HTTP ${res.statusCode}');
    }
    final doc = html_parser.parse(res.body);
    final stubs = <ChapterStub>[];
    String? currentGroup;
    final candidates = doc.querySelectorAll(
        '.p-eplist__chapter-title, .p-eplist__sublist');
    for (final el in candidates) {
      if (el.classes.contains('p-eplist__chapter-title')) {
        final t = el.text.trim();
        currentGroup = t.isEmpty ? null : t;
        continue;
      }
      final link = el.querySelector('a.p-eplist__subtitle');
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      final m = RegExp(r'\/[a-z0-9]+\/(\d+)\/?$', caseSensitive: false)
          .firstMatch(href);
      if (m == null) continue;
      final chapterId = m.group(1)!;
      final updateEl = el.querySelector('.p-eplist__update');
      stubs.add(ChapterStub(
        id: chapterId,
        title: link.text.trim(),
        sourceUrl: '$_siteBase/${book.id.toLowerCase()}/$chapterId/',
        groupTitle: currentGroup,
        publishedAt: _parseSyosetuDate(updateEl?.text),
      ));
    }
    // Defensive fallback: TOC selector drifted but the book reports a count.
    if (stubs.isEmpty && (book.chapterCount ?? 0) > 0) {
      for (var i = 1; i <= book.chapterCount!; i++) {
        stubs.add(ChapterStub(
          id: '$i',
          title: '第$i話',
          sourceUrl: '$_siteBase/${book.id.toLowerCase()}/$i/',
        ));
      }
    }
    return stubs;
  }

  @override
  Future<Chapter> fetchChapter(BookStub book, ChapterStub chapter) async {
    final res = await _client.get(Uri.parse(chapter.sourceUrl));
    if (!res.ok) {
      throw Exception(
          'Syosetu chapter HTTP ${res.statusCode} for ${chapter.sourceUrl}');
    }
    final doc = html_parser.parse(res.body);
    final titleEl = doc.querySelector('.p-novel__title') ??
        doc.querySelector('.novel_subtitle');
    final pageTitle = titleEl?.text.trim();
    final containers = doc.querySelectorAll('.p-novel__text');
    final parts = <String>[];
    for (final c in containers) {
      for (final r in c.querySelectorAll('rt, rp')) {
        r.remove();
      }
      final paras = <String>[];
      for (final p in c.querySelectorAll('p')) {
        // Normalize ideographic spaces (U+3000) → ASCII space.
        final t = p.text.replaceAll('　', ' ').trim();
        if (t.isNotEmpty) paras.add(t);
      }
      if (paras.isNotEmpty) parts.add(paras.join('\n\n'));
    }
    final text = parts.join('\n\n');
    if (text.isEmpty) {
      throw Exception('Empty chapter body at ${chapter.sourceUrl}');
    }
    final finalTitle = (pageTitle?.isNotEmpty ?? false)
        ? pageTitle!
        : chapter.title.isNotEmpty
            ? chapter.title
            : '第${chapter.id}話';
    return Chapter(
      id: '${book.id}:${chapter.id}',
      title: finalTitle,
      originalText: text,
      sourceUrl: chapter.sourceUrl,
      publishedAt: chapter.publishedAt,
    );
  }
}

BookStub _workToStub(Map<String, dynamic> w) {
  final ncode = (w['ncode'] as String).toUpperCase();
  final ncodeLower = ncode.toLowerCase();
  final keyword = (w['keyword'] as String?) ?? '';
  return BookStub(
    id: ncode,
    title: ((w['title'] as String?) ?? '').trim(),
    author: (w['writer'] as String?)?.trim(),
    summary: (w['story'] as String?)?.trim(),
    chapterCount: (w['general_all_no'] as num?)?.toInt(),
    charCount: (w['length'] as num?)?.toInt(),
    isComplete: (w['end'] as num?)?.toInt() != 1,
    url: '$_siteBase/$ncodeLower/',
    imageUrl: 'https://sbo.syosetu.com/$ncodeLower/twitter.png',
    tags: keyword
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .take(8)
        .toList(),
    extra: {
      'rating': (w['global_point'] as num?)?.toDouble() ?? 0.0,
      'bookmarks': (w['fav_novel_cnt'] as num?)?.toInt() ?? 0,
      'isSerial': (w['novel_type'] as num?)?.toInt() == 1,
    },
  );
}

String _rootUrl(BookStub book) => '$_siteBase/${book.id.toLowerCase()}/';

int? _parseSyosetuDate(String? s) {
  if (s == null) return null;
  // "2024/05/23 13:45" — assumed JST.
  final m = RegExp(r'(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2})')
      .firstMatch(s);
  if (m == null) return null;
  final iso = '${m.group(1)}-${m.group(2)}-${m.group(3)}T'
      '${m.group(4)}:${m.group(5)}:00+09:00';
  return DateTime.tryParse(iso)?.millisecondsSinceEpoch;
}
