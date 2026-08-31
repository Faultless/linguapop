import 'package:flutter/material.dart';

import '../../data/models/novel.dart';
import 'book_cover.dart';
import 'jlpt_badge.dart';

/// Shelf-style book tile used in the library grid (Media view): book-shaped
/// cover with overlays, then a clamped title and author underneath. Tags are
/// intentionally omitted here — the grid is cover-forward; tags show in the
/// List and Card views where there's horizontal room for them.
class NovelCard extends StatelessWidget {
  final NovelMeta meta;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Slot width handed down by [BookShelf]. When set the card fills its slot
  /// exactly — cover at 2:3, caption in whatever height is left — so a row of
  /// covers lines up on the shelf board. Null keeps the old free-height form.
  final double? width;

  const NovelCard({
    super.key,
    required this.meta,
    required this.onTap,
    this.onLongPress,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = meta.chapterCount == 0
        ? 0.0
        : (meta.lastReadChapter / meta.chapterCount).clamp(0.0, 1.0);
    final jlptBucket = meta.jlptStats?.difficultyBucket;
    final w = width;

    if (w != null) {
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _CoverWithShadow(meta: meta, width: w),
                if (jlptBucket != null)
                  Positioned(
                    bottom: 5,
                    right: 5,
                    child: JlptBadge(level: jlptBucket, size: 8.5),
                  ),
                if (meta.favorite)
                  const Positioned(bottom: 5, left: 5, child: _FavoriteHeart()),
                if (progress > 0 && progress < 1)
                  Positioned(
                    left: 5,
                    right: 5,
                    bottom: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2.5,
                        backgroundColor: Colors.black.withValues(alpha: 0.35),
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Expanded(
              child: Text(
                meta.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.18,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                _CoverWithShadow(meta: meta),
                if (jlptBucket != null)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: JlptBadge(level: jlptBucket, size: 9.5),
                  ),
                if (meta.favorite)
                  const Positioned(
                    bottom: 6,
                    left: 6,
                    child: _FavoriteHeart(),
                  ),
                if (progress > 0 && progress < 1)
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.black.withValues(alpha: 0.35),
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                meta.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
            if (meta.author != null && meta.author!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                child: Text(
                  meta.author!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact horizontal row (List view): small cover thumbnail on the left,
/// title / author / tags clamped on the right. Everything is single- or
/// two-line capped so a long title or tag list can never overflow.
class NovelListRow extends StatelessWidget {
  final NovelMeta meta;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const NovelListRow({
    super.key,
    required this.meta,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = meta.chapterCount == 0
        ? 0.0
        : (meta.lastReadChapter / meta.chapterCount).clamp(0.0, 1.0);
    final jlptBucket = meta.jlptStats?.difficultyBucket;
    final tags = meta.tags ?? const <String>[];

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46,
              height: 69,
              child: BookCover(meta: meta, width: 46, overlayBadges: false),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (jlptBucket != null) ...[
                        const SizedBox(width: 8),
                        JlptBadge(level: jlptBucket, size: 9.5),
                      ],
                    ],
                  ),
                  if (meta.author != null && meta.author!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        meta.author!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  if (tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _ClampedTagRow(tags: tags, max: 3),
                    ),
                  if (progress > 0 && progress < 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor:
                              cs.onSurface.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rich full-width card (Card view): larger cover, title, author, a longer
/// tag wrap, and reading progress. Tags wrap to at most two lines via the
/// take()-and-count clamp.
class NovelWideCard extends StatelessWidget {
  final NovelMeta meta;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const NovelWideCard({
    super.key,
    required this.meta,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = meta.chapterCount == 0
        ? 0.0
        : (meta.lastReadChapter / meta.chapterCount).clamp(0.0, 1.0);
    final jlptBucket = meta.jlptStats?.difficultyBucket;
    final tags = meta.tags ?? const <String>[];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: cs.onSurface.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverWithShadow(meta: meta, width: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            meta.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (meta.favorite)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.favorite,
                                size: 15, color: cs.primary),
                          ),
                        if (jlptBucket != null) ...[
                          const SizedBox(width: 6),
                          JlptBadge(level: jlptBucket, size: 10),
                        ],
                      ],
                    ),
                    if (meta.author != null && meta.author!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          meta.author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    if (tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            for (final t in tags.take(5)) TagChip(label: t),
                            if (tags.length > 5)
                              _MoreCount(n: tags.length - 5),
                          ],
                        ),
                      ),
                    if (progress > 0 && progress < 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor:
                                cs.onSurface.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single non-wrapping row of tag chips, clamped to [max] with a "+N"
/// overflow indicator. Each chip is allowed to shrink so the row never
/// overflows its width.
class _ClampedTagRow extends StatelessWidget {
  final List<String> tags;
  final int max;
  const _ClampedTagRow({required this.tags, required this.max});

  @override
  Widget build(BuildContext context) {
    final shown = tags.take(max).toList();
    final extra = tags.length - shown.length;
    return Row(
      children: [
        for (final t in shown)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: TagChip(label: t),
            ),
          ),
        if (extra > 0) _MoreCount(n: extra),
      ],
    );
  }
}

class _MoreCount extends StatelessWidget {
  final int n;
  const _MoreCount({required this.n});
  @override
  Widget build(BuildContext context) {
    return Text(
      '+$n',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}

class _FavoriteHeart extends StatelessWidget {
  const _FavoriteHeart();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.favorite, size: 11, color: Colors.white),
    );
  }
}

class _CoverWithShadow extends StatelessWidget {
  final NovelMeta meta;
  final double? width;
  const _CoverWithShadow({required this.meta, this.width});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: width == null
          ? BookCover(meta: meta)
          // In a Row the AspectRatio has no bounded height, so pin the box.
          : SizedBox(
              width: width,
              height: width! * 3 / 2,
              child: BookCover(meta: meta, width: width!),
            ),
    );
  }
}
