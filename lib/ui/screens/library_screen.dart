import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/collection.dart';
import '../../data/models/novel.dart';
import '../../data/models/reader_prefs.dart';
import '../../providers/collections_provider.dart';
import '../../providers/novels_provider.dart';
import '../../providers/prefs_provider.dart';
import '../../services/sample/sample_content.dart';
import '../widgets/book_cover.dart';
import '../widgets/mini_toast.dart';
import '../widgets/novel_card.dart';
import '../widgets/view_mode_button.dart';

enum _StatusFilter { all, reading, finished, unread }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _StatusFilter _status = _StatusFilter.all;
  ContentType? _contentType;
  int? _jlptLevel; // 1..5, null = any
  String? _language;
  String? _collectionId;
  bool _favoritesOnly = false;
  final Set<String> _tagFilter = <String>{};

  bool get _anyFilterActive =>
      _status != _StatusFilter.all ||
      _contentType != null ||
      _jlptLevel != null ||
      _language != null ||
      _collectionId != null ||
      _favoritesOnly ||
      _tagFilter.isNotEmpty;

  /// A rolling news feed isn't a book — opening it drops you on that paper's
  /// front page rather than at whichever article you last read.
  void _open(BuildContext context, NovelMeta m) {
    if (m.sourceType == SourceType.feed) {
      final paper = m.sourceId ??
          (m.id.startsWith('feed:') ? m.id.substring(5) : m.id);
      context.go('/news?paper=$paper');
      return;
    }
    context.go('/reader/${m.id}');
  }

  void _clearFilters() => setState(() {
        _status = _StatusFilter.all;
        _contentType = null;
        _jlptLevel = null;
        _language = null;
        _collectionId = null;
        _favoritesOnly = false;
        _tagFilter.clear();
      });

  @override
  Widget build(BuildContext context) {
    final novels = ref.watch(novelsProvider);
    final prefs = ref.watch(readerPrefsProvider);
    final collections = ref.watch(collectionsProvider);
    final filtered = _filter(novels);
    final sorted = _sort(filtered, prefs.librarySort);
    final continueReading = _continueReading(novels);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LinguaPop'),
        actions: [
          ViewModeButton(
            mode: prefs.libraryViewMode,
            onChanged: (m) =>
                ref.read(readerPrefsProvider.notifier).setLibraryViewMode(m),
          ),
          IconButton(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortSheet(context),
          ),
          IconButton(
            tooltip: 'News',
            icon: const Icon(Icons.newspaper_outlined),
            onPressed: () => context.go('/news'),
          ),
          IconButton(
            tooltip: 'Vocab',
            icon: const Icon(Icons.style_outlined),
            onPressed: () => context.go('/vocab'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (novels.isNotEmpty)
            _FilterBar(
              status: _status,
              onStatusChanged: (s) => setState(() => _status = s),
              contentType: _contentType,
              languages: _availableLanguages(novels),
              language: _language,
              jlptLevel: _jlptLevel,
              favoritesOnly: _favoritesOnly,
              hasFavorites: novels.any((m) => m.favorite),
              collections: collections,
              collectionId: _collectionId,
              tags: _availableTags(novels),
              tagFilter: _tagFilter,
              hasJlptData: novels.any((m) => m.jlptStats != null),
              onContentTypePicked: (c) =>
                  setState(() => _contentType = _contentType == c ? null : c),
              onLanguagePicked: (l) =>
                  setState(() => _language = _language == l ? null : l),
              onJlptPicked: (l) =>
                  setState(() => _jlptLevel = _jlptLevel == l ? null : l),
              onFavoritesToggled: () =>
                  setState(() => _favoritesOnly = !_favoritesOnly),
              onCollectionPicked: (id) =>
                  setState(() => _collectionId = _collectionId == id ? null : id),
              onTagPicked: (t) {
                setState(() {
                  if (_tagFilter.contains(t)) {
                    _tagFilter.remove(t);
                  } else {
                    _tagFilter.add(t);
                  }
                });
              },
              onClear: _clearFilters,
            ),
          Expanded(
            child: novels.isEmpty
                ? const _EmptyLibrary()
                : sorted.isEmpty
                    ? _EmptyFilter(onClear: _clearFilters)
                    : CustomScrollView(
                        slivers: [
                          if (!_anyFilterActive && continueReading.isNotEmpty)
                            SliverToBoxAdapter(
                              child: _ContinueReadingRow(
                                novels: continueReading,
                                onTap: (m) => _open(context, m),
                                onLongPress: (m) => context.go('/book/${m.id}'),
                              ),
                            ),
                          _LibrarySliver(
                            novels: sorted,
                            viewMode: prefs.libraryViewMode,
                            onTap: (m) => _open(context, m),
                            onOpenDetail: (m) => context.go('/book/${m.id}'),
                          ),
                        ],
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }

  // ─────────── filtering / sorting ───────────

  List<NovelMeta> _filter(List<NovelMeta> all) {
    return all.where((m) {
      final progress = m.chapterCount == 0
          ? 0.0
          : m.lastReadChapter / m.chapterCount;
      switch (_status) {
        case _StatusFilter.reading:
          if (progress <= 0 || progress >= 1) return false;
        case _StatusFilter.finished:
          if (progress < 1 || m.chapterCount == 0) return false;
        case _StatusFilter.unread:
          if (progress != 0) return false;
        case _StatusFilter.all:
          break;
      }
      if (_favoritesOnly && !m.favorite) return false;
      if (_contentType != null && m.contentType != _contentType) return false;
      if (_language != null && m.sourceLanguage != _language) return false;
      if (_jlptLevel != null && m.jlptStats?.difficultyBucket != _jlptLevel) {
        return false;
      }
      if (_collectionId != null &&
          !(m.collectionIds ?? const <String>[]).contains(_collectionId)) {
        return false;
      }
      if (_tagFilter.isNotEmpty) {
        final tags = m.tags ?? const <String>[];
        if (!_tagFilter.every(tags.contains)) return false;
      }
      return true;
    }).toList();
  }

  /// In-progress books, most recently read first. Drives the "Continue reading"
  /// row. Falls back to addedAt for books opened before lastReadAt existed.
  List<NovelMeta> _continueReading(List<NovelMeta> all) {
    final list = all.where((m) {
      if (m.chapterCount == 0) return false;
      final p = m.lastReadChapter / m.chapterCount;
      return p > 0 && p < 1;
    }).toList()
      ..sort((a, b) =>
          (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));
    return list.take(12).toList();
  }

  List<NovelMeta> _sort(List<NovelMeta> ns, LibrarySort s) {
    final list = [...ns];
    switch (s) {
      case LibrarySort.recent:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case LibrarySort.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case LibrarySort.difficulty:
        list.sort((a, b) {
          final aS = a.jlptStats?.difficultyScore ?? 99;
          final bS = b.jlptStats?.difficultyScore ?? 99;
          return aS.compareTo(bS);
        });
      case LibrarySort.progress:
        double progress(NovelMeta m) =>
            m.chapterCount == 0 ? 0 : m.lastReadChapter / m.chapterCount;
        list.sort((a, b) {
          final ap = progress(a), bp = progress(b);
          final aActive = ap > 0 && ap < 1;
          final bActive = bp > 0 && bp < 1;
          if (aActive != bActive) return aActive ? -1 : 1;
          return bp.compareTo(ap);
        });
    }
    return list;
  }

  List<String> _availableLanguages(List<NovelMeta> ns) {
    final set = <String>{for (final m in ns) m.sourceLanguage};
    final out = set.toList()..sort();
    return out;
  }

  List<String> _availableTags(List<NovelMeta> ns) {
    final set = <String>{};
    for (final m in ns) {
      if (m.tags != null) set.addAll(m.tags!);
    }
    final list = set.toList()..sort();
    return list;
  }

  // ─────────── sheets ───────────

  Future<void> _showSortSheet(BuildContext context) async {
    final current = ref.read(readerPrefsProvider).librarySort;
    final picked = await showModalBottomSheet<LibrarySort>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in LibrarySort.values)
              ListTile(
                leading: Icon(s == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: Text(_sortLabel(s)),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await ref.read(readerPrefsProvider.notifier).setLibrarySort(picked);
    }
  }

  String _sortLabel(LibrarySort s) {
    switch (s) {
      case LibrarySort.recent: return 'Recently added';
      case LibrarySort.title: return 'Title (A→Z)';
      case LibrarySort.difficulty: return 'Difficulty (easiest first)';
      case LibrarySort.progress: return 'Progress (in-progress first)';
    }
  }

  Future<void> _showAddSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Browse sources'),
              subtitle: const Text('NHK Easy, Syosetu, …'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/sources');
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('Import EPUB / TXT'),
              subtitle: const Text('From device storage'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/import');
              },
            ),
          ],
        ),
      ),
    );
  }

}

class _LibrarySliver extends StatelessWidget {
  final List<NovelMeta> novels;
  final LibraryViewMode viewMode;
  final ValueChanged<NovelMeta> onTap;
  final ValueChanged<NovelMeta> onOpenDetail;
  const _LibrarySliver({
    required this.novels,
    required this.viewMode,
    required this.onTap,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    switch (viewMode) {
      case LibraryViewMode.grid:
        // Target ~150 px wide tiles, but never fewer than 2 columns; clamp at
        // 6 for tablets/desktops so things don't look comically small.
        final w = MediaQuery.sizeOf(context).width;
        final cols = (w / 165).floor().clamp(2, 6);
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 10,
              mainAxisSpacing: 8,
              // Cover (2:3) + ~2-line title + author. Generous enough to never
              // clip the text block.
              childAspectRatio: 0.50,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final m = novels[i];
                return NovelCard(
                  meta: m,
                  onTap: () => onTap(m),
                  onLongPress: () => onOpenDetail(m),
                );
              },
              childCount: novels.length,
            ),
          ),
        );
      case LibraryViewMode.list:
        return SliverPadding(
          padding: const EdgeInsets.only(top: 4, bottom: 96),
          sliver: SliverList.separated(
            itemCount: novels.length,
            separatorBuilder: (ctx, i) => Divider(
              height: 1,
              indent: 72,
              color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.06),
            ),
            itemBuilder: (ctx, i) {
              final m = novels[i];
              return NovelListRow(
                meta: m,
                onTap: () => onTap(m),
                onLongPress: () => onOpenDetail(m),
              );
            },
          ),
        );
      case LibraryViewMode.card:
        return SliverPadding(
          padding: const EdgeInsets.only(top: 4, bottom: 96),
          sliver: SliverList.builder(
            itemCount: novels.length,
            itemBuilder: (ctx, i) {
              final m = novels[i];
              return NovelWideCard(
                meta: m,
                onTap: () => onTap(m),
                onLongPress: () => onOpenDetail(m),
              );
            },
          ),
        );
    }
  }
}

class _ContinueReadingRow extends StatelessWidget {
  final List<NovelMeta> novels;
  final ValueChanged<NovelMeta> onTap;
  final ValueChanged<NovelMeta> onLongPress;
  const _ContinueReadingRow({
    required this.novels,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text('Continue reading',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.85))),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: novels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (ctx, i) {
              final m = novels[i];
              final progress = (m.lastReadChapter / m.chapterCount)
                  .clamp(0.0, 1.0);
              return GestureDetector(
                onTap: () => onTap(m),
                onLongPress: () => onLongPress(m),
                child: SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          BookCover(meta: m, width: 92),
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 5,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                backgroundColor:
                                    Colors.black.withValues(alpha: 0.35),
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Divider(
          height: 18,
          color: cs.onSurface.withValues(alpha: 0.06),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  final _StatusFilter status;
  final ValueChanged<_StatusFilter> onStatusChanged;
  final ContentType? contentType;
  final ValueChanged<ContentType> onContentTypePicked;
  final List<String> languages;
  final String? language;
  final ValueChanged<String> onLanguagePicked;
  final int? jlptLevel;
  final bool hasJlptData;
  final ValueChanged<int> onJlptPicked;
  final bool favoritesOnly;
  final bool hasFavorites;
  final VoidCallback onFavoritesToggled;
  final List<Collection> collections;
  final String? collectionId;
  final ValueChanged<String> onCollectionPicked;
  final List<String> tags;
  final Set<String> tagFilter;
  final ValueChanged<String> onTagPicked;
  final VoidCallback onClear;

  const _FilterBar({
    required this.status,
    required this.onStatusChanged,
    required this.contentType,
    required this.onContentTypePicked,
    required this.languages,
    required this.language,
    required this.onLanguagePicked,
    required this.jlptLevel,
    required this.hasJlptData,
    required this.onJlptPicked,
    required this.favoritesOnly,
    required this.hasFavorites,
    required this.onFavoritesToggled,
    required this.collections,
    required this.collectionId,
    required this.onCollectionPicked,
    required this.tags,
    required this.tagFilter,
    required this.onTagPicked,
    required this.onClear,
  });

  bool get _anyActive =>
      status != _StatusFilter.all ||
      contentType != null ||
      language != null ||
      jlptLevel != null ||
      favoritesOnly ||
      collectionId != null ||
      tagFilter.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        children: [
          // Row 1: status chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              _Chip(
                label: 'All',
                selected: status == _StatusFilter.all,
                onTap: () => onStatusChanged(_StatusFilter.all),
              ),
              const SizedBox(width: 6),
              _Chip(
                label: 'Reading',
                selected: status == _StatusFilter.reading,
                onTap: () => onStatusChanged(_StatusFilter.reading),
              ),
              const SizedBox(width: 6),
              _Chip(
                label: 'Unread',
                selected: status == _StatusFilter.unread,
                onTap: () => onStatusChanged(_StatusFilter.unread),
              ),
              const SizedBox(width: 6),
              _Chip(
                label: 'Finished',
                selected: status == _StatusFilter.finished,
                onTap: () => onStatusChanged(_StatusFilter.finished),
              ),
              if (hasFavorites) ...[
                const SizedBox(width: 16),
                _Chip(
                  label: '♥ Favorites',
                  selected: favoritesOnly,
                  onTap: onFavoritesToggled,
                ),
              ],
              const SizedBox(width: 16),
              if (collections.isNotEmpty) ...[
                _PopupChip(
                  label: collectionId == null
                      ? 'Collection'
                      : (collections
                              .where((c) => c.id == collectionId)
                              .map((c) => c.name)
                              .join())
                          .toString(),
                  selected: collectionId != null,
                  items: [
                    for (final c in collections)
                      _PopupChipItem(
                          label: c.name,
                          selected: c.id == collectionId,
                          onTap: () => onCollectionPicked(c.id)),
                  ],
                ),
                const SizedBox(width: 6),
              ],
              _PopupChip(
                label: contentType == null
                    ? 'Type'
                    : _contentTypeLabel(contentType!),
                selected: contentType != null,
                items: [
                  for (final c in ContentType.values)
                    _PopupChipItem(
                        label: _contentTypeLabel(c),
                        selected: c == contentType,
                        onTap: () => onContentTypePicked(c)),
                ],
              ),
              if (languages.length > 1) ...[
                const SizedBox(width: 6),
                _PopupChip(
                  label: language == null
                      ? 'Language'
                      : language!.toUpperCase(),
                  selected: language != null,
                  items: [
                    for (final l in languages)
                      _PopupChipItem(
                          label: l.toUpperCase(),
                          selected: l == language,
                          onTap: () => onLanguagePicked(l)),
                  ],
                ),
              ],
              if (hasJlptData) ...[
                const SizedBox(width: 6),
                _PopupChip(
                  label: jlptLevel == null ? 'JLPT' : 'N$jlptLevel',
                  selected: jlptLevel != null,
                  items: [
                    for (final lv in [5, 4, 3, 2, 1])
                      _PopupChipItem(
                          label: 'N$lv',
                          selected: lv == jlptLevel,
                          onTap: () => onJlptPicked(lv)),
                  ],
                ),
              ],
              if (_anyActive) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear filters',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: const Icon(Icons.cancel, size: 18),
                ),
              ],
            ]),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: tags.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final t = tags[i];
                  return _Chip(
                    label: t,
                    selected: tagFilter.contains(t),
                    onTap: () => onTagPicked(t),
                    dense: true,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _contentTypeLabel(ContentType c) {
    switch (c) {
      case ContentType.news: return 'News';
      case ContentType.lightNovel: return 'Light novel';
      case ContentType.webNovel: return 'Web novel';
      case ContentType.shortStory: return 'Short story';
      case ContentType.novel: return 'Novel';
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dense;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(
            horizontal: dense ? 11 : 14, vertical: dense ? 5 : 7),
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
            fontSize: dense ? 11.5 : 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

class _PopupChip extends StatelessWidget {
  final String label;
  final bool selected;
  final List<_PopupChipItem> items;
  const _PopupChip({
    required this.label,
    required this.selected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<int>(
      tooltip: label,
      itemBuilder: (ctx) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(children: [
              Icon(items[i].selected ? Icons.check : Icons.circle_outlined,
                  size: 16),
              const SizedBox(width: 8),
              Text(items[i].label),
            ]),
          ),
      ],
      onSelected: (i) => items[i].onTap(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.onSurface.withValues(alpha: 0.18)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? cs.onPrimary : cs.onSurface,
              ),
            ),
            Icon(Icons.arrow_drop_down,
                size: 18,
                color: selected
                    ? cs.onPrimary
                    : cs.onSurface.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

class _PopupChipItem {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PopupChipItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });
}

class _EmptyLibrary extends ConsumerStatefulWidget {
  const _EmptyLibrary();
  @override
  ConsumerState<_EmptyLibrary> createState() => _EmptyLibraryState();
}

class _EmptyLibraryState extends ConsumerState<_EmptyLibrary> {
  bool _loading = false;

  Future<void> _loadSample() async {
    setState(() => _loading = true);
    try {
      await SampleContentService(ref.read(novelsProvider.notifier)).loadAll();
      if (mounted) MiniToast.show(context, 'Sample content added ✓');
    } catch (_) {
      if (mounted) MiniToast.show(context, 'Could not load sample content');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 64, color: cs.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            const Text('Your library is empty',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              kIsWeb
                  ? 'Tap "Add" to import an EPUB / TXT file, or try the sample content below.'
                  : 'Tap "Add" to browse sources or import an EPUB / TXT file.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loading ? null : _loadSample,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_stories_outlined, size: 18),
                label: const Text('Load sample story + article'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyFilter extends StatelessWidget {
  final VoidCallback onClear;
  const _EmptyFilter({required this.onClear});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_off_outlined,
                size: 48, color: cs.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            const Text('No books match these filters.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextButton(onPressed: onClear, child: const Text('Clear filters')),
          ],
        ),
      ),
    );
  }
}
