import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/chapter.dart';
import '../../data/models/jp_token.dart';
import '../../data/models/novel.dart';
import '../../data/models/reader_prefs.dart';
import '../../data/models/vocab_entry.dart';
import '../../providers/novels_provider.dart';
import '../../providers/prefs_provider.dart';
import '../../providers/translation_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../services/translation/translate_service.dart';
import '../widgets/japanese_text.dart';
import '../widgets/word_popover.dart';
import 'reader_paginator.dart';

const _uuid = Uuid();

class ReaderScreen extends ConsumerStatefulWidget {
  final String novelId;

  /// When set (e.g. deep-linked from the news hub via `?ch=`), open this
  /// chapter instead of the last-read one.
  final int? initialChapter;

  const ReaderScreen({super.key, required this.novelId, this.initialChapter});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  NovelBody? _body;
  int _chapterIdx = 0;
  bool _chromeVisible = true;

  /// Position within the current chapter, as the active layout interprets it
  /// (scroll mode: scrollOffset in px; paged mode: page index). Persisted to
  /// `NovelMeta.lastReadOffset`.
  int _position = 0;

  Timer? _saveDebounce;

  // Active selection-translation state. `_selectionText` mirrors whatever the
  // SelectionArea is currently exposing; `_selectionTranslation` is non-null
  // once a translation request resolves. `_selectionTranslating` is true while
  // a request is in flight so the banner can show a spinner.
  String _selectionText = '';
  String? _selectionTranslation;
  bool _selectionTranslating = false;
  int _selectionRequestId = 0;
  Timer? _selectionDebounce;

  // Owned focus node for the SelectionArea — unfocusing clears the native
  // selection handles, which is how single-tap-to-deselect works below.
  final FocusNode _selectionFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final meta = _meta();
    final body = await ref
        .read(novelsProvider.notifier)
        .loadBody(widget.novelId);
    if (!mounted) return;
    final target = widget.initialChapter ?? meta.lastReadChapter;
    setState(() {
      _body = body;
      _chapterIdx = target.clamp(0, (body?.chapters.length ?? 1) - 1);
      // A deep-linked chapter starts from the top; resuming the last-read
      // chapter restores the saved offset.
      _position = _chapterIdx == meta.lastReadChapter ? meta.lastReadOffset : 0;
    });
  }

  NovelMeta _meta() => ref
      .read(novelsProvider)
      .firstWhere(
        (m) => m.id == widget.novelId,
        orElse: () => NovelMeta(id: widget.novelId, title: '?', addedAt: 0),
      );

  /// Called by both layouts whenever the user's position inside the chapter
  /// changes. Debounced so we don't write to Hive on every scroll tick.
  void _onPositionChanged(int newPos) {
    _position = newPos;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _persistProgress);
  }

  Future<void> _persistProgress() async {
    final m = ref.read(novelsProvider.notifier).findById(widget.novelId);
    if (m == null) return;
    await ref
        .read(novelsProvider.notifier)
        .updateMeta(
          m.copyWith(
            lastReadChapter: _chapterIdx,
            lastReadOffset: _position,
            lastReadAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _selectionDebounce?.cancel();
    _selectionFocus.dispose();
    super.dispose();
  }

  /// Single-tap on the chapter background: only meaningful when a selection
  /// is active. Drop focus on the SelectionArea so its handles vanish — that
  /// causes `onSelectionChanged(null)` to fire, which already resets the
  /// banner via [_onSelectionChanged].
  void _onBackgroundTap() {
    if (_selectionText.isNotEmpty) _selectionFocus.unfocus();
  }

  /// Receives every selection change from SelectionArea (drag handles,
  /// long-press extension, tap-to-clear). Empty string → clear the banner;
  /// otherwise debounce briefly before kicking off a translation so we don't
  /// fire a request on every char-level extension while the user is still
  /// dragging.
  void _onSelectionChanged(String text) {
    final trimmed = text.trim();
    if (trimmed == _selectionText) return;
    _selectionText = trimmed;

    if (trimmed.isEmpty) {
      _selectionDebounce?.cancel();
      setState(() {
        _selectionTranslation = null;
        _selectionTranslating = false;
      });
      return;
    }

    _selectionDebounce?.cancel();
    _selectionDebounce = Timer(
      const Duration(milliseconds: 350),
      _runSelectionTranslate,
    );
  }

  Future<void> _saveSelectionToVocab(NovelMeta meta, Chapter chapter) async {
    final text = _selectionText;
    if (text.isEmpty) return;
    final translation = _selectionTranslation;
    final entry = VocabEntry(
      id: _uuid.v4(),
      base: text,
      surface: text,
      glosses: translation == null || translation.startsWith('⚠')
          ? const []
          : [translation],
      exampleSentence: text,
      sourceNovelId: meta.id,
      sourceNovelTitle: meta.title,
      sourceChapterId: chapter.id,
      sourceChapterIndex: _chapterIdx,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      isPhrase: true,
    );
    await ref.read(vocabProvider.notifier).upsert(entry);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "${_truncate(text)}" to vocab.')),
    );
  }

  Future<void> _runSelectionTranslate() async {
    final reqId = ++_selectionRequestId;
    final text = _selectionText;
    if (text.isEmpty) return;
    final meta = _meta();
    if (!mounted) return;
    setState(() {
      _selectionTranslation = null;
      _selectionTranslating = true;
    });
    final svc = ref.read(translateServiceProvider);
    try {
      final result = await svc.translateText(
        text,
        from: meta.sourceLanguage,
        to: meta.targetLanguage,
      );
      if (!mounted || reqId != _selectionRequestId) return;
      setState(() {
        _selectionTranslation = result;
        _selectionTranslating = false;
      });
    } catch (e) {
      if (!mounted || reqId != _selectionRequestId) return;
      setState(() {
        _selectionTranslation =
            '⚠ ${e.toString().replaceFirst("Exception: ", "")}';
        _selectionTranslating = false;
      });
    }
  }

  void _gotoChapter(int idx, {int positionWithin = 0}) {
    final body = _body;
    if (body == null) return;
    final clamped = idx.clamp(0, body.chapters.length - 1);
    if (clamped == _chapterIdx && positionWithin == _position) return;
    setState(() {
      _chapterIdx = clamped;
      _position = positionWithin;
    });
    _persistProgress();
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  Future<void> _translateChapter(Chapter chapter, NovelMeta meta) async {
    final service = ref.read(translateServiceProvider);
    final cancel = CancelToken();
    final progress = ValueNotifier<double>(0);
    final messenger = ScaffoldMessenger.of(context);

    final ctxBefore = context;
    final sheetFuture = showModalBottomSheet<void>(
      context: ctxBefore,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return _TranslateProgressSheet(
          title: chapter.title,
          progress: progress,
          onCancel: () {
            cancel.cancel();
            Navigator.of(sheetCtx).maybePop();
          },
        );
      },
    );

    String? translatedText;
    Object? error;
    try {
      translatedText = await service.translateText(
        chapter.originalText,
        from: meta.sourceLanguage,
        to: meta.targetLanguage,
        cancel: cancel,
        onProgress: (p) => progress.value = p,
      );
    } catch (e) {
      error = e;
    }

    if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
    await sheetFuture;

    if (!mounted) return;
    if (error is TranslateCancelled) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Translation cancelled.')),
      );
      return;
    }
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Translation failed: $error')),
      );
      return;
    }

    final updated = Chapter(
      id: chapter.id,
      title: chapter.title,
      originalText: chapter.originalText,
      translatedText: translatedText,
      translationStatus: TranslationStatus.translated,
      sourceUrl: chapter.sourceUrl,
      publishedAt: chapter.publishedAt,
    );
    await ref
        .read(novelsProvider.notifier)
        .saveChapter(widget.novelId, updated);
    final body = _body;
    if (body != null) {
      setState(() {
        _body = NovelBody(
          id: body.id,
          chapters: [
            for (final c in body.chapters)
              if (c.id == updated.id) updated else c,
          ],
        );
      });
    }
    await ref
        .read(readerPrefsProvider.notifier)
        .setViewMode(ReaderViewMode.parallel);
    messenger.showSnackBar(
      const SnackBar(content: Text('Chapter translated.')),
    );
  }

  /// Where the back arrow goes. News articles came from a paper's front
  /// page, so that's where "back" belongs — not the library.
  String _backRoute(NovelMeta meta) {
    if (meta.sourceType == SourceType.feed) {
      final paper =
          meta.sourceId ??
          (meta.id.startsWith('feed:') ? meta.id.substring(5) : meta.id);
      return '/news?paper=$paper';
    }
    return '/';
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(readerPrefsProvider);
    final body = _body;
    if (body == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (body.chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Empty')),
        body: const Center(child: Text('No chapters in this novel.')),
      );
    }
    final chapter = body.chapters[_chapterIdx];
    final meta = _meta();

    final isPaged = prefs.layout == ReaderLayout.paged;

    // The reader is entered with `go`, which replaces the stack, so the system
    // back gesture would otherwise land on the library. Send it where the top
    // bar's arrow goes — back to the paper the story came from.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !context.mounted) return;
        context.go(_backRoute(meta));
      },
      child: Scaffold(
        // Keyboard shortcuts on desktop.
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _gotoChapter(_chapterIdx + 1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _gotoChapter(_chapterIdx - 1),
            const SingleActivator(LogicalKeyboardKey.keyH): _toggleChrome,
          },
          child: Focus(
            autofocus: true,
            child: SafeArea(
              child: Column(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _chromeVisible
                        ? _TopBar(
                            title: chapter.title,
                            onBack: () => context.go(_backRoute(meta)),
                            onSettings: () => context.go(
                              '/reader/${widget.novelId}/settings',
                            ),
                            onChapters: () => _showChapterPicker(body.chapters),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: SelectionArea(
                      focusNode: _selectionFocus,
                      onSelectionChanged: (selected) =>
                          _onSelectionChanged(selected?.plainText ?? ''),
                      child: isPaged
                          ? _PagedChapterView(
                              key: ValueKey('paged-${chapter.id}'),
                              chapter: chapter,
                              chapterIndex: _chapterIdx,
                              chapterCount: body.chapters.length,
                              initialPage: _position,
                              prefs: prefs,
                              novelId: widget.novelId,
                              novelTitle: meta.title,
                              onPageChanged: _onPositionChanged,
                              onAdvanceChapter: () =>
                                  _gotoChapter(_chapterIdx + 1),
                              onRetreatChapter: () => _gotoChapter(
                                _chapterIdx - 1,
                                positionWithin: -1,
                              ),
                              onCenterTap: _onBackgroundTap,
                              onDoubleTap: _toggleChrome,
                            )
                          : _ScrollChapterView(
                              key: ValueKey('scroll-${chapter.id}'),
                              chapter: chapter,
                              prefs: prefs,
                              initialOffset: _position.toDouble(),
                              novelId: widget.novelId,
                              novelTitle: meta.title,
                              chapterIndex: _chapterIdx,
                              nextTitle: _chapterIdx < body.chapters.length - 1
                                  ? body.chapters[_chapterIdx + 1].title
                                  : null,
                              nextLabel: meta.sourceType == SourceType.feed
                                  ? 'Next story'
                                  : 'Next chapter',
                              onNext: _chapterIdx < body.chapters.length - 1
                                  ? () => _gotoChapter(_chapterIdx + 1)
                                  : null,
                              onOffsetChanged: (px) =>
                                  _onPositionChanged(px.round()),
                              onTap: _onBackgroundTap,
                              onDoubleTap: _toggleChrome,
                            ),
                    ),
                  ),
                  if (_selectionText.isNotEmpty)
                    _SelectionTranslationBanner(
                      source: _selectionText,
                      translation: _selectionTranslation,
                      loading: _selectionTranslating,
                      onSaveToVocab: () => _saveSelectionToVocab(meta, chapter),
                      onDismiss: () {
                        // Hide banner; the user can clear the actual selection
                        // handles by tapping outside the text.
                        setState(() {
                          _selectionText = '';
                          _selectionTranslation = null;
                          _selectionTranslating = false;
                        });
                      },
                    ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _chromeVisible
                        ? _BottomBar(
                            chapterIdx: _chapterIdx,
                            chapterCount: body.chapters.length,
                            viewMode: prefs.viewMode,
                            onPrev: _chapterIdx > 0
                                ? () => _gotoChapter(_chapterIdx - 1)
                                : null,
                            onNext: _chapterIdx < body.chapters.length - 1
                                ? () => _gotoChapter(_chapterIdx + 1)
                                : null,
                            onViewMode: (v) async {
                              await ref
                                  .read(readerPrefsProvider.notifier)
                                  .setViewMode(v);
                            },
                            onTranslate:
                                chapter.translationStatus ==
                                    TranslationStatus.translated
                                ? null
                                : () => _translateChapter(chapter, meta),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showChapterPicker(List<Chapter> chapters) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (ctx, ctrl) => ListView.builder(
            controller: ctrl,
            itemCount: chapters.length,
            itemBuilder: (ctx, i) {
              final c = chapters[i];
              return ListTile(
                leading: SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                title: Text(
                  c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: i == _chapterIdx,
                onTap: () => Navigator.pop(ctx, i),
              );
            },
          ),
        );
      },
    );
    if (picked != null) _gotoChapter(picked);
  }
}

// ─────────── Scroll layout ───────────

class _ScrollChapterView extends StatefulWidget {
  final Chapter chapter;
  final ReaderPrefs prefs;
  final double initialOffset;
  final String novelId;
  final String novelTitle;
  final int chapterIndex;
  final ValueChanged<double> onOffsetChanged;

  /// Single-tap on the chapter background. Used to clear active selection.
  final VoidCallback onTap;

  /// Double-tap on the chapter background. Used to toggle the reader chrome.
  final VoidCallback onDoubleTap;

  /// Headline of what comes next, shown as a tappable card at the end of the
  /// article so reading a feed is a continuous scroll rather than a trip back
  /// to the bottom-bar arrows.
  final String? nextTitle;
  final String nextLabel;
  final VoidCallback? onNext;

  const _ScrollChapterView({
    super.key,
    required this.chapter,
    required this.prefs,
    required this.initialOffset,
    required this.novelId,
    required this.novelTitle,
    required this.chapterIndex,
    required this.onOffsetChanged,
    required this.onTap,
    required this.onDoubleTap,
    this.nextTitle,
    this.nextLabel = 'Next chapter',
    this.onNext,
  });

  @override
  State<_ScrollChapterView> createState() => _ScrollChapterViewState();
}

class _ScrollChapterViewState extends State<_ScrollChapterView> {
  late final ScrollController _ctrl;
  late final List<_Block> _blocks;

  @override
  void initState() {
    super.initState();
    _ctrl = ScrollController();
    _blocks = _buildBlocks(widget.chapter, widget.prefs.viewMode);
    _ctrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_ctrl.hasClients) return;
      _ctrl.jumpTo(
        widget.initialOffset.clamp(0, _ctrl.position.maxScrollExtent),
      );
    });
  }

  @override
  void didUpdateWidget(covariant _ScrollChapterView old) {
    super.didUpdateWidget(old);
    if (old.prefs.viewMode != widget.prefs.viewMode ||
        old.chapter.translatedText != widget.chapter.translatedText) {
      setState(() {
        _blocks = _buildBlocks(widget.chapter, widget.prefs.viewMode);
      });
    }
  }

  void _onScroll() {
    if (_ctrl.hasClients) widget.onOffsetChanged(_ctrl.position.pixels);
  }

  @override
  void dispose() {
    _ctrl
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = _baseTextStyle(context, widget.prefs);
    final paragraphGap = widget.prefs.fontSize * widget.prefs.paragraphSpacing;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.prefs.maxWidth),
          child: ListView.builder(
            controller: _ctrl,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            // 1 title + N blocks; "+ 1" for trailing spacer so the last
            // paragraph isn't glued to the bottom edge.
            itemCount: _blocks.length + 2,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                // The headline is prose too — colour-code and tap it like the
                // body, since it's where a news article's hardest vocabulary
                // usually is.
                return Padding(
                  padding: EdgeInsets.only(bottom: paragraphGap * 1.5),
                  child: JapaneseText(
                    text: widget.chapter.title,
                    prefs: widget.prefs,
                    baseStyle: baseStyle.copyWith(
                      fontSize: widget.prefs.fontSize + 6,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                    onTapToken: (tk) => showWordPopover(
                      context,
                      token: tk,
                      exampleSentence: widget.chapter.title,
                      sourceNovelId: widget.novelId,
                      sourceNovelTitle: widget.novelTitle,
                      sourceChapterId: widget.chapter.id,
                      sourceChapterIndex: widget.chapterIndex,
                    ),
                  ),
                );
              }
              if (i == _blocks.length + 1) {
                final next = widget.nextTitle;
                if (next == null || widget.onNext == null) {
                  return SizedBox(height: paragraphGap * 4);
                }
                return Padding(
                  padding: EdgeInsets.only(
                    top: paragraphGap,
                    bottom: paragraphGap * 3,
                  ),
                  child: _NextStoryCard(
                    label: widget.nextLabel,
                    title: next,
                    onTap: widget.onNext!,
                  ),
                );
              }
              return Padding(
                padding: EdgeInsets.only(bottom: paragraphGap),
                child: _ParagraphBlock(
                  block: _blocks[i - 1],
                  baseStyle: baseStyle,
                  prefs: widget.prefs,
                  onTapToken: (tk) => showWordPopover(
                    context,
                    token: tk,
                    exampleSentence: _blocks[i - 1].original,
                    sourceNovelId: widget.novelId,
                    sourceNovelTitle: widget.novelTitle,
                    sourceChapterId: widget.chapter.id,
                    sourceChapterIndex: widget.chapterIndex,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// End-of-article hand-off: "Next story ›" plus the headline, so a reader
/// finishing one piece can keep going with a single tap.
class _NextStoryCard extends StatelessWidget {
  final String label;
  final String title;
  final VoidCallback onTap;
  const _NextStoryCard({
    required this.label,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          border: Border.all(color: cs.onSurface.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 16,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────── Paged layout ───────────

class _PagedChapterView extends StatefulWidget {
  final Chapter chapter;
  final int chapterIndex;
  final int chapterCount;

  /// Last-saved page index. -1 means "last page" (used when arriving from a
  /// "swipe back into previous chapter" event).
  final int initialPage;
  final ReaderPrefs prefs;
  final String novelId;
  final String novelTitle;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onAdvanceChapter;
  final VoidCallback onRetreatChapter;

  /// Single-tap on the center zone (when tap-zones are on) or anywhere
  /// (when tap-zones are off). Used to clear active selection.
  final VoidCallback onCenterTap;

  /// Double-tap anywhere. Used to toggle the reader chrome.
  final VoidCallback onDoubleTap;

  const _PagedChapterView({
    super.key,
    required this.chapter,
    required this.chapterIndex,
    required this.chapterCount,
    required this.initialPage,
    required this.prefs,
    required this.novelId,
    required this.novelTitle,
    required this.onPageChanged,
    required this.onAdvanceChapter,
    required this.onRetreatChapter,
    required this.onCenterTap,
    required this.onDoubleTap,
  });

  @override
  State<_PagedChapterView> createState() => _PagedChapterViewState();
}

class _PagedChapterViewState extends State<_PagedChapterView> {
  late PageController _ctrl;
  late List<ChapterPage> _pages;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pages = _paginate();
    _currentPage = widget.initialPage < 0
        ? (_pages.length - 1).clamp(0, _pages.length)
        : widget.initialPage.clamp(0, _pages.isEmpty ? 0 : _pages.length - 1);
    _ctrl = PageController(initialPage: _currentPage);
  }

  @override
  void didUpdateWidget(covariant _PagedChapterView old) {
    super.didUpdateWidget(old);
    final pageLimitChanged =
        old.prefs.pageCharLimit != widget.prefs.pageCharLimit;
    final viewModeChanged = old.prefs.viewMode != widget.prefs.viewMode;
    final translationChanged =
        old.chapter.translatedText != widget.chapter.translatedText;
    if (pageLimitChanged || viewModeChanged || translationChanged) {
      setState(() {
        _pages = _paginate();
        _currentPage = _currentPage.clamp(0, _pages.length - 1);
        _ctrl.dispose();
        _ctrl = PageController(initialPage: _currentPage);
      });
    }
  }

  List<ChapterPage> _paginate() {
    final origs = splitParagraphs(widget.chapter.originalText);
    final trans = splitParagraphs(widget.chapter.translatedText ?? '');
    final viewMode = widget.prefs.viewMode;
    // Choose which streams contribute to char count.
    final origInput = viewMode == ReaderViewMode.translated && trans.isNotEmpty
        ? const <String>[]
        : origs;
    final transInput = viewMode == ReaderViewMode.original
        ? const <String>[]
        : trans;
    return paginateChapter(
      original: origInput.isEmpty ? origs : origInput,
      translated: transInput,
      pageCharLimit: widget.prefs.pageCharLimit,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    widget.onPageChanged(page);
  }

  void _animateToPage(int page) {
    if (page < 0) {
      widget.onRetreatChapter();
      return;
    }
    if (page >= _pages.length) {
      widget.onAdvanceChapter();
      return;
    }
    _ctrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    if (!widget.prefs.tapZonesEnabled) {
      widget.onCenterTap();
      return;
    }
    final w = constraints.maxWidth;
    final x = details.localPosition.dx;
    if (x < w / 3) {
      _animateToPage(_currentPage - 1);
    } else if (x > w * 2 / 3) {
      _animateToPage(_currentPage + 1);
    } else {
      widget.onCenterTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return const Center(child: Text('Empty chapter.'));
    }
    final baseStyle = _baseTextStyle(context, widget.prefs);
    final paragraphGap = widget.prefs.fontSize * widget.prefs.paragraphSpacing;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Column(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onTapUp: (d) => _handleTap(d, constraints),
                onDoubleTap: widget.onDoubleTap,
                child: NotificationListener<OverscrollNotification>(
                  onNotification: (n) {
                    // Boundary swipe: PageView clamps within the chapter's
                    // pages, but an overscroll at either end means the user
                    // is trying to leave the chapter. Hop to the adjacent one.
                    if (n.overscroll > 0 && _currentPage == _pages.length - 1) {
                      widget.onAdvanceChapter();
                    } else if (n.overscroll < 0 && _currentPage == 0) {
                      widget.onRetreatChapter();
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _ctrl,
                    onPageChanged: _onPageChanged,
                    itemCount: _pages.length,
                    physics: widget.prefs.swipeToTurnPage
                        ? const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          )
                        : const NeverScrollableScrollPhysics(),
                    itemBuilder: (ctx, i) {
                      final page = _pages[i];
                      return _PageBody(
                        page: page,
                        chapter: widget.chapter,
                        showTitle: i == 0,
                        baseStyle: baseStyle,
                        paragraphGap: paragraphGap,
                        prefs: widget.prefs,
                        novelId: widget.novelId,
                        novelTitle: widget.novelTitle,
                        chapterIndex: widget.chapterIndex,
                      );
                    },
                  ),
                ),
              ),
            ),
            _PageProgressBar(
              page: _currentPage,
              total: _pages.length,
              chapterIndex: widget.chapterIndex,
              chapterCount: widget.chapterCount,
            ),
          ],
        );
      },
    );
  }
}

class _PageBody extends StatelessWidget {
  final ChapterPage page;
  final Chapter chapter;
  final bool showTitle;
  final TextStyle baseStyle;
  final double paragraphGap;
  final ReaderPrefs prefs;
  final String novelId;
  final String novelTitle;
  final int chapterIndex;

  const _PageBody({
    required this.page,
    required this.chapter,
    required this.showTitle,
    required this.baseStyle,
    required this.paragraphGap,
    required this.prefs,
    required this.novelId,
    required this.novelTitle,
    required this.chapterIndex,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = <_Block>[
      for (var i = 0; i < page.originalParagraphs.length; i++)
        _composeBlock(
          page.originalParagraphs[i],
          i < page.translatedParagraphs.length
              ? page.translatedParagraphs[i]
              : null,
          prefs.viewMode,
        ),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: prefs.maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          // Inside-page scroll is a safety net: if a page happens to overflow
          // the viewport (large font + dense paragraph), the user can still
          // see the bottom. Swiping outside the scrollable still triggers the
          // PageView, which lives outside this widget.
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showTitle)
                Padding(
                  padding: EdgeInsets.only(bottom: paragraphGap * 1.5),
                  child: JapaneseText(
                    text: chapter.title,
                    prefs: prefs,
                    baseStyle: baseStyle.copyWith(
                      fontSize: prefs.fontSize + 6,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                    onTapToken: (tk) => showWordPopover(
                      context,
                      token: tk,
                      exampleSentence: chapter.title,
                      sourceNovelId: novelId,
                      sourceNovelTitle: novelTitle,
                      sourceChapterId: chapter.id,
                      sourceChapterIndex: chapterIndex,
                    ),
                  ),
                ),
              for (var i = 0; i < blocks.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: paragraphGap),
                  child: _ParagraphBlock(
                    block: blocks[i],
                    baseStyle: baseStyle,
                    prefs: prefs,
                    onTapToken: (tk) => showWordPopover(
                      context,
                      token: tk,
                      exampleSentence: blocks[i].original,
                      sourceNovelId: novelId,
                      sourceNovelTitle: novelTitle,
                      sourceChapterId: chapter.id,
                      sourceChapterIndex: chapterIndex,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageProgressBar extends StatelessWidget {
  final int page;
  final int total;
  final int chapterIndex;
  final int chapterCount;
  const _PageProgressBar({
    required this.page,
    required this.total,
    required this.chapterIndex,
    required this.chapterCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Row(
        children: [
          Text(
            '${page + 1} / $total',
            style: TextStyle(
              fontSize: 10.5,
              color: cs.onSurface.withValues(alpha: 0.55),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : (page + 1) / total,
                minHeight: 2,
                backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Ch ${chapterIndex + 1} / $chapterCount',
            style: TextStyle(
              fontSize: 10.5,
              color: cs.onSurface.withValues(alpha: 0.55),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────── Block construction + paragraph widget ───────────

class _Block {
  final String? original;
  final String? translated;
  const _Block({this.original, this.translated});
}

List<_Block> _buildBlocks(Chapter c, ReaderViewMode mode) {
  final origs = splitParagraphs(c.originalText);
  final trans = splitParagraphs(c.translatedText ?? '');
  switch (mode) {
    case ReaderViewMode.original:
      return [for (final o in origs) _Block(original: o)];
    case ReaderViewMode.translated:
      final src = trans.isEmpty ? origs : trans;
      return [for (final t in src) _Block(translated: t)];
    case ReaderViewMode.parallel:
      final n = origs.length > trans.length ? origs.length : trans.length;
      return [
        for (var i = 0; i < n; i++)
          _Block(
            original: i < origs.length ? origs[i] : null,
            translated: i < trans.length ? trans[i] : null,
          ),
      ];
  }
}

_Block _composeBlock(String original, String? translated, ReaderViewMode mode) {
  switch (mode) {
    case ReaderViewMode.original:
      return _Block(original: original);
    case ReaderViewMode.translated:
      return _Block(translated: translated ?? original);
    case ReaderViewMode.parallel:
      return _Block(original: original, translated: translated);
  }
}

TextStyle _baseTextStyle(BuildContext context, ReaderPrefs prefs) {
  return TextStyle(
    fontSize: prefs.fontSize,
    height: prefs.lineHeight,
    letterSpacing: prefs.letterSpacing,
    fontFamily: _fontFamilyName(prefs.fontFamily),
    color: Theme.of(context).colorScheme.onSurface,
  );
}

String? _fontFamilyName(ReaderFontFamily f) {
  switch (f) {
    case ReaderFontFamily.serif:
      return null;
    case ReaderFontFamily.sans:
      return null;
    case ReaderFontFamily.mono:
      return 'monospace';
    case ReaderFontFamily.dyslexic:
      return null;
  }
}

class _ParagraphBlock extends StatelessWidget {
  final _Block block;
  final TextStyle baseStyle;
  final ReaderPrefs prefs;
  final void Function(JpToken)? onTapToken;
  const _ParagraphBlock({
    required this.block,
    required this.baseStyle,
    required this.prefs,
    this.onTapToken,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.75);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.original != null)
          JapaneseText(
            text: block.original!,
            prefs: prefs,
            baseStyle: baseStyle,
            onTapToken: onTapToken,
          ),
        if (block.original != null && block.translated != null)
          const SizedBox(height: 6),
        if (block.translated != null)
          Text(
            block.translated!,
            style: baseStyle.copyWith(
              color: muted,
              fontStyle: prefs.viewMode == ReaderViewMode.parallel
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
      ],
    );
  }
}

// ─────────── Top / bottom bars + translation sheet ───────────

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onChapters;
  const _TopBar({
    required this.title,
    required this.onBack,
    required this.onSettings,
    required this.onChapters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: onChapters,
            icon: const Icon(Icons.format_list_numbered),
          ),
          IconButton(onPressed: onSettings, icon: const Icon(Icons.tune)),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int chapterIdx;
  final int chapterCount;
  final ReaderViewMode viewMode;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<ReaderViewMode> onViewMode;
  final VoidCallback? onTranslate;
  const _BottomBar({
    required this.chapterIdx,
    required this.chapterCount,
    required this.viewMode,
    required this.onPrev,
    required this.onNext,
    required this.onViewMode,
    required this.onTranslate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: SegmentedButton<ReaderViewMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: ReaderViewMode.original, label: Text('原')),
                ButtonSegment(
                  value: ReaderViewMode.translated,
                  label: Text('EN'),
                ),
                ButtonSegment(
                  value: ReaderViewMode.parallel,
                  label: Text('Both'),
                ),
              ],
              selected: {viewMode},
              onSelectionChanged: (s) => onViewMode(s.first),
            ),
          ),
          IconButton(
            tooltip: 'Translate chapter',
            onPressed: onTranslate,
            icon: const Icon(Icons.translate),
          ),
          IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class _TranslateProgressSheet extends StatelessWidget {
  final String title;
  final ValueNotifier<double> progress;
  final VoidCallback onCancel;
  const _TranslateProgressSheet({
    required this.title,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Translating chapter',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (ctx, p, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: p == 0 ? null : p),
                  const SizedBox(height: 6),
                  Text(
                    p == 0 ? 'Sending…' : '${(p * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

String _truncate(String s, [int max = 24]) =>
    s.length <= max ? s : '${s.substring(0, max - 1)}…';

class _SelectionTranslationBanner extends StatelessWidget {
  final String source;
  final String? translation;
  final bool loading;
  final VoidCallback onDismiss;
  final VoidCallback onSaveToVocab;

  const _SelectionTranslationBanner({
    required this.source,
    required this.translation,
    required this.loading,
    required this.onDismiss,
    required this.onSaveToVocab,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isError = translation != null && translation!.startsWith('⚠');
    return Material(
      color: cs.surface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: cs.onSurface.withValues(alpha: 0.10)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    source,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (loading)
                    Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Translating…',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    )
                  else if (translation != null)
                    Text(
                      translation!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: isError
                            ? cs.error
                            : cs.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Save phrase to vocab',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  onPressed: loading || isError ? null : onSaveToVocab,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
