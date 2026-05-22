import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks where a user paused inside each video so the next view picks
/// up where they left off (YouTube / Netflix behavior).
///
/// Storage shape (one row per video, keyed by URL hash for opacity):
///
/// ```
///   unmu.video.resume.v1 = { "<urlHash>": { "p": 423000, "t": 17323... }, ... }
/// ```
///
/// `p` = position in milliseconds, `t` = last-touched timestamp in
/// epoch-ms. Rows older than [_kResumeTTL] are auto-pruned on read so
/// the blob doesn't grow forever — at 50 chars × 1000 entries we stay
/// well under SharedPreferences' practical size budget.
class VideoResumeService {
  static const String _kKey = 'unmu.video.resume.v1';
  static const Duration _kResumeTTL = Duration(days: 30);
  static const int _kMaxEntries = 1000;

  /// Tiny non-crypto hash of [url] for use as the storage key. We don't
  /// store the raw URL because it contains pre-signed query strings
  /// that rotate every fetch — same video, different URL each time.
  /// Hashing just the path portion keeps the key stable across
  /// re-signings.
  static String _hash(String url) {
    final pathOnly =
        Uri.tryParse(url)?.path ?? url.split('?').first;
    // Fowler-Noll-Vo 32-bit — fast, well-distributed, deterministic.
    var h = 0x811c9dc5;
    for (var i = 0; i < pathOnly.length; i++) {
      h = (h ^ pathOnly.codeUnitAt(i)) & 0xffffffff;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Read everything (already-pruned). Cheap — SharedPreferences keeps
  /// the whole map in memory once the singleton is initialized.
  static Future<Map<String, dynamic>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final v = json.decode(raw);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return {};
  }

  static Future<void> _write(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, json.encode(data));
  }

  /// Save [position] for [url]. Skipped when the position is near the
  /// very start (< 10 s — pre-buffer noise) or very end (in the last
  /// 10 s — let it auto-restart instead of resuming at "the end").
  static Future<void> savePosition({
    required String url,
    required Duration position,
    required Duration total,
  }) async {
    final p = position.inMilliseconds;
    final t = total.inMilliseconds;
    if (p < 10000 || (t > 0 && p > t - 10000)) {
      return;
    }
    final data = await _read();
    data[_hash(url)] = {
      'p': p,
      't': DateTime.now().millisecondsSinceEpoch,
    };
    await _prune(data);
    await _write(data);
  }

  /// Get the saved position for [url], or null if none / expired.
  static Future<Duration?> loadPosition(String url) async {
    final data = await _read();
    final raw = data[_hash(url)];
    if (raw is! Map) return null;
    final p = raw['p'];
    final t = raw['t'];
    if (p is! int || t is! int) return null;
    final age = DateTime.now().millisecondsSinceEpoch - t;
    if (age > _kResumeTTL.inMilliseconds) return null;
    return Duration(milliseconds: p);
  }

  /// Drop the saved position for [url] — called when the video plays
  /// all the way to its end, since "resume at the end" is useless.
  static Future<void> clearPosition(String url) async {
    final data = await _read();
    data.remove(_hash(url));
    await _write(data);
  }

  /// Best-effort cleanup. Mutates [data] in place.
  ///   1. Drop entries older than [_kResumeTTL].
  ///   2. If still > [_kMaxEntries], drop the oldest until we're under.
  static Future<void> _prune(Map<String, dynamic> data) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = <String>[];
    for (final entry in data.entries) {
      final t = (entry.value is Map) ? entry.value['t'] : null;
      if (t is! int || (now - t) > _kResumeTTL.inMilliseconds) {
        stale.add(entry.key);
      }
    }
    for (final k in stale) {
      data.remove(k);
    }
    if (data.length <= _kMaxEntries) return;
    final entries = data.entries.toList()
      ..sort((a, b) {
        final ta = (a.value is Map ? a.value['t'] : 0) as int? ?? 0;
        final tb = (b.value is Map ? b.value['t'] : 0) as int? ?? 0;
        return ta.compareTo(tb);
      });
    final dropCount = data.length - _kMaxEntries;
    for (var i = 0; i < dropCount; i++) {
      data.remove(entries[i].key);
    }
  }
}
