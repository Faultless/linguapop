import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../data/models/chapter.dart';
import '../../data/models/novel.dart' show ContentType;
import 'nhk_auth.dart';
import 'rss.dart' show parseRssItems, ogImage;
import 'session_client.dart';
import 'source_types.dart';

/// Regular NHK News Web (full-difficulty Japanese). Listing comes from the
/// public RSS feed; article bodies are server-rendered on news.web.nhk but
/// only in full once the NHK session handshake has run (same cookies as NHK
/// Easy).
class NhkNewsSource extends FeedSource {
  // Top stories. Other categories exist (cat1 社会, cat5 ビジネス, …) but the
  // main feed keeps the list manageable.
  static const _rssUrl = 'https://www3.nhk.or.jp/rss/news/cat0.xml';

  final SessionClient _client;

  NhkNewsSource(this._client);

  @override
  String get id => 'nhk-news';
  @override
  String get name => 'NHK News';

  @override
  String? get nativeName => 'NHKニュース';
  @override
  String? get description => 'NHKニュース — full-difficulty daily news';
  @override
  String get language => 'ja';
  @override
  ContentType get contentType => ContentType.news;
  @override
  String? get homepageUrl => 'https://news.web.nhk/newsweb/';

  @override
  Future<List<ArticleStub>> list() async {
    final res = await _client.get(Uri.parse(_rssUrl));
    if (!res.ok) throw Exception('NHK News RSS HTTP ${res.statusCode}');
    final out = <ArticleStub>[];
    for (final item in parseRssItems(res.body)) {
      final id = _newsId(item.link);
      if (id == null) continue;
      out.add(ArticleStub(
        id: id,
        title: item.title,
        sourceUrl: _articleUrl(id),
        publishedAt: item.publishedAt,
        summary: item.description,
      ));
    }
    return out;
  }

  @override
  Future<Chapter> fetch(ArticleStub stub) async {
    final url = Uri.parse(stub.sourceUrl);
    await NhkAuth.ensure(_client);
    var res = await _client.get(url);
    if (!res.ok) throw Exception('NHK News article HTTP ${res.statusCode}');
    final doc = html_parser.parse(res.body);
    final text = _extractBody(doc);
    if (text.isEmpty) {
      throw Exception('Could not parse NHK News article body');
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

  /// RSS links look like
  /// `http://www3.nhk.or.jp/news/html/20260612/k10015148891000.html`.
  static String? _newsId(String link) {
    final m = RegExp(r'(k\d{14,})').firstMatch(link);
    return m?.group(1);
  }

  static String _articleUrl(String id) =>
      'https://news.web.nhk/newsweb/na/na-$id';

  /// The newsweb pages use hashed CSS classes that change between deploys, so
  /// the extractor self-calibrates: the first non-empty `<p>` after the `<h1>`
  /// is the article lead — every body paragraph shares its exact class
  /// attribute, while related-news/teaser paragraphs use different classes.
  static String _extractBody(dom.Document doc) {
    final root = doc.querySelector('main') ?? doc.body;
    if (root == null) return '';

    // querySelectorAll returns document order, so this walks h1 and every p
    // in the order they appear on the page.
    String? bodyClass;
    var seenH1 = root.querySelector('h1') == null;
    final paragraphs = <String>[];
    for (final el in root.querySelectorAll('h1, p')) {
      if (el.localName == 'h1') {
        seenH1 = true;
        continue;
      }
      if (!seenH1) continue;
      final text = _cleanParagraph(el);
      if (text.isEmpty) continue;
      bodyClass ??= el.attributes['class'] ?? '';
      if ((el.attributes['class'] ?? '') == bodyClass) {
        paragraphs.add(text);
      }
    }
    return paragraphs.join('\n\n');
  }

  /// Strips UI furniture nested inside a paragraph (share buttons, category
  /// links, ruby annotations) before reading its text.
  static String _cleanParagraph(dom.Element p) {
    final clone = p.clone(true);
    for (final el in clone.querySelectorAll('a, button, rt, rp, svg')) {
      el.remove();
    }
    return clone.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
