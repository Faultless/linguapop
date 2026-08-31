import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../data/models/chapter.dart';
import '../../data/models/novel.dart' show ContentType;
import 'nhk_auth.dart';
import 'rss.dart' show ogImage;
import 'session_client.dart';
import 'source_types.dart';

const _base = 'https://news.web.nhk';
const _listUrl = '$_base/news/easy/top-list.json';
const _homepage = '$_base/news/easy/';

class NhkEasySource extends FeedSource {
  final SessionClient _client;

  NhkEasySource(this._client);

  @override
  String get id => 'nhk-easy';
  @override
  String get name => 'NHK News Easy';

  @override
  String? get nativeName => 'NHKやさしいニュース';
  @override
  String? get description =>
      'やさしい日本語 — daily news rewritten for learners';
  @override
  String get language => 'ja';
  @override
  ContentType get contentType => ContentType.news;
  @override
  String? get homepageUrl => _homepage;

  /// Run the auth handshake at most once per app session (shared with the
  /// regular NHK News adapter — same cookie domain).
  Future<void> _ensureAuthenticated() => NhkAuth.ensure(_client);

  @override
  Future<List<ArticleStub>> list() async {
    final listUri = Uri.parse(_listUrl);
    var res = await _client.get(listUri);
    if (res.statusCode == 401 || res.statusCode == 403) {
      await _ensureAuthenticated();
      res = await _client.get(listUri);
    }
    if (!res.ok) {
      throw Exception('NHK Easy list HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! List) return const [];
    final out = <ArticleStub>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final newsId = raw['news_id'] as String?;
      final title = raw['title'] as String?;
      if (newsId == null || title == null || title.isEmpty) continue;
      out.add(ArticleStub(
        id: newsId,
        title: title.replaceAll(RegExp(r'\s+'), ' ').trim(),
        sourceUrl: _articleUrl(newsId),
        publishedAt: _parsePrearrangedTime(
            (raw['news_publication_time'] as String?) ??
                (raw['news_prearranged_time'] as String?)),
        imageUrl: (raw['news_easy_image_uri'] as String?) ??
            (raw['news_web_image_uri'] as String?),
        summary: _stripHtml(raw['outline_with_ruby'] as String?),
      ));
    }
    return out;
  }

  @override
  Future<Chapter> fetch(ArticleStub stub) async {
    final url = Uri.parse(stub.sourceUrl);
    var res = await _client.get(url);
    // Without a session cookie the URL still 200s but returns the Next.js SPA
    // shell instead of SSR'd content. Detect by looking for the body marker.
    if (!res.ok || !res.body.contains('js-article-body')) {
      await _ensureAuthenticated();
      res = await _client.get(url);
    }
    if (!res.ok) {
      throw Exception('NHK Easy article HTTP ${res.statusCode}');
    }
    final doc = html_parser.parse(res.body);
    final text = _extractBody(doc);
    if (text.isEmpty) {
      throw Exception('Could not parse NHK Easy article body');
    }
    return Chapter(
      id: stub.id,
      title: stub.title,
      originalText: text,
      sourceUrl: stub.sourceUrl,
      publishedAt: stub.publishedAt,
      // Prefer the article page's social image (always absolute); the list
      // stub's URI can be relative or missing.
      imageUrl: ogImage(doc) ?? stub.imageUrl,
    );
  }
}

String _articleUrl(String newsId) => '$_base/news/easy/$newsId/$newsId.html';

int? _parsePrearrangedTime(String? s) {
  if (s == null) return null;
  // "2025-05-23 14:00:00" — assumed JST.
  final isoLike = '${s.replaceFirst(' ', 'T')}+09:00';
  return DateTime.tryParse(isoLike)?.millisecondsSinceEpoch;
}

String _extractBody(dom.Document doc) {
  final body = doc.querySelector('#js-article-body') ??
      doc.querySelector('.article-main__body') ??
      doc.querySelector('article');
  if (body == null) return '';
  // Drop ruby annotations — keep only base text.
  for (final el in body.querySelectorAll('rt, rp')) {
    el.remove();
  }
  final paragraphs = <String>[];
  for (final p in body.querySelectorAll('p, div.body-text')) {
    final t = p.text.trim();
    if (t.isNotEmpty) paragraphs.add(t);
  }
  if (paragraphs.isEmpty) {
    return body.text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
  return paragraphs.join('\n\n');
}

String? _stripHtml(String? html) {
  if (html == null) return null;
  // Remove ruby annotation markup but keep base text.
  final cleaned = html
      .replaceAll(RegExp(r'<rt[^>]*>[\s\S]*?</rt>'), '')
      .replaceAll(RegExp(r'<rp[^>]*>[\s\S]*?</rp>'), '')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .trim();
  return cleaned.isEmpty ? null : cleaned;
}
