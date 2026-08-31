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

/// Full-width paper masthead: overline, title, and the dateline row.
class NewspaperMasthead extends StatelessWidget {
  final String title;
  final String overline;
  final String leftMeta;
  final String rightMeta;
  const NewspaperMasthead({
    super.key,
    required this.title,
    required this.overline,
    required this.leftMeta,
    required this.rightMeta,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.sizeOf(context).width;
    // Shrink the masthead on narrow phones so a long paper name stays on one
    // line instead of wrapping into a wall of display type.
    final titleSize = (w / (title.length.clamp(6, 24)) * 1.9).clamp(26.0, 44.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NewsRule(alpha: 0.5),
        const SizedBox(height: 8),
        Text(
          overline.toUpperCase(),
          textAlign: TextAlign.center,
          style: NewsprintStyle.meta(cs, size: 10).copyWith(letterSpacing: 3),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: NewsprintStyle.serif,
            fontSize: titleSize,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        const NewsRule(alpha: 0.5),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(leftMeta.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NewsprintStyle.meta(cs, size: 9.5).copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6))),
              ),
              Text(rightMeta.toUpperCase(),
                  maxLines: 1,
                  style: NewsprintStyle.meta(cs, size: 9.5).copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6))),
            ],
          ),
        ),
        const NewsDoubleRule(),
      ],
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label!.toUpperCase(),
              style: NewsprintStyle.meta(cs, size: 11)
                  .copyWith(letterSpacing: 2.2),
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
              name.toUpperCase(),
              style: TextStyle(
                fontFamily: NewsprintStyle.serif,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
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
