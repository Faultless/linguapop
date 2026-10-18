import 'dart:async';
import 'dart:convert';

import '../../data/models/chapter.dart';
import '../../data/models/novel.dart' show ContentType;
import 'nhk_auth.dart';
import 'session_client.dart';
import 'source_types.dart';

/// One NHK News desk — a genre of NHK's article playlists. They all read the
/// same way, so each becomes its own paper on the stand.
class NhkDesk {
  /// Playlist genre: `news-nwa-<genre>-nationwide[-YYYYMMDD]`.
  final String genre;

  /// Source id. The top-stories desk keeps the historical plain `nhk-news`
  /// so feeds imported before the desks existed still resolve.
  final String id;
  final String name;
  final String nativeName;
  final bool byDefault;

  const NhkDesk({
    required this.genre,
    required this.id,
    required this.name,
    required this.nativeName,
    this.byDefault = false,
  });

  static const top = NhkDesk(
      genre: 'latest',
      id: 'nhk-news',
      name: 'NHK News',
      nativeName: 'NHKニュース',
      byDefault: true);

  /// Every desk, top stories first. NHK merged science and culture into one
  /// genre, so the old 文化 desk is gone and 科学 covers both.
  static const all = [
    top,
    NhkDesk(genre: 'society', id: 'nhk-shakai', name: 'NHK Society', nativeName: 'NHK社会'),
    NhkDesk(genre: 'politics', id: 'nhk-seiji', name: 'NHK Politics', nativeName: 'NHK政治'),
    NhkDesk(genre: 'business', id: 'nhk-keizai', name: 'NHK Business', nativeName: 'NHK経済'),
    NhkDesk(genre: 'international', id: 'nhk-kokusai', name: 'NHK World', nativeName: 'NHK国際'),
    NhkDesk(genre: 'scienceculture', id: 'nhk-kagaku', name: 'NHK Science & Culture', nativeName: 'NHK科学・文化'),
    NhkDesk(genre: 'sports', id: 'nhk-sports', name: 'NHK Sport', nativeName: 'NHKスポーツ'),
    NhkDesk(genre: 'disaster', id: 'nhk-saigai', name: 'NHK Disasters', nativeName: 'NHK災害'),
  ];
}

/// Regular NHK News (full-difficulty Japanese), read from the JSON API behind
/// news.web.nhk. The old www3 RSS froze in August 2026.
///
/// NHK keeps one playlist per genre per day, and each item carries the whole
/// article body. So listing a window is one request per day, and fetching is
/// free: [list] puts the body on the stub.
class NhkNewsSource extends FeedSource {
  final SessionClient _client;
  final NhkDesk desk;

  NhkNewsSource(this._client, {this.desk = NhkDesk.top});

  static const _api = 'https://api.web.nhk/r8/l/newsarticle/pl';

  /// The API's largest page.
  static const _pageSize = 20;

  /// Days listed when the caller gives no `since`.
  static const _defaultDays = 3;

  /// Wire flashes ("速報") are a line or two; not worth a page.
  static const _minBody = 80;

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

  String _playlist(DateTime day) =>
      '$_api/news-nwa-${desk.genre}-nationwide-${_ymd(day)}.json?size=$_pageSize';

  @override
  Future<List<ArticleStub>> list({DateTime? since}) async {
    await NhkAuth.ensure(_client);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = since == null
        ? today.subtract(const Duration(days: _defaultDays - 1))
        : DateTime(since.year, since.month, since.day);
    final out = <ArticleStub>[];
    final seen = <String>{};
    var failures = 0;
    var days = 0;
    for (var d = today; !d.isBefore(first); d = DateTime(d.year, d.month, d.day - 1)) {
      days++;
      final res = await _client.get(Uri.parse(_playlist(d)));
      // A day with no playlist yet (just past midnight) is a 404, not an error.
      if (!res.ok) {
        if (res.statusCode != 404) failures++;
        continue;
      }
      for (final stub in parsePlaylist(res.body)) {
        if (seen.add(stub.id)) out.add(stub);
      }
    }
    if (out.isEmpty && failures == days) {
      throw Exception('${desk.name} API unreachable');
    }
    return out;
  }

  /// Stubs out of one playlist page, each carrying its article body.
  static List<ArticleStub> parsePlaylist(String json) {
    final data = jsonDecode(json);
    final items = data is Map ? data['result'] : null;
    if (items is! List) return const [];
    final out = <ArticleStub>[];
    for (final item in items) {
      if (item is! Map) continue;
      final id = item['id'] as String?;
      final title = (item['headline'] ?? item['name']) as String?;
      final body = _paragraphs(item['articleBody'] as String? ?? '');
      if (id == null || title == null || body.length < _minBody) continue;
      final published = DateTime.tryParse(item['datePublished'] as String? ?? '');
      final image = item['image'];
      String? imageUrl;
      if (image is Map) {
        final pick = image['icon'] ?? image['medium'];
        if (pick is Map) imageUrl = pick['url'] as String?;
      }
      out.add(ArticleStub(
        id: id,
        title: title.trim(),
        sourceUrl: item['canonical'] as String? ??
            'https://news.web.nhk/newsweb/na/$id',
        publishedAt: published?.millisecondsSinceEpoch,
        summary: body.length > 120 ? '${body.substring(0, 120)}…' : body,
        imageUrl: imageUrl,
        body: body,
      ));
    }
    return out;
  }

  @override
  Future<Chapter> fetch(ArticleStub stub) async {
    var body = stub.body;
    var imageUrl = stub.imageUrl;
    if (body == null) {
      await NhkAuth.ensure(_client);
      final id = stub.sourceUrl.split('/').last;
      final res = await _client
          .get(Uri.parse('https://api.web.nhk/r8/t/newsarticle/na/$id.json'));
      if (!res.ok) throw Exception('NHK News article HTTP ${res.statusCode}');
      final parsed = parsePlaylist('{"result":[${res.body}]}');
      if (parsed.isEmpty) throw Exception('Could not parse NHK News article');
      body = parsed.first.body;
      imageUrl ??= parsed.first.imageUrl;
    }
    return Chapter(
      id: stub.id,
      title: stub.title,
      originalText: body!,
      sourceUrl: stub.sourceUrl,
      publishedAt: stub.publishedAt,
      imageUrl: imageUrl,
    );
  }

  /// NHK separates paragraphs with two or three newlines; normalise to one
  /// blank line, which is what the reader splits on.
  static String _paragraphs(String raw) => raw
      .split(RegExp(r'\n\s*\n+'))
      .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((p) => p.isNotEmpty)
      .join('\n\n');

  static String _ymd(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}
