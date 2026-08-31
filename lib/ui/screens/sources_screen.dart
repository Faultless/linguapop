import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/sources_provider.dart';
import '../../services/sources/feed_sync.dart';
import '../../services/sources/source_import.dart';
import '../../services/sources/source_types.dart';
import '../../services/sources/syosetu.dart';
import '../widgets/difficulty_badge.dart';
import '../widgets/mini_toast.dart';
import '../widgets/web_source_notice.dart';

const _kSourceAll = 'all';

/// Compact chip labels for the source filter row.
const _kChipLabels = {
  'nhk-easy': 'NHK Easy',
  'nhk-news': 'NHK News',
  'mainichi': 'Mainichi',
  'syosetu': 'Syosetu',
};

/// Universal "browse + import" screen. Hits all available source adapters
/// from a single search bar and lets the user import in a single tap.
class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});
  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _sourceFilter = _kSourceAll;
  SearchOrder _order = SearchOrder.rating;
  CompletionFilter _completion = CompletionFilter.any;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  bool _visible(Source s) =>
      _sourceFilter == _kSourceAll || _sourceFilter == s.id;

  @override
  Widget build(BuildContext context) {
    // Live source adapters are dart:io-based (and CORS-blocked besides) —
    // never touch the registry on web, its client can't even construct.
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Browse sources')),
        body: const SafeArea(child: WebSourceNotice()),
      );
    }
    final registry = ref.watch(sourceRegistryProvider);
    final feedSources = registry.feedSources.where(_visible).toList();
    final searchSources = registry.searchSources.where(_visible).toList();
    final showSyosetuFilters = searchSources.whereType<SyosetuSource>().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse sources'),
        actions: [
          IconButton(
            tooltip: 'News hub',
            icon: const Icon(Icons.newspaper_outlined),
            onPressed: () => context.go('/news'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SearchHeader(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              chips: [
                (id: _kSourceAll, label: 'All'),
                for (final s in registry.all)
                  (id: s.id, label: _kChipLabels[s.id] ?? s.name),
              ],
              sourceFilter: _sourceFilter,
              onSourceFilterChanged: (s) =>
                  setState(() => _sourceFilter = s),
              order: _order,
              onOrderChanged: (o) => setState(() => _order = o),
              completion: _completion,
              onCompletionChanged: (c) => setState(() => _completion = c),
              showSyosetuFilters: showSyosetuFilters,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
                children: [
                  for (final feedSource in feedSources)
                    _FeedSection(
                      key: ValueKey('feed-${feedSource.id}'),
                      source: feedSource,
                      query: _query,
                      onAdd: _addArticle,
                      onRemove: _removeArticle,
                    ),
                  for (final searchSource in searchSources)
                    _SearchSection(
                      key: ValueKey('search-${searchSource.id}'),
                      source: searchSource,
                      query: SearchQuery(
                        word: _query.isEmpty ? null : _query,
                        order: _order,
                        completion: _completion,
                        limit: 20,
                      ),
                      onAdd: _addBook,
                      onRemove: _removeBook,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeArticle(FeedSource source, ArticleStub stub) async {
    final confirmed = await _confirmRemove(context, stub.title);
    if (confirmed != true || !mounted) return;
    await ref.read(sourceImporterProvider).removeArticle(
        sourceId: source.id, sourceUrl: stub.sourceUrl);
    if (!mounted) return;
    MiniToast.show(context, 'Removed');
  }

  Future<void> _removeBook(SearchSource source, BookStub book) async {
    final url = book.url;
    if (url == null) return;
    final confirmed = await _confirmRemove(context, book.title);
    if (confirmed != true || !mounted) return;
    await ref.read(sourceImporterProvider).removeBookByUrl(url);
    if (!mounted) return;
    MiniToast.show(context, 'Removed');
  }

  Future<bool?> _confirmRemove(BuildContext context, String title) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from library?'),
        content: Text('"$title" and its reading progress will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _addArticle(FeedSource source, ArticleStub stub) async {
    final importer = ref.read(sourceImporterProvider);
    MiniToast.show(context, 'Adding…');
    try {
      await importer.importArticle(source: source, stub: stub);
      if (!mounted) return;
      MiniToast.show(context, 'Added ✓');
    } catch (e) {
      if (!mounted) return;
      // Failures are worth a visible, dismissible message.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Add failed: $e')));
    }
  }

  Future<void> _addBook(SearchSource source, BookStub book) async {
    final importer = ref.read(sourceImporterProvider);
    final task = ImportTask(
      taskId: book.id,
      sourceLabel: source.name,
      title: book.title,
    );

    // Show a non-dismissable progress sheet driven by the live task state.
    final ctxBeforeAwait = context;
    unawaited(showModalBottomSheet<void>(
      context: ctxBeforeAwait,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return _ImportProgressSheet(
          task: task,
          onCancel: () {
            task.cancel();
            Navigator.of(sheetCtx).maybePop();
          },
        );
      },
    ));

    Object? error;
    try {
      await importer.importBook(
        source: source,
        book: book,
        task: task,
        onTaskUpdate: (_) {/* the sheet polls via its own state */},
      );
    } catch (e) {
      error = e;
    }

    if (!mounted) return;
    // Close the progress sheet (if it's still open).
    Navigator.of(context, rootNavigator: true).maybePop();

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
      return;
    }
    MiniToast.show(context, 'Added ✓');
  }
}

class _SearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final List<({String id, String label})> chips;
  final String sourceFilter;
  final ValueChanged<String> onSourceFilterChanged;
  final SearchOrder order;
  final ValueChanged<SearchOrder> onOrderChanged;
  final CompletionFilter completion;
  final ValueChanged<CompletionFilter> onCompletionChanged;
  final bool showSyosetuFilters;
  const _SearchHeader({
    required this.controller,
    required this.onChanged,
    required this.chips,
    required this.sourceFilter,
    required this.onSourceFilterChanged,
    required this.order,
    required this.onOrderChanged,
    required this.completion,
    required this.onCompletionChanged,
    required this.showSyosetuFilters,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search Japanese books or news…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.05),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < chips.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        _Chip(
                          label: chips[i].label,
                          selected: sourceFilter == chips[i].id,
                          onTap: () => onSourceFilterChanged(chips[i].id),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (showSyosetuFilters)
                PopupMenuButton<_SyosetuMenu>(
                  tooltip: 'Filters',
                  icon: const Icon(Icons.tune),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      enabled: false,
                      child: Text('Order',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    for (final o in SearchOrder.values)
                      PopupMenuItem(
                        value: _SyosetuMenu(order: o),
                        child: Row(children: [
                          Icon(o == order ? Icons.check : Icons.circle_outlined,
                              size: 16),
                          const SizedBox(width: 8),
                          Text(_orderLabel(o)),
                        ]),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      enabled: false,
                      child: Text('Status',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    for (final c in CompletionFilter.values)
                      PopupMenuItem(
                        value: _SyosetuMenu(completion: c),
                        child: Row(children: [
                          Icon(c == completion ? Icons.check : Icons.circle_outlined,
                              size: 16),
                          const SizedBox(width: 8),
                          Text(_completionLabel(c)),
                        ]),
                      ),
                  ],
                  onSelected: (m) {
                    if (m.order != null) onOrderChanged(m.order!);
                    if (m.completion != null) onCompletionChanged(m.completion!);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _orderLabel(SearchOrder o) {
    switch (o) {
      case SearchOrder.rating: return 'Highest rated';
      case SearchOrder.bookmarks: return 'Most bookmarked';
      case SearchOrder.weekly: return 'Weekly trending';
      case SearchOrder.newest: return 'Newest';
      case SearchOrder.oldest: return 'Oldest';
      case SearchOrder.longest: return 'Longest';
      case SearchOrder.shortest: return 'Shortest';
    }
  }

  static String _completionLabel(CompletionFilter c) {
    switch (c) {
      case CompletionFilter.any: return 'Any status';
      case CompletionFilter.complete: return 'Completed only';
      case CompletionFilter.ongoing: return 'Ongoing only';
    }
  }
}

class _SyosetuMenu {
  final SearchOrder? order;
  final CompletionFilter? completion;
  const _SyosetuMenu({this.order, this.completion});
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.onSurface.withValues(alpha: 0.18)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

class _FeedSection extends ConsumerStatefulWidget {
  final FeedSource source;
  final String query;
  final Future<void> Function(FeedSource, ArticleStub) onAdd;
  final Future<void> Function(FeedSource, ArticleStub) onRemove;
  const _FeedSection({
    super.key,
    required this.source,
    required this.query,
    required this.onAdd,
    required this.onRemove,
  });
  @override
  ConsumerState<_FeedSection> createState() => _FeedSectionState();
}

class _FeedSectionState extends ConsumerState<_FeedSection> {
  Future<List<ArticleStub>>? _future;
  bool _bulkBusy = false;

  @override
  void initState() {
    super.initState();
    _future = widget.source.list();
  }

  /// Bulk import straight from the newsstand — the fast path most readers
  /// want instead of tapping "+" on each headline.
  Future<void> _bulkFetch(FeedFetchMode mode) async {
    if (_bulkBusy) return;
    setState(() => _bulkBusy = true);
    MiniToast.show(context, '${mode.label}…');
    final result = await ref
        .read(feedSyncProvider)
        .run(sources: [widget.source], mode: mode);
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    MiniToast.show(context, result.summary);
  }

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      icon: Icons.article_outlined,
      label: widget.source.name,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_bulkBusy)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          PopupMenuButton<FeedFetchMode>(
            tooltip: 'Add stories in bulk',
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.playlist_add, size: 20),
            enabled: !_bulkBusy,
            onSelected: _bulkFetch,
            itemBuilder: (ctx) => [
              for (final m in FeedFetchMode.values)
                PopupMenuItem(value: m, child: Text(m.label)),
            ],
          ),
          IconButton(
            tooltip: 'Read this paper',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.chrome_reader_mode_outlined, size: 19),
            onPressed: () => context.go('/news?paper=${widget.source.id}'),
          ),
        ],
      ),
      child: FutureBuilder<List<ArticleStub>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _LoadingRow();
          }
          if (snap.hasError) {
            return _ErrorRow(
              message: snap.error.toString(),
              onRetry: () => setState(() => _future = widget.source.list()),
            );
          }
          var items = snap.data ?? const <ArticleStub>[];
          if (widget.query.isNotEmpty) {
            final needle = widget.query.toLowerCase();
            items = items
                .where((a) => a.title.toLowerCase().contains(needle))
                .toList();
          }
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                widget.query.isEmpty
                    ? 'No articles available right now.'
                    : 'No articles match "${widget.query}".',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6)),
              ),
            );
          }
          final imported = ref
                  .watch(importedArticleUrlsProvider(widget.source.id))
                  .valueOrNull ??
              const <String>{};
          return Column(
            children: [
              for (final a in items.take(20))
                _ArticleTile(
                  stub: a,
                  added: imported.contains(a.sourceUrl),
                  onAdd: () => widget.onAdd(widget.source, a),
                  onRemove: () => widget.onRemove(widget.source, a),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchSection extends ConsumerStatefulWidget {
  final SearchSource source;
  final SearchQuery query;
  final Future<void> Function(SearchSource, BookStub) onAdd;
  final Future<void> Function(SearchSource, BookStub) onRemove;
  const _SearchSection({
    super.key,
    required this.source,
    required this.query,
    required this.onAdd,
    required this.onRemove,
  });
  @override
  ConsumerState<_SearchSection> createState() => _SearchSectionState();
}

class _SearchSectionState extends ConsumerState<_SearchSection> {
  late Future<List<BookStub>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.source.search(widget.query);
  }

  @override
  void didUpdateWidget(covariant _SearchSection old) {
    super.didUpdateWidget(old);
    if (old.query.word != widget.query.word ||
        old.query.order != widget.query.order ||
        old.query.completion != widget.query.completion) {
      _future = widget.source.search(widget.query);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      icon: Icons.menu_book_outlined,
      label: '${widget.source.name}'
          '${widget.query.word == null ? " — top rated" : ""}',
      child: FutureBuilder<List<BookStub>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _LoadingRow();
          }
          if (snap.hasError) {
            return _ErrorRow(
              message: snap.error.toString(),
              onRetry: () =>
                  setState(() => _future = widget.source.search(widget.query)),
            );
          }
          final items = snap.data ?? const <BookStub>[];
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                widget.query.word == null
                    ? 'No results.'
                    : 'No books match "${widget.query.word}".',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6)),
              ),
            );
          }
          final imported = ref.watch(importedBookUrlsProvider);
          return Column(
            children: [
              for (final b in items)
                _BookTile(
                  book: b,
                  added: b.url != null && imported.contains(b.url),
                  onAdd: () => widget.onAdd(widget.source, b),
                  onRemove: () => widget.onRemove(widget.source, b),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  /// Section-level actions (bulk fetch, "read this paper"), right-aligned in
  /// the header rule.
  final Widget? trailing;
  const _SectionShell({
    required this.icon,
    required this.label,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: cs.primary,
                      )),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing!,
                ],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ArticleTile extends StatefulWidget {
  final ArticleStub stub;
  final bool added;
  final Future<void> Function() onAdd;
  final Future<void> Function() onRemove;
  const _ArticleTile({
    required this.stub,
    required this.added,
    required this.onAdd,
    required this.onRemove,
  });
  @override
  State<_ArticleTile> createState() => _ArticleTileState();
}

class _ArticleTileState extends State<_ArticleTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final published = widget.stub.publishedAt == null
        ? null
        : _formatDate(DateTime.fromMillisecondsSinceEpoch(widget.stub.publishedAt!));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: _busy
              ? null
              : () => _run(widget.added ? widget.onRemove : widget.onAdd),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.stub.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25),
                      ),
                      if (widget.stub.summary != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.stub.summary!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: cs.onSurface.withValues(alpha: 0.7)),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            // Rough estimate from title + teaser only — the
                            // full text isn't downloaded until import.
                            DifficultyBadge(
                              text:
                                  '${widget.stub.title} ${widget.stub.summary ?? ""}',
                              approx: true,
                            ),
                            if (published != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                published,
                                style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        cs.onSurface.withValues(alpha: 0.55)),
                              ),
                            ],
                            if (widget.added) ...[
                              const SizedBox(width: 8),
                              Text(
                                'added',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : widget.added
                          ? IconButton(
                              tooltip: 'In library — tap to remove',
                              onPressed: () => _run(widget.onRemove),
                              icon: Icon(Icons.check_circle,
                                  color: cs.primary),
                            )
                          : IconButton(
                              tooltip: 'Add to library',
                              onPressed: () => _run(widget.onAdd),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookTile extends StatefulWidget {
  final BookStub book;
  final bool added;
  final Future<void> Function() onAdd;
  final Future<void> Function() onRemove;
  const _BookTile({
    required this.book,
    required this.added,
    required this.onAdd,
    required this.onRemove,
  });
  @override
  State<_BookTile> createState() => _BookTileState();
}

class _BookTileState extends State<_BookTile> {
  bool _adding = false;

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await widget.onAdd();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _adding = true);
    try {
      await widget.onRemove();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final book = widget.book;
    final rating = (book.extra['rating'] as num?)?.toDouble();
    final bookmarks = (book.extra['bookmarks'] as num?)?.toInt();
    final isSerial = book.extra['isSerial'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: _adding ? null : () => _showDetail(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BookThumb(url: book.imageUrl, title: book.title),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25),
                      ),
                      if (book.author != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            book.author!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withValues(alpha: 0.7)),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          if (rating != null && rating > 0)
                            _BookStat(
                                icon: Icons.star,
                                label: rating.toStringAsFixed(0)),
                          if (bookmarks != null && bookmarks > 0)
                            _BookStat(
                                icon: Icons.bookmark_outline,
                                label: _compactNumber(bookmarks)),
                          if (book.chapterCount != null && book.chapterCount! > 0)
                            _BookStat(
                                icon: Icons.menu_book_outlined,
                                label: '${book.chapterCount} ch'),
                          if (!isSerial)
                            const _BookStat(
                                icon: Icons.bookmark_added_outlined,
                                label: 'short'),
                          if (book.isComplete == true)
                            const _BookStat(
                                icon: Icons.check_circle_outline,
                                label: 'complete'),
                          if (widget.added)
                            const _BookStat(
                                icon: Icons.library_add_check_outlined,
                                label: 'added'),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: _adding
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : widget.added
                          ? IconButton(
                              tooltip: 'In library — tap to remove',
                              onPressed: _remove,
                              icon: Icon(Icons.check_circle, color: cs.primary),
                            )
                          : IconButton(
                              tooltip: 'Add to library',
                              onPressed: _add,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(BuildContext context) async {
    final book = widget.book;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (ctx, ctrl) {
            return ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                Text(book.title,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.2)),
                if (book.author != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(book.author!,
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7))),
                  ),
                const SizedBox(height: 12),
                if (book.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in book.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(t,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w500)),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                if (book.summary != null && book.summary!.isNotEmpty)
                  Text(book.summary!,
                      style: const TextStyle(fontSize: 14, height: 1.55)),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _add();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add to library'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _BookThumb extends StatelessWidget {
  final String? url;
  final String title;
  const _BookThumb({this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 56,
      height: 80,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        title.isEmpty ? '📖' : title.characters.first,
        style: TextStyle(
            fontSize: 24, fontWeight: FontWeight.w700, color: cs.primary),
      ),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url!,
        width: 56,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _BookStat extends StatelessWidget {
  final IconData icon;
  final String label;
  const _BookStat({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: cs.onSurface.withValues(alpha: 0.6)),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
      ],
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Row(children: [
        SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Loading…', style: TextStyle(fontSize: 13)),
      ]),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRow({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ImportProgressSheet extends StatefulWidget {
  final ImportTask task;
  final VoidCallback onCancel;
  const _ImportProgressSheet({required this.task, required this.onCancel});
  @override
  State<_ImportProgressSheet> createState() => _ImportProgressSheetState();
}

class _ImportProgressSheetState extends State<_ImportProgressSheet> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Poll the task so the UI rebuilds as progress advances. Cheap and
    // entirely local — the actual work runs as a separate async future
    // updating the task object.
    _poll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final task = widget.task;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, height: 1.2)),
            const SizedBox(height: 4),
            Text(task.sourceLabel,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: task.progress),
            const SizedBox(height: 8),
            Text(task.status,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 16),
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

String _compactNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}
