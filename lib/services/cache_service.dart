import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Clears the on-disk junk that bloats iOS "Documents & Data": picked-video
/// temp copies (file_picker), generated cover thumbnails (video_thumbnail),
/// video-player cache, and any other temp/cache files.
///
/// It only touches the OS **temporary** + **application-cache** directories
/// and Flutter's in-memory image cache — NOT the Documents dir or
/// SharedPreferences — so the user's session (auth token) and any persistent
/// data are never lost.
class CacheService {
  /// The directories we're allowed to wipe. Both are reproducible caches.
  static Future<List<Directory>> _cacheDirs() async {
    final dirs = <Directory>[];
    try {
      dirs.add(await getTemporaryDirectory());
    } catch (_) {}
    try {
      dirs.add(await getApplicationCacheDirectory());
    } catch (_) {}
    return dirs;
  }

  /// Total bytes currently sitting in the cache directories.
  static Future<int> sizeBytes() async {
    var total = 0;
    for (final dir in await _cacheDirs()) {
      if (!await dir.exists()) continue;
      try {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return total;
  }

  /// Delete everything in the cache directories + drop Flutter's image
  /// cache. Returns the number of bytes that were present before clearing
  /// (i.e. roughly what got freed) so the UI can report it.
  static Future<int> clear() async {
    final before = await sizeBytes();
    for (final dir in await _cacheDirs()) {
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {
            // A file currently open (e.g. a video mid-playback) can't be
            // deleted — skip it; the next clear will catch it.
          }
        }
      } catch (_) {}
    }
    // In-memory + live image caches.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    return before;
  }

  /// Human-readable size, e.g. "1.54 GB", "212 MB", "48 KB".
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}
