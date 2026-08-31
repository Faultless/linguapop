import 'dart:typed_data';

import '../../data/storage/storage.dart';
import 'session_client.dart';

/// Downloads and keeps article lead images on the device.
///
/// This exists because NHK serves its article images from `news.web.nhk`,
/// which answers 401 to anyone without the session cookie the feed adapters
/// negotiate. `Image.network` has no cookie jar, so every NHK picture rendered
/// as a broken-image box. Fetching through the same [SessionClient] that read
/// the article is the only way those images load at all.
///
/// Doing it at import time rather than at paint time also means the front page
/// draws instantly and works offline, which suits a paper you fetch in the
/// morning and read later.
///
/// Stored images are addressed as `local:<key>` in `Chapter.imageUrl`;
/// [NewsThumb] resolves that against this store.
class NewsImageStore {
  final SessionClient _client;
  NewsImageStore(this._client);

  /// Prefix marking an image that lives in the local box rather than on the
  /// network.
  static const scheme = 'local:';

  /// How many article images to keep. At roughly 60–150 KB each this is a few
  /// tens of megabytes at worst; older entries are dropped first.
  static const maxImages = 240;

  /// Bytes larger than this are almost certainly not a lead image (or aren't
  /// worth the space).
  static const maxBytes = 3 * 1024 * 1024;

  static bool isLocal(String? url) =>
      url != null && url.startsWith(scheme);

  static String keyOf(String localUrl) => localUrl.substring(scheme.length);

  /// The bytes behind a `local:` URL, or null if they've been evicted.
  static Uint8List? read(String localUrl) {
    final raw = Storage.newsImages().get(keyOf(localUrl));
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return null;
  }

  /// Fetch [url] through the session client and store it under [key].
  ///
  /// Returns the `local:` URL to put on the chapter, or null when the image
  /// can't be had — in which case the caller should drop the image entirely
  /// rather than store a URL that will render as a broken box.
  Future<String?> capture(String url, String key) async {
    try {
      final res = await _client.get(Uri.parse(url));
      if (!res.ok) return null;
      if (!res.contentType.startsWith('image/')) return null;
      if (res.bytes.isEmpty || res.bytes.length > maxBytes) return null;
      final box = Storage.newsImages();
      await box.put(key, Uint8List.fromList(res.bytes));
      await _prune();
      return '$scheme$key';
    } catch (_) {
      return null;
    }
  }

  /// Drop the oldest entries once the box outgrows [maxImages]. Hive preserves
  /// insertion order for its keys, so the front of the list is the oldest.
  Future<void> _prune() async {
    final box = Storage.newsImages();
    if (box.length <= maxImages) return;
    final excess = box.length - maxImages;
    final doomed = box.keys.take(excess).toList();
    await box.deleteAll(doomed);
  }

  /// Remove the image belonging to a deleted article.
  static Future<void> forget(String? localUrl) async {
    if (!isLocal(localUrl)) return;
    await Storage.newsImages().delete(keyOf(localUrl!));
  }
}
