import 'dart:convert';

import '../../data/storage/storage.dart';

const _key = 'news_synced_at';

/// When a feed was last synced, and how wide a window that sync covered.
class SyncStamp {
  final int at;
  final int days;

  /// Bumped when the sync logic changes enough that earlier stamps can't be
  /// trusted (v2: NHK moved off its frozen RSS).
  final int version;
  static const current = 2;

  const SyncStamp(this.at, this.days, [this.version = current]);

  Map<String, dynamic> toJson() => {'at': at, 'days': days, 'v': version};
  factory SyncStamp.fromJson(Map<String, dynamic> j) => SyncStamp(
      (j['at'] as num).toInt(),
      (j['days'] as num).toInt(),
      (j['v'] as num?)?.toInt() ?? 1);
}

/// Per-source sync stamps, so a refresh only touches papers that need it.
///
/// The articles themselves are the cache: a sync skips every `sourceUrl`
/// already imported, so a day-later refresh only fetches the new day.
class NewsFreshness {
  /// A same-day stamp older than this still refreshes — wires file all day.
  static const maxAge = Duration(hours: 2);

  /// Whether [stamp] needs a refresh for a window of [days] at [now]: never
  /// synced, synced on an earlier calendar day, synced with a narrower window
  /// than is now asked for, or simply older than [maxAge].
  static bool isStale(SyncStamp? stamp, int days, DateTime now) {
    if (stamp == null || stamp.days < days) return true;
    if (stamp.version != SyncStamp.current) return true;
    final at = DateTime.fromMillisecondsSinceEpoch(stamp.at);
    if (at.year != now.year || at.month != now.month || at.day != now.day) {
      return true;
    }
    return now.difference(at) > maxAge;
  }

  static Map<String, SyncStamp> load() {
    try {
      final raw = Storage.prefs().get(_key);
      if (raw is String && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        return {
          for (final e in m.entries)
            e.key: SyncStamp.fromJson(Map<String, dynamic>.from(e.value as Map)),
        };
      }
    } catch (_) {}
    return {};
  }

  static Future<void> stamp(String sourceId, SyncStamp s) async {
    final all = load()..[sourceId] = s;
    await Storage.prefs().put(
        _key, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
  }
}
