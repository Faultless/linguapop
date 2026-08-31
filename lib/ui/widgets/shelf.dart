import 'package:flutter/material.dart';

/// One shelf of the library: a fixed number of evenly-spaced slots with a
/// board drawn underneath, so the grid reads as furniture rather than as a
/// list of tiles.
///
/// The board is three thin layers — a contact shadow that the covers appear to
/// sit in, the board face, and its front edge — rather than a wood texture.
/// It reads as a shelf at a glance without the skeuomorphism.
///
/// Items are sized by the shelf, not by themselves: [itemBuilder] receives the
/// slot width so covers, mastheads and type can all scale off one number.
class BookShelf extends StatelessWidget {
  /// Slots across. The last shelf of a library is usually part-full; empty
  /// slots keep their space so the covers stay on a common grid.
  final int columns;

  /// Items actually present on this shelf (`<= columns`).
  final int count;

  final double spacing;

  /// Slot height as a multiple of slot width. The default fits a 2:3 cover
  /// plus a two-line caption.
  final double heightRatio;

  /// Draw the board under this shelf. The final shelf in a scroll view often
  /// looks better without one.
  final bool board;

  final Widget Function(BuildContext context, int index, double width)
      itemBuilder;

  const BookShelf({
    super.key,
    required this.columns,
    required this.count,
    required this.itemBuilder,
    this.spacing = 12,
    this.heightRatio = 1.84,
    this.board = true,
  });

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return LayoutBuilder(builder: (ctx, c) {
      final width = (c.maxWidth - spacing * (columns - 1)) / columns;
      if (width <= 0) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: width * heightRatio,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < columns; i++) ...[
                  if (i > 0) SizedBox(width: spacing),
                  SizedBox(
                    width: width,
                    height: width * heightRatio,
                    child: i < count
                        ? itemBuilder(ctx, i, width)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
          if (board) ShelfBoard(ink: ink),
        ],
      );
    });
  }
}

/// The board itself: contact shadow, face, front edge.
class ShelfBoard extends StatelessWidget {
  final Color ink;
  const ShelfBoard({super.key, required this.ink});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                ink.withValues(alpha: 0.10),
              ],
            ),
          ),
        ),
        Container(height: 2.5, color: ink.withValues(alpha: 0.30)),
        Container(height: 1.5, color: ink.withValues(alpha: 0.12)),
        const SizedBox(height: 18),
      ],
    );
  }
}
