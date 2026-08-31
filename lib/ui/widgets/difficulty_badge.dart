import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/jlpt_stats.dart';
import '../../data/themes/builtin_themes.dart';
import '../../providers/jlpt_provider.dart';

/// Estimates the JLPT difficulty of [text] and renders a compact level badge
/// (e.g. "~N3") colored like the JLPT palette. Renders nothing while the
/// pipeline warms up or when no estimate is possible (web stub tokenizer,
/// no Japanese content words).
///
/// Set [approx] when the input is only a teaser (title + summary) rather than
/// the full text — the label gets a "~" prefix.
/// Set [showBar] to also render a tiny distribution bar of N5…N1 word shares.
class DifficultyBadge extends ConsumerStatefulWidget {
  final String text;
  final bool approx;
  final bool showBar;
  final double fontSize;

  /// Already-computed breakdown. When set the badge does no work at all —
  /// this is the path the front page uses, because tokenizing each article as
  /// it scrolled into view was the most expensive thing on that screen.
  final JlptStats? stats;

  const DifficultyBadge({
    super.key,
    required this.text,
    this.approx = false,
    this.showBar = false,
    this.fontSize = 10.5,
    this.stats,
  });

  @override
  ConsumerState<DifficultyBadge> createState() => _DifficultyBadgeState();
}

class _DifficultyBadgeState extends ConsumerState<DifficultyBadge> {
  JlptStats? _stats;

  @override
  void initState() {
    super.initState();
    if (widget.stats == null) _estimate();
  }

  @override
  void didUpdateWidget(covariant DifficultyBadge old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.stats != widget.stats) {
      _stats = null;
      if (widget.stats == null) _estimate();
    }
  }

  Future<void> _estimate() async {
    final estimator = ref.read(jlptEstimatorProvider);
    final text = widget.text;
    final stats = await estimator.estimate(text);
    if (!mounted || widget.text != text) return;
    setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats ?? _stats;
    final bucket = stats?.difficultyBucket;
    if (stats == null || bucket == null) return const SizedBox.shrink();
    final c = kJlptColors[bucket] ?? Colors.grey;
    final label = '${widget.approx ? "~" : ""}N$bucket';

    final badge = Container(
      padding: EdgeInsets.symmetric(
          horizontal: widget.fontSize * 0.55, vertical: widget.fontSize * 0.16),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        border: Border.all(color: c.withValues(alpha: 0.65), width: 1),
        borderRadius: BorderRadius.circular(widget.fontSize * 0.6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w700,
          color: c,
          letterSpacing: 0.3,
        ),
      ),
    );

    if (!widget.showBar) return badge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(width: 6),
        JlptDistributionBar(stats: stats, width: 54),
      ],
    );
  }
}

/// Thin stacked bar showing the share of N5…N1 (+ unknown) content words.
class JlptDistributionBar extends StatelessWidget {
  final JlptStats stats;
  final double width;
  final double height;
  const JlptDistributionBar({
    super.key,
    required this.stats,
    this.width = 60,
    this.height = 5,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final segments = <(int count, Color color)>[
      (stats.n5, kJlptColors[5]!),
      (stats.n4, kJlptColors[4]!),
      (stats.n3, kJlptColors[3]!),
      (stats.n2, kJlptColors[2]!),
      (stats.n1, kJlptColors[1]!),
      (stats.unknown, cs.onSurface.withValues(alpha: 0.18)),
    ];
    final total = stats.total;
    if (total == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        width: width,
        height: height,
        child: Row(
          children: [
            for (final (count, color) in segments)
              if (count > 0)
                Expanded(
                  flex: count,
                  child: ColoredBox(color: color),
                ),
          ],
        ),
      ),
    );
  }
}
