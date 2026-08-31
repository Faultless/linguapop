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
/// One Mainichi feed. The paper publishes several RDF feeds; these are the
/// ones that actually resolve — the section paths advertised elsewhere
/// (`shakai`, `keizai`, …) answer 200 with an HTML error page.
class MainichiDesk {
  /// Feed filename stem under `/rss/etc/`.
  final String slug;
  final String id;
  final String name;
  final String nativeName;
  final String tagline;
  final bool byDefault;

  const MainichiDesk({
    required this.slug,
    required this.id,
    required this.name,
    required this.nativeName,
    required this.tagline,
    this.byDefault = false,
  });

  static const flash = MainichiDesk(
      slug: 'mainichi-flash',
      id: 'mainichi',
      name: 'Mainichi Shimbun',
      nativeName: '毎日新聞',
      tagline: 'ニュース速報 — breaking news',
      byDefault: true);

  /// Just the one. The other advertised feeds don't hold up: `sports` and
  /// `enta` are stale placeholders, `mainichi.rss` mixes section landing
  /// pages in with the stories, `opinion` serves the flash feed's items
  /// verbatim, and the section paths (`shakai`, `keizai`, …) answer 200 with
  /// an HTML error page.
  static const all = [flash];
}

class MainichiSource extends FeedSource {
  final SessionClient _client;
  final MainichiDesk desk;

  MainichiSource(this._client, {this.desk = MainichiDesk.flash});

  String get _rssUrl => 'https://mainichi.jp/rss/etc/${desk.slug}.rss';

  @override
  String get id => desk.id;
  @override
  String get name => desk.name;

  @override
  String? get nativeName => desk.nativeName;
  @override
  String? get description => '${desk.nativeName} ${desk.tagline}';
  @override
  bool get enabledByDefault => desk.byDefault;
  @override
  String get language => 'ja';
  @override
  ContentType get contentType => ContentType.news;
  @override
  String? get homepageUrl => 'https://mainichi.jp/';

  @override
  Future<List<ArticleStub>> list() async {
    final res = await _client.get(Uri.parse(_rssUrl));
    if (!res.ok) throw Exception('${desk.name} RSS HTTP ${res.statusCode}');
    final out = <ArticleStub>[];
    for (final item in parseRssItems(res.body)) {
      // Article URLs look like
      // /articles/20260831/k00/00m/020/033000c — five path segments, ending
      // in the story number. Anything else in the feed is a section landing
      // page with no body to extract.
      final m = RegExp(r'/articles/([\w-]+(?:/[\w-]+)+c)(?:[?#]|$)')
          .firstMatch(item.link);
      if (m == null) continue;
      out.add(ArticleStub(
        id: m.group(1)!.replaceAll('/', '-'),
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
