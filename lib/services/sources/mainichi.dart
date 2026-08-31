import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../data/models/chapter.dart';
import '../../data/models/novel.dart' show ContentType;
import 'rss.dart' show parseRssItems, ogImage;
import 'session_client.dart';
import 'source_types.dart';

/// Mainichi Shimbun's breaking-news feed (ニュース速報・総合). Flash articles
/// are usually free in full; premium articles serve only their free opening
/// portion, which we import as-is with a short notice appended.
class MainichiSource extends FeedSource {
  static const _rssUrl = 'https://mainichi.jp/rss/etc/mainichi-flash.rss';

  final SessionClient _client;

  MainichiSource(this._client);

  @override
  String get id => 'mainichi';
  @override
  String get name => 'Mainichi Shimbun';

  @override
  String? get nativeName => '毎日新聞';
  @override
  String? get description => '毎日新聞 ニュース速報 — breaking news';
  @override
  String get language => 'ja';
  @override
  ContentType get contentType => ContentType.news;
  @override
  String? get homepageUrl => 'https://mainichi.jp/';

  @override
  Future<List<ArticleStub>> list() async {
    final res = await _client.get(Uri.parse(_rssUrl));
    if (!res.ok) throw Exception('Mainichi RSS HTTP ${res.statusCode}');
    final out = <ArticleStub>[];
    for (final item in parseRssItems(res.body)) {
      final m = RegExp(r'/articles/(\d+)/([a-z0-9]+)/(\d+[a-z]?)/(\d+c)')
          .firstMatch(item.link);
      out.add(ArticleStub(
        id: m == null ? item.link : m.groups([1, 2, 3, 4]).join('-'),
        title: item.title,
        sourceUrl: item.link,
        publishedAt: item.publishedAt,
        summary: item.description,
      ));
    }
    return out;
  }

  @override
  Future<Chapter> fetch(ArticleStub stub) async {
    final res = await _client.get(Uri.parse(stub.sourceUrl));
    if (!res.ok) throw Exception('Mainichi article HTTP ${res.statusCode}');

    final doc = html_parser.parse(res.body);
    final body = doc.querySelector('section.articledetail-body') ??
        doc.querySelector('.articledetail-body');
    if (body == null) throw Exception('Could not parse Mainichi article body');

    // Photo captions, embedded scripts and ad slots live inside the body
    // section — drop them before collecting paragraphs.
    for (final el in body.querySelectorAll(
        'figure, figcaption, script, style, [class*="ad-"], aside')) {
      el.remove();
    }
    final paragraphs = <String>[];
    for (final p in body.querySelectorAll('p')) {
      final t = p.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) paragraphs.add(t);
    }
    if (paragraphs.isEmpty) {
      throw Exception('Mainichi article body was empty');
    }

    var text = paragraphs.join('\n\n');
    if (_isPaywalled(doc)) {
      text = '$text\n\n（この記事の続きは毎日新聞の有料会員向けです）';
    }
    return Chapter(
      id: stub.id,
      title: stub.title,
      originalText: text,
      sourceUrl: stub.sourceUrl,
      publishedAt: stub.publishedAt,
      imageUrl: ogImage(doc),
    );
  }

  /// Mainichi flags premium articles in a meta tag; free articles have an
  /// empty value.
  static bool _isPaywalled(dom.Document doc) {
    final meta = doc.querySelector('meta[name="cXenseParse:mai-fee-charging"]');
    final v = meta?.attributes['content'];
    return v != null && v.isNotEmpty;
  }
}
