import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/novel.dart';
import '../../providers/covers_provider.dart';
import 'newspaper.dart';

/// A book-shaped cover image. If [coverUrl] is set we load it (data: URIs,
/// remote URLs, and the `local:` scheme for device-picked images all work).
/// Otherwise we render a procedural cover whose gradient palette is
/// deterministically derived from the title — same title always gets the same
/// colors, so the library looks coherent across sessions.
class BookCover extends ConsumerWidget {
  final NovelMeta meta;
  /// Width in logical pixels. Height follows the 2:3 aspect ratio.
  final double width;
  /// Optional override for the cover URL (used when we want to preview a
  /// not-yet-imported novel, e.g. in search results).
  final String? coverUrlOverride;
  /// Show small overlay badges (content type, source language). Set to false
  /// when the surrounding card already shows that info.
  final bool overlayBadges;

  const BookCover({
    super.key,
    required this.meta,
    this.width = 110,
    this.coverUrlOverride,
    this.overlayBadges = true,
  });

  String? get _coverUrl => coverUrlOverride ?? meta.coverUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = _coverUrl;
    final hasUrl = url != null && url.isNotEmpty;
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasUrl)
                _coverImage(ref, url)
              else if (meta.sourceType == SourceType.feed)
                // A news feed isn't a book — it sits on the shelf as a folded
                // paper with the outlet's name on the masthead.
                NewspaperFront(
                  outlet: meta.title,
                  kicker: meta.chapterCount > 0 ? '${meta.chapterCount}件' : null,
                )
              else
                _ProceduralCover(meta: meta),
              if (overlayBadges) _CoverOverlay(meta: meta),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverImage(WidgetRef ref, String url) {
    final fallback = _ProceduralCover(meta: meta);
    if (isLocalCover(url)) {
      // Watch the revision so a freshly-picked cover repaints immediately.
      ref.watch(coverRevisionProvider);
      final bytes = LocalCoverStore.get(meta.id);
      if (bytes == null) return fallback;
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _ProceduralCover extends StatelessWidget {
  final NovelMeta meta;
  const _ProceduralCover({required this.meta});

  static const _palettes = <List<Color>>[
    [Color(0xFF8E2DE2), Color(0xFF4A00E0)], // purple
    [Color(0xFFFC466B), Color(0xFF3F5EFB)], // pink → blue
    [Color(0xFFFF512F), Color(0xFFF09819)], // orange
    [Color(0xFF11998E), Color(0xFF38EF7D)], // teal → green
    [Color(0xFF614385), Color(0xFF516395)], // indigo
    [Color(0xFFEB3349), Color(0xFFF45C43)], // red
    [Color(0xFF00B4DB), Color(0xFF0083B0)], // cyan
    [Color(0xFFAA076B), Color(0xFF61045F)], // magenta
    [Color(0xFFDA22FF), Color(0xFF9733EE)], // violet
    [Color(0xFF1F4037), Color(0xFF99F2C8)], // forest
    [Color(0xFF373B44), Color(0xFF4286F4)], // slate
    [Color(0xFFB24592), Color(0xFFF15F79)], // rose
  ];

  List<Color> get _palette {
    final idx = meta.title.hashCode.abs() % _palettes.length;
    return _palettes[idx];
  }

  String get _displayTitle {
    final t = meta.title.trim();
    if (t.isEmpty) return '?';
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _palette;
    return CustomPaint(
      painter: _CoverPainter(
        colors: colors,
        seed: meta.title.hashCode,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _displayTitle,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _fontSizeForTitle(_displayTitle),
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.3,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (meta.author != null && meta.author!.isNotEmpty)
              Text(
                meta.author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Generative type-scale — shorter titles get to breathe, longer titles
  /// shrink so they fit in the same ~5 lines we cap with `maxLines`.
  double _fontSizeForTitle(String title) {
    final len = title.length;
    if (len <= 8) return 22;
    if (len <= 16) return 18;
    if (len <= 28) return 14.5;
    if (len <= 50) return 12;
    return 10;
  }
}

class _CoverPainter extends CustomPainter {
  final List<Color> colors;
  final int seed;
  _CoverPainter({required this.colors, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // Subtle dot lattice so the cover looks intentional, not flat. Density
    // and offset are derived from the title hash so each cover gets a
    // unique fingerprint.
    final rng = Random(seed);
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07);
    const spacing = 14.0;
    final phaseX = (rng.nextDouble() * spacing);
    final phaseY = (rng.nextDouble() * spacing);
    for (double y = phaseY; y < size.height; y += spacing) {
      for (double x = phaseX; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    // Diagonal accent stroke — a soft "spine highlight" near the left edge.
    final accent = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, 4, size.height), accent);
  }

  @override
  bool shouldRepaint(covariant _CoverPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.colors != colors;
}

class _CoverOverlay extends StatelessWidget {
  final NovelMeta meta;
  const _CoverOverlay({required this.meta});

  @override
  Widget build(BuildContext context) {
    final lang = meta.sourceLanguage.toUpperCase();
    final ctype = meta.contentType;
    // Along the bottom edge, not the top: a cover's title lives at the top,
    // and on a newspaper front the masthead is the whole point of the tile.
    return Stack(
      children: [
        if (ctype != null)
          Positioned(
            bottom: 6,
            left: 6,
            child: _miniBadge(
              context,
              label: _contentTypeLabel(ctype),
            ),
          ),
        Positioned(
          bottom: 6,
          right: 6,
          child: _miniBadge(context, label: lang),
        ),
      ],
    );
  }

  static String _contentTypeLabel(ContentType c) {
    switch (c) {
      case ContentType.news:
        return 'NEWS';
      case ContentType.lightNovel:
        return 'LN';
      case ContentType.webNovel:
        return 'WEB';
      case ContentType.shortStory:
        return 'SHORT';
      case ContentType.novel:
        return 'NOVEL';
    }
  }

  Widget _miniBadge(BuildContext context, {required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.6,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Render a tag as a colored chip whose hue is derived from the tag string so
/// the same tag always looks the same. Lightweight, no allocations per build.
class TagChip extends StatelessWidget {
  final String label;
  final bool dense;
  const TagChip({super.key, required this.label, this.dense = true});

  @override
  Widget build(BuildContext context) {
    final hue = (label.hashCode.abs() % 360).toDouble();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = HSLColor.fromAHSL(
            dark ? 0.30 : 0.18, hue, 0.65, dark ? 0.55 : 0.55)
        .toColor();
    final fg = HSLColor.fromAHSL(1, hue, 0.65, dark ? 0.85 : 0.30).toColor();
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(dense ? 6 : 999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: dense ? 10 : 12,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
