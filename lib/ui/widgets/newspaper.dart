import 'package:flutter/material.dart';

/// Shared visual vocabulary for the front-page view: mastheads, rules, and
/// the small-caps meta lines that make a list of imported articles read like
/// a broadsheet instead of a feed.
///
/// Everything here draws from the active [ColorScheme], so the user's reader
/// theme (paper / sepia / night / e-ink …) still governs the palette — only
/// the *shapes* are fixed.
class NewsprintStyle {
  static const serif = 'serif';

  /// Small-caps-ish meta line: "07:32 · NHK EASY".
  static TextStyle meta(ColorScheme cs, {double size = 10.5}) => TextStyle(
        fontFamily: serif,
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        height: 1.2,
        color: cs.primary,
      );

  static TextStyle headline(ColorScheme cs,
          {double size = 16, bool read = false}) =>
      TextStyle(
        fontFamily: serif,
        fontSize: size,
        height: 1.18,
        fontWeight: read ? FontWeight.w600 : FontWeight.w800,
        letterSpacing: -0.1,
        color: read ? cs.onSurface.withValues(alpha: 0.6) : cs.onSurface,
      );

  static TextStyle body(ColorScheme cs, {double size = 12}) => TextStyle(
        fontFamily: serif,
        fontSize: size,
        height: 1.34,
        color: cs.onSurface.withValues(alpha: 0.78),
      );
}

/// Horizontal hairline. [weight] 2 draws the heavy rule newspapers use under
/// a masthead; [gap] > 0 draws the classic thin/thick pair.
class NewsRule extends StatelessWidget {
  final double weight;
  final double alpha;
  const NewsRule({super.key, this.weight = 1, this.alpha = 0.55});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: weight,
      color: cs.onSurface.withValues(alpha: alpha),
    );
  }
}

/// The thin-over-thick rule pair that sits under a masthead.
class NewsDoubleRule extends StatelessWidget {
  const NewsDoubleRule({super.key});
  @override
  Widget build(BuildContext context) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NewsRule(weight: 2.5, alpha: 0.75),
          SizedBox(height: 2),
          NewsRule(alpha: 0.5),
        ],
      );
}

/// Full-width paper masthead, set the way a Japanese daily sets one: the
/// outlet's name in heavy kanji between rules, a romaji overline, and a
/// dateline row carrying the edition seal (朝刊 / 夕刊) and the story count.
class NewspaperMasthead extends StatelessWidget {
  /// Masthead name, normally in Japanese.
  final String title;

  /// Romaji / Latin line above it.
  final String overline;
  final String leftMeta;
  final String rightMeta;

  /// Boxed seal at the right of the title row (edition, 号外, …).
  final String? seal;

  const NewspaperMasthead({
    super.key,
    required this.title,
    required this.overline,
    required this.leftMeta,
    required this.rightMeta,
    this.seal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.sizeOf(context).width;
    // Kanji are square, so a Japanese masthead fills its line far faster than
    // a Latin one; size off the actual character count either way.
    final titleSize =
        (w / (title.runes.length.clamp(4, 18)) * 1.55).clamp(24.0, 46.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NewsRule(alpha: 0.5),
        const SizedBox(height: 8),
        Text(
          overline.toUpperCase(),
          textAlign: TextAlign.center,
          style: NewsprintStyle.meta(cs, size: 9.5).copyWith(letterSpacing: 3.4),
        ),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NewsprintStyle.serif,
                  fontSize: titleSize,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (seal != null) SealBox(text: seal!),
          ],
        ),
        const SizedBox(height: 8),
        const NewsRule(alpha: 0.5),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(leftMeta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NewsprintStyle.meta(cs, size: 10).copyWith(
                        letterSpacing: 0.6,
                        color: cs.onSurface.withValues(alpha: 0.65))),
              ),
              Text(rightMeta,
                  maxLines: 1,
                  style: NewsprintStyle.meta(cs, size: 10).copyWith(
                      letterSpacing: 0.6,
                      color: cs.onSurface.withValues(alpha: 0.65))),
            ],
          ),
        ),
        const NewsDoubleRule(),
      ],
    );
  }
}

/// A boxed label in the accent colour — the 号外 / 朝刊 seal a Japanese paper
/// stamps beside its masthead.
class SealBox extends StatelessWidget {
  final String text;
  const SealBox({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: cs.primary, width: 1.4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: NewsprintStyle.serif,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: cs.primary,
        ),
      ),
    );
  }
}

/// Reverse-type outlet label — white-on-ink, the way a Japanese paper marks
/// which desk or wire a story came off.
class KickerBox extends StatelessWidget {
  final String text;
  final bool muted;
  const KickerBox({super.key, required this.text, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = muted ? cs.onSurface.withValues(alpha: 0.35) : cs.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      color: bg,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: NewsprintStyle.serif,
          fontSize: 9,
          height: 1.25,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: cs.surface,
        ),
      ),
    );
  }
}

/// Section divider between masonry bands — a rule with an optional centred
/// label ("TODAY", "YESTERDAY", a date).
class NewsSectionRule extends StatelessWidget {
  final String? label;
  const NewsSectionRule({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (label == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: NewsRule(alpha: 0.28),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: NewsRule(alpha: 0.45, weight: 1.6)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '【${label!}】',
              style: NewsprintStyle.meta(cs, size: 11.5)
                  .copyWith(letterSpacing: 1.2),
            ),
          ),
          Expanded(child: NewsRule(alpha: 0.45, weight: 1.6)),
        ],
      ),
    );
  }
}

/// A paper on the rack: the source's name set as a miniature masthead, with
/// an unread count. Selected state inverts to ink-on-paper.
class PaperTab extends StatelessWidget {
  final String name;
  final int unread;
  final bool selected;
  final VoidCallback onTap;
  const PaperTab({
    super.key,
    required this.name,
    required this.unread,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.surface : cs.onSurface;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.onSurface : Colors.transparent,
          border: Border.all(
              color: cs.onSurface.withValues(alpha: selected ? 0.9 : 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontFamily: NewsprintStyle.serif,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: fg,
              ),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$unread',
                style: TextStyle(
                  fontFamily: NewsprintStyle.serif,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? cs.surface.withValues(alpha: 0.75)
                      : cs.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// Deterministic small integer from a string, so a story's placeholder art and
/// a paper's fake column widths stay the same across rebuilds and restarts.
int stableSeed(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = (h ^ c) * 0x01000193;
    h &= 0xFFFFFFFF;
  }
  return h;
}

/// Body copy seen from across the room: rows of thin rules at pseudo-random
/// lengths, optionally broken by a solid block standing in for a photo.
///
/// Cheap enough to sit inside a scrolling shelf — one `drawRect` per line, no
/// text layout at all.
class NewsprintPainter extends CustomPainter {
  final Color color;
  final int seed;
  final int columns;
  final double lineHeight;
  final double thickness;

  /// Rows at the top of the first column drawn heavier, as a headline.
  final int headlineRows;

  /// Fraction of the column height taken by a photo block, 0 for none.
  final double photoFraction;

  const NewsprintPainter({
    required this.color,
    required this.seed,
    this.columns = 2,
    this.lineHeight = 4,
    this.thickness = 1.4,
    this.headlineRows = 2,
    this.photoFraction = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const gutter = 4.0;
    final colWidth = (size.width - gutter * (columns - 1)) / columns;
    if (colWidth <= 1) return;
    final paint = Paint()..color = color;
    var rng = seed | 1;
    double next() {
      // Cheap xorshift — deterministic, no dart:math import needed.
      rng ^= (rng << 13) & 0xFFFFFFFF;
      rng ^= rng >> 17;
      rng ^= (rng << 5) & 0xFFFFFFFF;
      return (rng & 0xFFFF) / 0xFFFF;
    }

    for (var c = 0; c < columns; c++) {
      final x = c * (colWidth + gutter);
      var y = 0.0;
      // A photo block heads the last column when asked for.
      if (photoFraction > 0 && c == columns - 1) {
        final h = size.height * photoFraction;
        canvas.drawRect(
            Rect.fromLTWH(x, y, colWidth, h), paint..color = color);
        y += h + lineHeight;
      }
      var row = 0;
      while (y + thickness <= size.height) {
        final isHeadline = c == 0 && row < headlineRows;
        final h = isHeadline ? thickness * 2.2 : thickness;
        if (y + h > size.height) break;
        final w = isHeadline
            ? colWidth * (0.72 + next() * 0.28)
            : colWidth * (0.55 + next() * 0.45);
        canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
        y += h + lineHeight;
        row++;
      }
    }
  }

  @override
  bool shouldRepaint(NewsprintPainter old) =>
      old.color != color ||
      old.seed != seed ||
      old.columns != columns ||
      old.lineHeight != lineHeight ||
      old.thickness != thickness ||
      old.photoFraction != photoFraction;
}

/// A paper as it looks on the shelf: the outlet's name set as a masthead over
/// a page of unreadable column copy. Scales off its own width so it reads at
/// both a 60 px thumbnail and a 160 px shelf card.
class NewspaperFront extends StatelessWidget {
  final String outlet;

  /// Small line under the masthead — usually the edition or story count.
  final String? kicker;

  const NewspaperFront({super.key, required this.outlet, this.kicker});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = cs.onSurface;
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 110.0;
      final pad = (w * 0.07).clamp(4.0, 12.0);
      final mastheadSize = (w * 0.15).clamp(7.0, 20.0);
      return Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: ink.withValues(alpha: 0.35)),
        ),
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              outlet,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: NewsprintStyle.serif,
                fontSize: mastheadSize,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                color: ink,
              ),
            ),
            SizedBox(height: pad * 0.5),
            Container(height: 1.6, color: ink.withValues(alpha: 0.7)),
            if (kicker != null) ...[
              SizedBox(height: pad * 0.3),
              Text(
                kicker!,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NewsprintStyle.serif,
                  fontSize: (w * 0.075).clamp(5.5, 10.0),
                  letterSpacing: 0.5,
                  color: cs.primary,
                ),
              ),
            ],
            SizedBox(height: pad * 0.4),
            Container(height: 0.8, color: ink.withValues(alpha: 0.4)),
            SizedBox(height: pad * 0.5),
            Expanded(
              child: CustomPaint(
                painter: NewsprintPainter(
                  color: ink.withValues(alpha: 0.30),
                  seed: stableSeed(outlet),
                  columns: 2,
                  lineHeight: (w * 0.035).clamp(2.0, 5.0),
                  thickness: (w * 0.012).clamp(1.0, 2.0),
                  photoFraction: 0.28,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Stand-in for a story whose source had no image to scrape: a faint field of
/// column copy with the headline's own first kanji set large behind it, so a
/// picture-less story still has a shape on the page instead of a grey box.
class NewsprintPlaceholder extends StatelessWidget {
  final String seedText;
  final double height;
  const NewsprintPlaceholder({
    super.key,
    required this.seedText,
    required this.height,
  });

  /// The first CJK character of [text], or 「新」 when there isn't one.
  static String glyphFor(String text) {
    for (final r in text.runes) {
      final kanji = (r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF);
      if (kanji) return String.fromCharCode(r);
    }
    return '新';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = cs.onSurface;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ColoredBox(
        color: ink.withValues(alpha: 0.045),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    glyphFor(seedText),
                    style: TextStyle(
                      fontFamily: NewsprintStyle.serif,
                      fontWeight: FontWeight.w900,
                      color: ink.withValues(alpha: 0.14),
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(7),
              child: CustomPaint(
                painter: NewsprintPainter(
                  color: ink.withValues(alpha: 0.16),
                  seed: stableSeed(seedText),
                  columns: 3,
                  lineHeight: 4,
                  thickness: 1.2,
                  headlineRows: 0,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
