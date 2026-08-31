import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../data/models/chapter.dart';
import '../../data/models/novel.dart' show ContentType;
import 'nhk_auth.dart';
import 'rss.dart' show parseRssItems, ogImage;
import 'session_client.dart';
import 'source_types.dart';

/// One NHK News Web desk — a category RSS feed. NHK publishes nine, and they
/// all render the same way, so each becomes its own paper on the stand.
class NhkDesk {
  /// RSS filename stem (`cat0` … `cat8`).
  final String cat;

  /// Source id. The top-stories desk keeps the historical plain `nhk-news`
  /// so feeds imported before the desks existed still resolve.
  final String id;
  final String name;
  final String nativeName;
  final bool byDefault;

  const NhkDesk({
    required this.cat,
    required this.id,
    required this.name,
    required this.nativeName,
    this.byDefault = false,
  });

  static const top = NhkDesk(
      cat: 'cat0',
      id: 'nhk-news',
      name: 'NHK News',
      nativeName: 'NHKニュース',
      byDefault: true);

  /// Every desk, top stories first.
  static const all = [
    top,
    NhkDesk(cat: 'cat1', id: 'nhk-shakai', name: 'NHK Society', nativeName: 'NHK社会'),
    NhkDesk(cat: 'cat4', id: 'nhk-seiji', name: 'NHK Politics', nativeName: 'NHK政治'),
    NhkDesk(cat: 'cat5', id: 'nhk-keizai', name: 'NHK Business', nativeName: 'NHK経済'),
    NhkDesk(cat: 'cat6', id: 'nhk-kokusai', name: 'NHK World', nativeName: 'NHK国際'),
    NhkDesk(cat: 'cat3', id: 'nhk-kagaku', name: 'NHK Science', nativeName: 'NHK科学・医療'),
    NhkDesk(cat: 'cat2', id: 'nhk-bunka', name: 'NHK Culture', nativeName: 'NHK文化・エンタメ'),
    NhkDesk(cat: 'cat7', id: 'nhk-sports', name: 'NHK Sport', nativeName: 'NHKスポーツ'),
    // cat8 (暮らし) is deliberately absent: its feed links to lifestyle
    // landing pages rather than news articles, so nothing survives the
    // article-id filter.
  ];
}

/// Regular NHK News Web (full-difficulty Japanese). Listing comes from the
/// public RSS feed; article bodies are server-rendered on news.web.nhk but
/// only in full once the NHK session handshake has run (same cookies as NHK
/// Easy). One instance per [NhkDesk].
class NhkNewsSource extends FeedSource {
  final SessionClient _client;
  final NhkDesk desk;

  NhkNewsSource(this._client, {this.desk = NhkDesk.top});

  String get _rssUrl => 'https://www3.nhk.or.jp/rss/news/${desk.cat}.xml';

  @override
  String get id => desk.id;
  @override
  String get name => desk.name;

  @override
  String? get nativeName => desk.nativeName;
  @override
  String? get description => '${desk.nativeName} — full-difficulty daily news';
  @override
  bool get enabledByDefault => desk.byDefault;
  @override
  String get language => 'ja';
  @override
  ContentType get contentType => ContentType.news;
  @override
  String? get homepageUrl => 'https://news.web.nhk/newsweb/';

  @override
  Future<List<ArticleStub>> list() async {
    final res = await _client.get(Uri.parse(_rssUrl));
    if (!res.ok) throw Exception('${desk.name} RSS HTTP ${res.statusCode}');
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
