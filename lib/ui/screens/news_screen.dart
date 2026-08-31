import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/reader_prefs.dart';
import '../../providers/news_provider.dart';
import '../../providers/prefs_provider.dart';
import '../../providers/sources_provider.dart';
import '../../services/sources/feed_sync.dart';
import '../../services/sources/source_types.dart';
import '../widgets/difficulty_badge.dart';
import '../widgets/front_page.dart';
import '../widgets/news_thumb.dart';
import '../widgets/newspaper.dart';
import '../widgets/view_mode_button.dart';
import '../widgets/web_source_notice.dart';

const _kAllSources = 'all';

/// The combined edition's own masthead — "Kotoba Shimbun", the word paper.
const _kAllPapersTitle = '言葉新聞';
const _kAllPapersOverline = 'Kotoba Shimbun · LinguaPop';

/// The front page: every imported feed article laid out as a newspaper —
/// masthead, a rack of papers you can switch between, and two columns of
/// headlines you scroll straight through instead of paging article by
/// article in the reader.
///
/// The list/card view modes from the old news hub are still available through
/// the view-mode button for readers who prefer a linear feed.
class NewsScreen extends ConsumerStatefulWidget {
  /// Source id to open on ("all" for every paper). Comes from `?paper=` so
  /// the library and the browse screen can deep-link into one paper.
  final String? initialPaper;
  const NewsScreen({super.key, this.initialPaper});
  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  late String _paper = widget.initialPaper ?? _kAllSources;
  bool _unreadOnly = false;

  bool _syncing = false;
  bool _cancelRequested = false;
  FeedSyncProgress? _progress;

  /// Last list we successfully rendered. The articles provider recomputes on
  /// every library write, and dropping to a spinner each time made a sync look
  /// like the page was reloading under the reader. Holding the previous
  /// edition means the page only ever changes by gaining stories.
  List<NewsArticle>? _lastArticles;

  /// Papers the stand carries, honouring the source manager.
  List<FeedSource> _enabledFeeds() {
    final registry = ref.read(sourceRegistryProvider);
    final carried = ReaderPrefsNotifier.carriedSources(
        ref.read(readerPrefsProvider), registry.defaultFeedIds);
    return registry.feedSources.where((s) => carried.contains(s.id)).toList();
  }

  /// Feed sources the current paper selection covers.
  List<FeedSource> _selectedSources() {
    final all = _enabledFeeds();
    if (_paper == _kAllSources) return all;
    return all.where((s) => s.id == _paper).toList();
  }

  /// Move one paper along the rack, wrapping at both ends. Bound to a
  /// horizontal swipe so reading mode needs no rack at all.
  void _shiftPaper(int delta) {
    final ids = [_kAllSources, for (final s in _enabledFeeds()) s.id];
    if (ids.length < 2) return;
    final current = ids.indexOf(_paper);
    final next = ((current < 0 ? 0 : current) + delta) % ids.length;
    setState(() => _paper = ids[next < 0 ? next + ids.length : next]);
  }

  Future<void> _fetch(FeedFetchMode mode) async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _cancelRequested = false;
      _progress = null;
    });
    final result = await ref.read(feedSyncProvider).run(
          sources: _selectedSources(),
          mode: mode,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          isCancelled: () => _cancelRequested,
        );
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _progress = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.summary)));
  }

  Future<void> _pickFetchMode() async {
    final mode = await showModalBottomSheet<FeedFetchMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in FeedFetchMode.values)
              ListTile(
                leading: Icon(m == FeedFetchMode.today
                    ? Icons.today_outlined
                    : Icons.download_outlined),
                title: Text(m.label),
                subtitle: Text(m.description),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );
    if (mode != null) await _fetch(mode);
  }

  Future<void> _delete(NewsArticle a) async {
    await ref.read(sourceImporterProvider).removeArticle(
          sourceId: a.sourceId,
          sourceUrl: a.chapter.sourceUrl ?? '',
        );
  }

  Future<void> _confirmDelete(NewsArticle a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove story?'),
        content: Text(a.chapter.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _delete(a);
  }

  void _open(NewsArticle a) {
    ref.read(newsReadProvider.notifier).markRead(a.novelId, a.chapter.id);
    context.go('/reader/${a.novelId}?ch=${a.chapterIndex}');
  }

  @override
  Widget build(BuildContext context) {
    // Same restriction as the sources screen: the feed adapters are
    // dart:io-based and cannot run on Flutter web.
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('News')),
        body: const SafeArea(child: WebSourceNotice()),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final articlesAsync = ref.watch(newsArticlesProvider);
    final readSet = ref.watch(newsReadProvider);
    final registry = ref.watch(sourceRegistryProvider);
    final prefs = ref.watch(readerPrefsProvider);
    final simple = prefs.simpleMode;
    final viewMode = simple ? LibraryViewMode.grid : prefs.newsViewMode;
    final carried = ReaderPrefsNotifier.carriedSources(
        prefs, registry.defaultFeedIds);
    final feedSources =
        registry.feedSources.where((s) => carried.contains(s.id)).toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        scrolledUnderElevation: 0,
        title: const Text('新聞',
            style: TextStyle(
                fontFamily: 'serif',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 2)),
        actions: [
          if (!simple) ...[
            ViewModeButton(
              mode: viewMode,
              labelOverrides: const {LibraryViewMode.grid: 'Front page'},
              iconOverrides: const {
                LibraryViewMode.grid: Icons.view_column_outlined
              },
              onChanged: (m) =>
                  ref.read(readerPrefsProvider.notifier).setNewsViewMode(m),
            ),
            IconButton(
              tooltip: _unreadOnly ? 'Showing unread only' : 'Show unread only',
              onPressed: () => setState(() => _unreadOnly = !_unreadOnly),
              icon: Icon(_unreadOnly
                  ? Icons.mark_email_unread
                  : Icons.mark_email_unread_outlined),
            ),
          ],
          IconButton(
            tooltip: _syncing ? 'Stop fetching' : 'Fetch stories',
            onPressed: _syncing
                ? () => setState(() => _cancelRequested = true)
                : (simple
                    ? () => _fetch(FeedFetchMode.today)
                    : _pickFetchMode),
            icon: _syncing
                ? const Icon(Icons.stop_circle_outlined)
                : const Icon(Icons.download_outlined),
          ),
          if (simple)
            IconButton(
              tooltip: 'Settings',
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.more_horiz),
            )
          else
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'read-all') _markAllRead();
                if (v == 'browse') context.go('/sources');
                if (v == 'papers') context.go('/sources/manage');
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                    value: 'read-all', child: Text('Mark all as read')),
                PopupMenuItem(value: 'papers', child: Text('Papers…')),
                PopupMenuItem(value: 'browse', child: Text('Browse sources')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            final articles = articlesAsync.valueOrNull ?? _lastArticles;
            if (articles == null) {
              if (articlesAsync.hasError) {
                return Center(child: Text('Failed to load: ${articlesAsync.error}'));
              }
              return const Center(child: CircularProgressIndicator());
            }
            _lastArticles = articles;

            bool isRead(NewsArticle a) => readSet
                .contains(NewsReadNotifier.keyFor(a.novelId, a.chapter.id));
            String nameOf(NewsArticle a) {
              final src = registry.byId(a.sourceId);
              return src?.nativeName ?? src?.name ?? a.sourceId;
            }

            // Stories from a paper that's been taken off the stand stay in the
            // library but leave the front page.
            var items =
                articles.where((a) => carried.contains(a.sourceId)).toList();
            if (_paper != _kAllSources) {
              items = items.where((a) => a.sourceId == _paper).toList();
            }
            if (_unreadOnly) {
              items = items.where((a) => !isRead(a)).toList();
            }

            // Unread badges on the rack always reflect the whole library, not
            // the current filter.
            final unreadBySource = <String, int>{};
            for (final a in articles) {
              if (isRead(a)) continue;
              unreadBySource[a.sourceId] =
                  (unreadBySource[a.sourceId] ?? 0) + 1;
            }

            final rack = _PaperRack(
              papers: [
                (
                  id: _kAllSources,
                  name: '全紙',
                  unread: unreadBySource.values.fold(0, (a, b) => a + b),
                ),
                for (final s in feedSources)
                  (
                    id: s.id,
                    name: s.nativeName ?? s.name,
                    unread: unreadBySource[s.id] ?? 0,
                  ),
              ],
              selected: _paper,
              onSelected: (id) => setState(() => _paper = id),
            );

            final papers = [_kAllSources, for (final s in feedSources) s.id];
            final paperIndex = papers.indexOf(_paper);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (simple)
                  _PaperDots(count: papers.length, index: paperIndex)
                else
                  rack,
                const NewsRule(alpha: 0.35),
                if (_syncing) _SyncBanner(progress: _progress),
                Expanded(
                  // Swipe left/right to change paper. The page under this
                  // scrolls vertically, so a horizontal drag is unambiguous —
                  // in reading mode it's the only way to change paper.
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v < -250) _shiftPaper(1);
                      if (v > 250) _shiftPaper(-1);
                    },
                    child: RefreshIndicator(
                    onRefresh: () => _fetch(FeedFetchMode.today),
                    child: viewMode == LibraryViewMode.grid
                        ? _FrontPage(
                            items: items,
                            paperTitle: _paperTitle(feedSources),
                            paperOverline: _paperOverline(feedSources),
                            showSource: _paper == _kAllSources,
                            totalCount: articles.length,
                            isRead: isRead,
                            nameOf: nameOf,
                            onOpen: _open,
                            onDelete: _confirmDelete,
                            onFetch: _fetch,
                            syncing: _syncing,
                            simple: simple,
                          )
                        : _LinearNews(
                            items: items,
                            big: viewMode == LibraryViewMode.card,
                            isRead: isRead,
                            nameOf: nameOf,
                            onOpen: _open,
                            onDelete: _delete,
                            onFetch: _fetch,
                            syncing: _syncing,
                            hasAnyArticles: articles.isNotEmpty,
                          ),
                    ),
                  ),
                ),
                if (items.isNotEmpty && !simple)
                  Container(
                    color: cs.onSurface.withValues(alpha: 0.03),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_unreadOnly ? "未読" : "全"}${items.length}件',
                            style: NewsprintStyle.meta(cs, size: 9.5).copyWith(
                                color: cs.onSurface.withValues(alpha: 0.5)),
                          ),
                        ),
                        TextButton(
                          onPressed:
                              _syncing ? null : () => _fetch(FeedFetchMode.today),
                          child: const Text("Today's paper"),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Masthead name: the outlet in its own script, or the paper of record we
  /// print when every source is folded into one edition.
  String _paperTitle(List<FeedSource> feedSources) {
    if (_paper == _kAllSources) return _kAllPapersTitle;
    for (final s in feedSources) {
      if (s.id == _paper) return s.nativeName ?? s.name;
    }
    return _kAllPapersTitle;
  }

  /// Romaji line above the masthead.
  String _paperOverline(List<FeedSource> feedSources) {
    if (_paper == _kAllSources) return _kAllPapersOverline;
    for (final s in feedSources) {
      if (s.id == _paper) return s.name;
    }
    return _kAllPapersOverline;
  }

  Future<void> _markAllRead() async {
    final articles = ref.read(newsArticlesProvider).valueOrNull ?? const [];
    final notifier = ref.read(newsReadProvider.notifier);
    for (final a in articles) {
      if (_paper != _kAllSources && a.sourceId != _paper) continue;
      await notifier.markRead(a.novelId, a.chapter.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Front page (newspaper layout)
// ---------------------------------------------------------------------------

/// Masonry front page: masthead, then day-labelled bands of story blocks laid
/// into two columns on a phone (more on a tablet or desktop window).
///
/// Bands rather than one continuous masonry: a band is a fixed slice of the
/// list balanced across the columns, which keeps the whole thing inside a
/// `ListView.builder`. Building every story eagerly would mean tokenizing
/// every article for its difficulty badge on first paint.
class _FrontPage extends StatelessWidget {
  final List<NewsArticle> items;
  final String paperTitle;
  final String paperOverline;
  final bool showSource;
  final int totalCount;
  final bool Function(NewsArticle) isRead;
  final String Function(NewsArticle) nameOf;
  final void Function(NewsArticle) onOpen;
  final Future<void> Function(NewsArticle) onDelete;
  final Future<void> Function(FeedFetchMode) onFetch;
  final bool syncing;
  final bool simple;

  const _FrontPage({
    required this.items,
    required this.paperTitle,
    required this.paperOverline,
    required this.showSource,
    required this.totalCount,
    required this.isRead,
    required this.nameOf,
    required this.onOpen,
    required this.onDelete,
    required this.onFetch,
    required this.syncing,
    this.simple = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = FrontPageBand.columnsFor(width);
    final rows = _buildRows(items, columns * 4);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
      itemCount: rows.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return _FrontPageHeader(
            title: paperTitle,
            overline: paperOverline,
            count: items.length,
            syncing: syncing,
            onFetch: onFetch,
            empty: items.isEmpty,
            hasAnyArticles: totalCount > 0,
            simple: simple,
          );
        }
        final row = rows[i - 1];
        if (row is String) return NewsSectionRule(label: row);
        final band = row as List<NewsArticle>;
        final byId = {for (final a in band) _entryId(a): a};
        return FrontPageBand(
          items: [for (final a in band) _toItem(a, isRead(a), nameOf(a))],
          columns: columns,
          showSource: showSource,
          onOpen: (item) => onOpen(byId[item.id]!),
          onLongPress: (item) => onDelete(byId[item.id]!),
        );
      },
    );
  }

  /// Day-label strings interleaved with fixed-size bands of articles.
  static List<Object> _buildRows(List<NewsArticle> items, int bandSize) {
    final rows = <Object>[];
    final buf = <NewsArticle>[];
    void flush() {
      for (var i = 0; i < buf.length; i += bandSize) {
        rows.add(buf.sublist(i, (i + bandSize).clamp(0, buf.length)));
      }
      buf.clear();
    }

    String? lastDay;
    for (final a in items) {
      final day = _dayLabel(a.chapter.publishedAt);
      if (day != lastDay) {
        flush();
        rows.add(day);
        lastDay = day;
      }
      buf.add(a);
    }
    flush();
    return rows;
  }
}

class _FrontPageHeader extends StatelessWidget {
  final String title;
  final String overline;
  final int count;
  final bool syncing;
  final bool empty;
  final bool hasAnyArticles;
  final bool simple;
  final Future<void> Function(FeedFetchMode) onFetch;
  const _FrontPageHeader({
    required this.title,
    required this.overline,
    required this.count,
    required this.syncing,
    required this.empty,
    required this.hasAnyArticles,
    required this.onFetch,
    this.simple = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NewspaperMasthead(
          title: title,
          overline: overline,
          leftMeta: _japaneseDate(now),
          rightMeta: '全$count件',
          seal: _editionSeal(now),
        ),
        const SizedBox(height: 10),
        if (simple)
          // Reading mode keeps one verb on the page: get the paper.
          OutlinedButton(
            onPressed: syncing ? null : () => onFetch(FeedFetchMode.today),
            child: const Text('今日の新聞'),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      syncing ? null : () => onFetch(FeedFetchMode.today),
                  icon: const Icon(Icons.today_outlined, size: 17),
                  label: const Text("Today's paper"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      syncing ? null : () => onFetch(FeedFetchMode.latest10),
                  icon: const Icon(Icons.download_outlined, size: 17),
                  label: const Text('Latest 10'),
                ),
              ),
            ],
          ),
        if (empty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Column(
              children: [
                Icon(Icons.newspaper_outlined,
                    size: 44, color: cs.onSurface.withValues(alpha: 0.25)),
                const SizedBox(height: 12),
                Text(
                  hasAnyArticles
                      ? 'Nothing matches the current filter.'
                      : 'No stories yet — pull the latest above.',
                  textAlign: TextAlign.center,
                  style: NewsprintStyle.body(cs, size: 13),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

String _entryId(NewsArticle a) => '${a.novelId}/${a.chapter.id}';

/// Project a stored feed article onto the layout-only model the front page
/// widgets take.
FrontPageItem _toItem(NewsArticle a, bool read, String sourceName) =>
    FrontPageItem(
      id: _entryId(a),
      title: a.chapter.title,
      snippet: a.chapter.originalText.replaceAll(RegExp(r'\s+'), ' ').trim(),
      sourceName: sourceName,
      imageUrl: a.chapter.imageUrl,
      publishedAt: a.chapter.publishedAt,
      read: read,
      difficultyText: a.chapter.originalText,
    );

class _PaperRack extends StatelessWidget {
  final List<({String id, String name, int unread})> papers;
  final String selected;
  final ValueChanged<String> onSelected;
  const _PaperRack({
    required this.papers,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: papers.length,
        separatorBuilder: (ctx, i) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final p = papers[i];
          return PaperTab(
            name: p.name,
            unread: p.unread,
            selected: selected == p.id,
            onTap: () => onSelected(p.id),
          );
        },
      ),
    );
  }
}

/// Where you are on the rack when there's no rack: one tick per paper, the
/// current one inked. Not a control — swiping is.
class _PaperDots extends StatelessWidget {
  final int count;
  final int index;
  const _PaperDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (count < 2) return const SizedBox(height: 10);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: i == index ? 16 : 8,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              color: cs.onSurface
                  .withValues(alpha: i == index ? 0.75 : 0.22),
            ),
        ],
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  final FeedSyncProgress? progress;
  const _SyncBanner({required this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, value: progress?.fraction),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              progress?.label ?? 'Checking the wires…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NewsprintStyle.meta(cs, size: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Linear (list / card) view — the pre-front-page layout, kept as an option
// ---------------------------------------------------------------------------

class _LinearNews extends StatelessWidget {
  final List<NewsArticle> items;
  final bool big;
  final bool Function(NewsArticle) isRead;
  final String Function(NewsArticle) nameOf;
  final void Function(NewsArticle) onOpen;
  final Future<void> Function(NewsArticle) onDelete;
  final Future<void> Function(FeedFetchMode) onFetch;
  final bool syncing;
  final bool hasAnyArticles;

  const _LinearNews({
    required this.items,
    required this.big,
    required this.isRead,
    required this.nameOf,
    required this.onOpen,
    required this.onDelete,
    required this.onFetch,
    required this.syncing,
    required this.hasAnyArticles,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyState(
        hasAnyArticles: hasAnyArticles,
        syncing: syncing,
        onFetch: onFetch,
      );
    }
    final rows = <Object>[];
    String? lastDay;
    for (final a in items) {
      final day = _dayLabel(a.chapter.publishedAt);
      if (day != lastDay) {
        rows.add(day);
        lastDay = day;
      }
      rows.add(a);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 48),
      itemCount: rows.length,
      itemBuilder: (ctx, i) {
        final row = rows[i];
        if (row is String) return _DayHeader(label: row);
        final a = row as NewsArticle;
        return _ArticleRow(
          key: ValueKey('${a.novelId}/${a.chapter.id}'),
          article: a,
          sourceName: nameOf(a),
          read: isRead(a),
          big: big,
          onTap: () => onOpen(a),
          onDelete: () => onDelete(a),
        );
      },
    );
  }
}

String _dayLabel(int? publishedAt) {
  if (publishedAt == null) return '日付なし';
  final dt = DateTime.fromMillisecondsSinceEpoch(publishedAt);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今日';
  if (diff == 1) return '昨日';
  return '${day.month}月${day.day}日';
}

const _weekdayKanji = ['月', '火', '水', '木', '金', '土', '日'];

/// "2026年8月31日（月）" — the dateline every Japanese daily runs.
String _japaneseDate(DateTime d) =>
    '${d.year}年${d.month}月${d.day}日（${_weekdayKanji[d.weekday - 1]}）';

/// Morning or evening edition, the way a paper stamps it.
String _editionSeal(DateTime d) => d.hour < 15 ? '朝刊' : '夕刊';

String _timeLabel(int? publishedAt) {
  if (publishedAt == null) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(publishedAt);
  return '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
}

class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  final NewsArticle article;
  final String sourceName;
  final bool read;

  /// Card view: larger lead image and a one-line text snippet.
  final bool big;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;
  const _ArticleRow({
    super.key,
    required this.article,
    required this.sourceName,
    required this.read,
    required this.onTap,
    required this.onDelete,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final time = _timeLabel(article.chapter.publishedAt);
    final thumbSize = big ? 84.0 : 60.0;
    final hasImage = (article.chapter.imageUrl ?? '').isNotEmpty;

    final meta = Row(
      children: [
        // Unread dot.
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: read ? Colors.transparent : cs.primary,
            border: read
                ? Border.all(color: cs.onSurface.withValues(alpha: 0.25))
                : null,
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            time.isEmpty ? sourceName : '$sourceName · $time',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
        const SizedBox(width: 8),
        DifficultyBadge(
          text: article.chapter.originalText,
          showBar: !big,
        ),
      ],
    );

    return Dismissible(
      key: ValueKey('dismiss-${article.novelId}-${article.chapter.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: cs.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, big ? 12 : 10, 16, big ? 12 : 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.chapter.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: big ? 15.5 : 14.5,
                        height: 1.3,
                        fontWeight: read ? FontWeight.w400 : FontWeight.w600,
                        color: read
                            ? cs.onSurface.withValues(alpha: 0.65)
                            : cs.onSurface,
                      ),
                    ),
                    if (big) ...[
                      const SizedBox(height: 4),
                      Text(
                        article.chapter.originalText.replaceAll('\n', ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    meta,
                  ],
                ),
              ),
              if (hasImage) ...[
                const SizedBox(width: 12),
                NewsThumb(
                  url: article.chapter.imageUrl,
                  width: thumbSize,
                  height: thumbSize,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasAnyArticles;
  final bool syncing;
  final Future<void> Function(FeedFetchMode) onFetch;
  const _EmptyState({
    required this.hasAnyArticles,
    required this.syncing,
    required this.onFetch,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.newspaper_outlined,
            size: 48, color: cs.onSurface.withValues(alpha: 0.3)),
        const SizedBox(height: 12),
        Text(
          hasAnyArticles
              ? 'Nothing matches the current filter.'
              : 'No news stories yet.',
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.65)),
        ),
        const SizedBox(height: 14),
        if (!hasAnyArticles)
          Center(
            child: FilledButton.tonalIcon(
              onPressed: syncing ? null : () => onFetch(FeedFetchMode.today),
              icon: const Icon(Icons.today_outlined),
              label: const Text("Get today's paper"),
            ),
          ),
      ],
    );
  }
}
