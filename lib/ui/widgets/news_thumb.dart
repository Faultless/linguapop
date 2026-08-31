import 'package:flutter/material.dart';

import '../../services/sources/news_image_store.dart';

/// Lazily-loaded, memory-bounded news lead image.
///
/// Three cases:
///   * `local:…` — bytes captured at import time through the feed's
///     authenticated client (NHK serves its images behind a session cookie).
///   * a remote URL — streamed and cached by Flutter's own ImageCache.
///   * neither, or a load failure — [onUnavailable] fires so the caller can
///     drop the picture box entirely rather than leave a grey rectangle on the
///     page.
///
/// The decode is capped with `cacheWidth` so a page of thumbnails stays cheap.
class NewsThumb extends StatefulWidget {
  final String? url;
  final double width;
  final double height;
  final double radius;

  /// Called once when there's nothing to show — no URL, evicted bytes, or a
  /// failed fetch. Fires after the frame, so it's safe to `setState` from.
  final VoidCallback? onUnavailable;

  const NewsThumb({
    super.key,
    required this.url,
    this.width = 64,
    this.height = 64,
    this.radius = 8,
    this.onUnavailable,
  });

  @override
  State<NewsThumb> createState() => _NewsThumbState();
}

class _NewsThumbState extends State<NewsThumb> {
  bool _reported = false;

  void _reportUnavailable() {
    if (_reported || widget.onUnavailable == null) return;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onUnavailable!();
    });
  }

  @override
  void didUpdateWidget(covariant NewsThumb old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _reported = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconSize = (widget.width.isFinite ? widget.width : 64.0) * 0.34;
    final placeholder = Container(
      color: cs.onSurface.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined,
          size: iconSize, color: cs.onSurface.withValues(alpha: 0.25)),
    );

    final url = widget.url;
    // Decode at roughly the displayed pixel size to keep memory low. When the
    // box is unbounded (grid tiles use width: infinity), fall back to a
    // sensible cap instead of computing an infinite cacheWidth.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = widget.width.isFinite
        ? (widget.width * dpr).round()
        : (400 * dpr).round();

    Widget child;
    if (url == null || url.isEmpty) {
      _reportUnavailable();
      child = placeholder;
    } else if (NewsImageStore.isLocal(url)) {
      final bytes = NewsImageStore.read(url);
      if (bytes == null) {
        _reportUnavailable();
        child = placeholder;
      } else {
        child = Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          cacheWidth: cacheW,
          gaplessPlayback: true,
          errorBuilder: (_, e, s) {
            _reportUnavailable();
            return placeholder;
          },
        );
      }
    } else {
      child = Image.network(
        url,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        cacheWidth: cacheW,
        gaplessPlayback: true,
        frameBuilder: (ctx, child, frame, wasSync) {
          if (wasSync || frame != null) {
            return AnimatedOpacity(
              opacity: 1,
              duration: const Duration(milliseconds: 220),
              child: child,
            );
          }
          return placeholder;
        },
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : placeholder,
        errorBuilder: (_, e, s) {
          _reportUnavailable();
          return placeholder;
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
          width: widget.width, height: widget.height, child: child),
    );
  }
}
