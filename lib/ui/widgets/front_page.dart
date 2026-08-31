import 'package:flutter/material.dart';

import 'difficulty_badge.dart';
import 'news_thumb.dart';
import 'newspaper.dart';

/// One story as the front page needs it — deliberately not tied to
/// [NewsArticle] so the layout can be laid out and tested on its own.
class FrontPageItem {
  final String id;
  final String title;
  final String snippet;
  final String sourceName;
  final String? imageUrl;
  final int? publishedAt;
  final bool read;

  /// Text the difficulty badge scores. Usually the full article body.
  final String difficultyText;

  const FrontPageItem({
    required this.id,
    required this.title,
    required this.snippet,
    required this.sourceName,
    this.imageUrl,
    this.publishedAt,
    this.read = false,
    this.difficultyText = '',
  });
}

/// One balanced slice of the front page.
///
/// Stories are dealt into whichever column is currently shortest, using a
/// cheap height estimate — the same trick a paste-up editor uses, and it
/// keeps columns from drifting apart without a second layout pass.
///
/// Bands rather than one continuous masonry: a band is a fixed slice of the
/// list, which keeps the whole page inside a `ListView.builder`. Building
/// every story eagerly would mean tokenizing every article for its difficulty
/// badge on first paint.
class FrontPageBand extends StatelessWidget {
  final List<FrontPageItem> items;
  final int columns;
  final bool showSource;
  final bool showDifficulty;
  final void Function(FrontPageItem) onOpen;
  final void Function(FrontPageItem)? onLongPress;

  static const gutter = 12.0;

  const FrontPageBand({
    super.key,
    required this.items,
    required this.columns,
    required this.onOpen,
    this.showSource = true,
    this.showDifficulty = true,
    this.onLongPress,
  });

  /// Two columns on a phone — the point of the layout is to read like a
  /// broadsheet, not a feed — widening to more only on tablets and desktop.
  static int columnsFor(double width) {
    if (width < 640) return 2;
    return (width / 300).floor().clamp(3, 5);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (ctx, c) {
      final colWidth = (c.maxWidth - gutter * (columns - 1)) / columns;
      final buckets = deal(items, columns, colWidth);

      final children = <Widget>[];
      for (var k = 0; k < columns; k++) {
        if (k > 0) children.add(const SizedBox(width: gutter));
        children.add(Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in buckets[k])
                FrontPageStory(
                  key: ValueKey(item.id),
                  item: item,
                  showSource: showSource,
                  showDifficulty: showDifficulty,
                  columnWidth: colWidth,
                  onTap: () => onOpen(item),
                  onLongPress:
                      onLongPress == null ? null : () => onLongPress!(item),
                ),
            ],
          ),
        ));
      }

      // The vertical rules between columns are painted behind the row rather
      // than laid out as stretched children: a Row inside a ListView has an
      // unbounded height, so a full-height divider can't be a flex child
      // without an expensive IntrinsicHeight pass.
      return CustomPaint(
        painter: _ColumnRulesPainter(
          columns: columns,
          colWidth: colWidth,
          gutter: gutter,
          color: cs.onSurface.withValues(alpha: 0.16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    });
  }

  /// Assign each item to the shortest column so far. Exposed for tests.
  static List<List<FrontPageItem>> deal(
      List<FrontPageItem> items, int columns, double colWidth) {
    final buckets = List.generate(columns, (_) => <FrontPageItem>[]);
    final heights = List<double>.filled(columns, 0);
    for (final item in items) {
      var shortest = 0;
      for (var k = 1; k < columns; k++) {
        if (heights[k] < heights[shortest]) shortest = k;
      }
      buckets[shortest].add(item);
      heights[shortest] += estimateHeight(item, colWidth);
    }
    return buckets;
  }

  /// Rough rendered height of a story block, in logical pixels. Only the
  /// *relative* values matter — it decides which column a story lands in.
  static double estimateHeight(FrontPageItem item, double colWidth) {
    const headlineSize = 15.0;
    final perLine = (colWidth / (headlineSize * 0.96)).floor().clamp(4, 40);
    final titleLines = (item.title.runes.length / perLine).ceil().clamp(1, 6);
    var h = 18.0; // meta line
    h += titleLines * headlineSize * 1.18 + 6;
    if ((item.imageUrl ?? '').isNotEmpty ||
        (item.imageUrl == null && FrontPageStory.wantsPlaceholder(item.id))) {
      h += colWidth * 0.58 + 8;
    }
    h += 3 * 12 * 1.34; // snippet
    h += 26; // padding + rule
    return h;
  }
}

class _ColumnRulesPainter extends CustomPainter {
  final int columns;
  final double colWidth;
  final double gutter;
  final Color color;
  const _ColumnRulesPainter({
    required this.columns,
    required this.colWidth,
    required this.gutter,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var k = 1; k < columns; k++) {
      final x = colWidth * k + gutter * (k - 1) + gutter / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_ColumnRulesPainter old) =>
      old.columns != columns ||
      old.colWidth != colWidth ||
      old.gutter != gutter ||
      old.color != color;
}

/// One story on the front page: meta line, serif headline, optional cut, and
/// a short lead paragraph, closed by a hairline rule.
class FrontPageStory extends StatefulWidget {
  final FrontPageItem item;
  final bool showSource;
  final bool showDifficulty;
  final double columnWidth;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const FrontPageStory({
    super.key,
    required this.item,
    required this.columnWidth,
    required this.onTap,
    this.showSource = true,
    this.showDifficulty = true,
    this.onLongPress,
  });

  @override
  State<FrontPageStory> createState() => _FrontPageStoryState();

  /// Whether a story with no scrapeable image still gets a drawn stand-in.
  ///
  /// Not every one: a page where every single story carries a picture box
  /// looks like a template, and a page with none looks broken. Two in three,
  /// picked deterministically from the story id so a given story always looks
  /// the same.
  static bool wantsPlaceholder(String id) => stableSeed(id) % 3 != 0;
}

class _FrontPageStoryState extends State<FrontPageStory> {
  /// Set once the image turns out not to exist — an evicted local capture, or
  /// a host that won't serve it. The story then runs text-only rather than
  /// holding a grey rectangle on the page.
  bool _noImage = false;

  @override
  void didUpdateWidget(covariant FrontPageStory old) {
    super.didUpdateWidget(old);
    if (old.item.imageUrl != widget.item.imageUrl) _noImage = false;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final showSource = widget.showSource;
    final columnWidth = widget.columnWidth;
    final cs = Theme.of(context).colorScheme;
    final read = item.read;
    final time = frontPageTimeLabel(item.publishedAt);
    final image = _noImage ? '' : (item.imageUrl ?? '');
    final cutHeight = columnWidth * 0.56;

    Widget? cut;
    if (image.isNotEmpty) {
      cut = NewsThumb(
        url: image,
        width: double.infinity,
        height: cutHeight,
        radius: 0,
        onUnavailable: () {
          if (mounted) setState(() => _noImage = true);
        },
      );
    } else if (item.imageUrl == null &&
        FrontPageStory.wantsPlaceholder(item.id)) {
      // Only for stories the source never offered a picture for. A story whose
      // picture failed to load goes text-only instead — a drawn stand-in there
      // would be pretending we had something.
      cut = NewsprintPlaceholder(seedText: item.title, height: cutHeight);
    }

    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (showSource) ...[
                  Flexible(
                    child: KickerBox(text: item.sourceName, muted: read),
                  ),
                  const SizedBox(width: 5),
                ],
                if (time.isNotEmpty)
                  Text(
                    time,
                    maxLines: 1,
                    style: NewsprintStyle.meta(cs, size: 9.5).copyWith(
                        color: read
                            ? cs.onSurface.withValues(alpha: 0.45)
                            : cs.primary),
                  ),
                const Spacer(),
                if (widget.showDifficulty)
                  DifficultyBadge(text: item.difficultyText, fontSize: 8.5),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unread stories carry the accent rule down the headline.
                Container(
                  width: 2.5,
                  height: 15.0 * 1.18,
                  margin: const EdgeInsets.only(right: 5, top: 1),
                  color: read ? Colors.transparent : cs.primary,
                ),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: NewsprintStyle.headline(cs, read: read),
                  ),
                ),
              ],
            ),
            if (cut != null) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  border:
                      Border.all(color: cs.onSurface.withValues(alpha: 0.35)),
                ),
                padding: const EdgeInsets.all(2),
                child: cut,
              ),
            ],
            if (item.snippet.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.justify,
                style: NewsprintStyle.body(cs),
              ),
            ],
            const SizedBox(height: 10),
            NewsRule(alpha: read ? 0.14 : 0.24),
          ],
        ),
      ),
    );
  }
}

String frontPageTimeLabel(int? publishedAt) {
  if (publishedAt == null) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(publishedAt);
  return '${dt.hour.toString().padLeft(2, "0")}:'
      '${dt.minute.toString().padLeft(2, "0")}';
}
