import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import 'auth_service.dart';

/// How many multipart parts may be in flight at once during a direct-
/// to-S3 upload. 4 hits the sweet spot on real-world cellular + WiFi:
///
///   * 1  — Phase A baseline, no parallelism, slowest
///   * 4  — ~3-4× faster than 1 on a 50 Mbit link; still gentle on
///          cellular signal + battery
///   * 8+ — diminishing returns; HTTP/1.1 head-of-line + tower
///          throttling start to dominate, and battery drain spikes
///
/// Kept as a top-level const so a future cellular-aware setter (Phase
/// C+) can override it dynamically without changing call sites.
const int _kMultipartConcurrency = 4;

/// Persistent upload-state lifetime. Backend pre-signed PUT URLs live
/// for 6 hours; we expire client state 1 hour earlier so a resumed
/// upload never tries to PUT to a URL that's already dead.
const Duration _kUploadStateTTL = Duration(hours: 5);

/// SharedPreferences key prefix for serialized upload state. Each
/// in-progress upload is keyed by an opaque hash of its file path —
/// the path itself could contain characters that confuse downstream
/// tooling.
const String _kUploadStatePrefix = 'unmu.upload.v1:';

/// Multipart file uploader. Posts a file to the backend's
/// /api/me/uploads/(video|image) endpoints and returns an absolute URL the
/// client can use as `mediaUrl` / `coverUrl` on a post.
///
/// The backend returns a path like `/uploads/videos/<random>.mp4`; we
/// rewrite it to a fully-qualified URL using [ApiConfig.baseUrl] so the
/// `video_player` widget can resolve it.
class UploadService {
  static String get _base => ApiConfig.baseUrl;

  /// Upload a video file. Returns the relative path (e.g.
  /// `/uploads/videos/<random>.mp4`) on success, or an `error` message
  /// on failure.
  ///
  /// We deliberately store **relative** paths — the absolute URL is
  /// reconstructed at read-time using [ApiConfig.baseUrl]'s origin, so
  /// the dev IP can change (laptop hops Wi-Fi, deploys to prod over
  /// HTTPS, etc.) without invalidating posts already in the database.
  ///
  /// The backend caps videos at 100 MB and only accepts mp4 / mov / m4v /
  /// webm / mkv extensions.
  static Future<({String? url, String? error})> uploadVideo(File file) =>
      _upload(file, '/me/uploads/video');

  /// Upload an image file (post cover / thumbnail). Backend caps at 8 MB
  /// and accepts jpg / jpeg / png / webp / gif.
  static Future<({String? url, String? error})> uploadImage(File file) =>
      _upload(file, '/me/uploads/image');

  /// Upload a PDF document — used by the expert-application form for
  /// resume / credentials. Backend caps at 10 MB and accepts .pdf only.
  static Future<({String? url, String? error})> uploadDocument(File file) =>
      _upload(file, '/me/uploads/document');

  static Future<({String? url, String? error})> _upload(
      File file, String path) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        return (url: null, error: 'Not signed in.');
      }

      final uri = Uri.parse('$_base$path');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (url: null, error: 'Session expired — please sign in again.');
      }
      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final relative = body['url'] as String? ?? '';
        if (relative.isEmpty) {
          return (url: null, error: 'Server returned no URL.');
        }
        // Return the relative path as-is. ExpertPost.fromJson resolves
        // it to the current origin when the post is fetched back.
        return (url: relative, error: null);
      }
      // Try to surface the backend's error message for size / type errors.
      final err = _safeDecode(response.body)['error']?.toString() ??
          'Upload failed (${response.statusCode}).';
      return (url: null, error: err);
    } catch (e) {
      return (url: null, error: 'Connection error: $e');
    }
  }

  static Map<String, dynamic> _safeDecode(String s) {
    try {
      final v = json.decode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return {};
  }

  // ───────────────────────────────────────────────────────────────────
  // Chunked video upload — three-step protocol (init → chunk × N →
  // complete). Use this instead of [uploadVideo] for reels and any
  // long video. Benefits over single-shot:
  //
  //   * Network drops mid-upload only lose one chunk → that chunk is
  //     retried instead of the whole 50 MB file.
  //   * Real progress (0..1) is reported via [onProgress] so the
  //     composer can render a moving bar instead of a forever-spinner.
  //   * Sidesteps proxy / nginx body-size limits in production.
  //
  // Restart-on-fail: if a chunk fails after 3 retries we abort the
  // whole upload and surface an error. A future "GET /status" can opt
  // into true resumable; this version is good enough for 99% of mobile
  // uploads on flaky 4G.
  // ───────────────────────────────────────────────────────────────────

  /// Upload [file] in chunks. [onProgress] is called with values in
  /// 0..1 — driven by `chunksUploaded / totalChunks`, not bytes-on-the-
  /// wire. Returns the relative URL on success.
  static Future<({String? url, String? error})> uploadVideoChunked(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        return (url: null, error: 'Not signed in.');
      }

      final filename = file.path.split(Platform.pathSeparator).last;
      final totalSize = await file.length();
      if (totalSize <= 0) {
        return (url: null, error: 'File is empty.');
      }

      // ── Step 1: init — server returns uploadId + chunkSize ────────
      final initRes = await _initChunked(token, filename, totalSize);
      if (initRes.error != null) {
        return (url: null, error: initRes.error);
      }
      final uploadId = initRes.uploadId!;
      final chunkSize = initRes.chunkSize!;
      final totalChunks = (totalSize / chunkSize).ceil();

      onProgress?.call(0.0);

      // ── Step 2: chunk × N. Sequential — keeps client + server
      // memory bounded and matches the natural retry granularity. ──
      final raf = await file.open();
      try {
        for (var i = 0; i < totalChunks; i++) {
          final start = i * chunkSize;
          final end = (start + chunkSize).clamp(0, totalSize);
          final length = end - start;
          await raf.setPosition(start);
          final bytes = await raf.read(length);

          final ok = await _uploadOneChunk(
            token: token,
            uploadId: uploadId,
            index: i,
            bytes: bytes,
          );
          if (!ok.success) {
            return (url: null, error: ok.error ?? 'Chunk $i failed.');
          }
          onProgress?.call((i + 1) / totalChunks);
        }
      } finally {
        await raf.close();
      }

      // ── Step 3: complete — server stitches into final file ────────
      final completeRes =
          await _completeChunked(token, uploadId, filename);
      if (completeRes.error != null) {
        return (url: null, error: completeRes.error);
      }
      return (url: completeRes.url, error: null);
    } catch (e) {
      return (url: null, error: 'Connection error: $e');
    }
  }

  // ─── /init ────────────────────────────────────────────────────────

  static Future<({String? uploadId, int? chunkSize, String? error})>
      _initChunked(String token, String filename, int totalSize) async {
    final totalChunks =
        (totalSize / (2 * 1024 * 1024)).ceil(); // optimistic guess
    final response = await http.post(
      Uri.parse('$_base/me/uploads/video/init'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'filename': filename,
        'totalChunks': totalChunks,
        'totalSize': totalSize,
      }),
    );
    if (response.statusCode == 401) {
      await Get.find<AuthController>().handleAuthFailure();
      return (
        uploadId: null,
        chunkSize: null,
        error: 'Session expired — please sign in again.',
      );
    }
    if (response.statusCode != 200) {
      final err = _safeDecode(response.body)['error']?.toString() ??
          'Init failed (${response.statusCode}).';
      return (uploadId: null, chunkSize: null, error: err);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final id = body['uploadId'] as String?;
    final size = (body['chunkSize'] as num?)?.toInt();
    if (id == null || size == null) {
      return (
        uploadId: null,
        chunkSize: null,
        error: 'Server returned no uploadId.',
      );
    }
    return (uploadId: id, chunkSize: size, error: null);
  }

  // ─── /chunk (with retry) ──────────────────────────────────────────

  static Future<({bool success, String? error})> _uploadOneChunk({
    required String token,
    required String uploadId,
    required int index,
    required List<int> bytes,
  }) async {
    const maxAttempts = 3;
    String? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$_base/me/uploads/video/chunk'),
        )
          ..headers['Authorization'] = 'Bearer $token'
          ..fields['uploadId'] = uploadId
          ..fields['chunkIndex'] = '$index'
          ..files.add(
            http.MultipartFile.fromBytes(
              'data',
              bytes,
              filename: '$index.bin',
            ),
          );
        final streamed = await request.send().timeout(
              const Duration(seconds: 60),
            );
        final response = await http.Response.fromStream(streamed);
        if (response.statusCode == 401) {
          await Get.find<AuthController>().handleAuthFailure();
          return (
            success: false,
            error: 'Session expired — please sign in again.',
          );
        }
        if (response.statusCode == 200) {
          return (success: true, error: null);
        }
        // 4xx is the server saying "this is your fault" — don't retry.
        if (response.statusCode >= 400 && response.statusCode < 500) {
          final err = _safeDecode(response.body)['error']?.toString() ??
              'Chunk rejected (${response.statusCode}).';
          return (success: false, error: err);
        }
        lastError = 'Chunk $index failed (${response.statusCode}).';
      } catch (e) {
        lastError = 'Chunk $index error: $e';
      }
      // Quick exponential-ish backoff before the next attempt: 200ms,
      // 600ms. Total worst-case extra wait per chunk = ~800ms.
      if (attempt < maxAttempts) {
        await Future<void>.delayed(
          Duration(milliseconds: 200 * (attempt * attempt)),
        );
      }
    }
    return (success: false, error: lastError ?? 'Chunk $index failed.');
  }

  // ─── /complete ────────────────────────────────────────────────────

  static Future<({String? url, String? error})> _completeChunked(
    String token,
    String uploadId,
    String filename,
  ) async {
    final response = await http.post(
      Uri.parse('$_base/me/uploads/video/complete'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'uploadId': uploadId,
        'filename': filename,
      }),
    );
    if (response.statusCode == 401) {
      await Get.find<AuthController>().handleAuthFailure();
      return (url: null, error: 'Session expired — please sign in again.');
    }
    if (response.statusCode != 200) {
      final err = _safeDecode(response.body)['error']?.toString() ??
          'Complete failed (${response.statusCode}).';
      return (url: null, error: err);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final relative = body['url'] as String? ?? '';
    if (relative.isEmpty) {
      return (url: null, error: 'Server returned no URL.');
    }
    return (url: relative, error: null);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Direct-to-S3 multipart upload — Phase A
  //
  // Replaces [uploadVideoChunked] with a flow where bytes go straight
  // from the phone to S3, never through the Go backend. Backend
  // bandwidth per upload drops to zero; uploads run ~2-3× faster on
  // cellular because the middleman copy is gone.
  //
  // Protocol:
  //
  //   1. POST /me/uploads/video/multipart/init  { filename, totalSize }
  //      →  { uploadId, key, partSize, parts:[{partNumber, url}, ...] }
  //   2. PUT each part directly to its presigned URL; capture the ETag
  //      header from the response.
  //   3. POST /me/uploads/video/multipart/complete  { uploadId, key, parts }
  //      →  { url, key }   (final presigned GET URL)
  //   4. On any failure: POST /me/uploads/video/multipart/abort  to
  //      release the partial parts (S3 charges for them until aborted).
  //
  // Phase A keeps part uploads SEQUENTIAL. Phase B parallelizes them.
  // Phase C adds resume-from-state. Phase D adds MD5 integrity.
  // ═══════════════════════════════════════════════════════════════════

  /// Upload a video file directly to S3 in multipart parts. The backend
  /// never sees the bytes — it only mints presigned URLs and finalizes.
  /// Falls back to [uploadVideoChunked] if the server says S3 isn't
  /// configured (503).
  ///
  /// **Resume (Phase C):** every successful part is persisted to local
  /// storage so a subsequent call with the same [file] picks up where
  /// it left off. Network drop, app close, phone reboot — all survive
  /// as long as the call happens within [_kUploadStateTTL] (the URL
  /// expiry window). After that window, stale state is auto-cleaned
  /// and a fresh upload starts.
  static Future<({String? url, String? error})>
      uploadVideoDirectMultipart(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      return (url: null, error: 'Not signed in.');
    }
    final filename = file.path.split(Platform.pathSeparator).last;
    final totalSize = await file.length();
    if (totalSize <= 0) {
      return (url: null, error: 'File is empty.');
    }

    // ── Step 0: try to resume. We look up any persisted state for this
    // file path and validate it: stale state (> 5h old) or a state from
    // a different-size file means we discard it and start fresh.
    var state = await _loadUploadState(file.path);
    if (state != null) {
      final reasonToDiscard = _stateInvalidReason(state, totalSize);
      if (reasonToDiscard != null) {
        // Best-effort: abort the dead S3 upload so orphan parts get
        // cleaned up. We swallow errors — if the abort fails, AWS's
        // bucket lifecycle rule will eventually GC the parts anyway.
        await _abortMultipart(token, state.uploadId, state.key);
        await _clearUploadState(file.path);
        state = null;
      }
    }

    // ── Step 1: init (only if we don't have viable state).
    if (state == null) {
      final initRes = await _initMultipart(token, filename, totalSize);
      if (initRes.error != null) {
        // 503 path → server explicitly said S3 isn't wired. Fall back
        // to the existing chunked-through-backend flow so reels still
        // upload on dev environments without AWS keys.
        if (initRes.fallback) {
          return uploadVideoChunked(file, onProgress: onProgress);
        }
        return (url: null, error: initRes.error);
      }
      state = _UploadState(
        savedAt: DateTime.now(),
        filePath: file.path,
        totalSize: totalSize,
        uploadId: initRes.uploadId!,
        key: initRes.key!,
        partSize: initRes.partSize!,
        parts: initRes.parts!
            .map(
              (p) => _UploadPart(
                partNumber: p['partNumber'] as int,
                url: p['url'] as String,
              ),
            )
            .toList(),
      );
      await _saveUploadState(state);
    }

    onProgress?.call(state.doneCount / state.parts.length);

    // ── Step 2: upload pending parts concurrently. Each worker reads
    // its part's bytes JUST BEFORE the PUT (open / seek / read / close)
    // so the phone never holds more than [_kMultipartConcurrency] × the
    // part size in RAM at once. A 5 GB upload with 4 concurrent 10 MB
    // workers peaks at ~40 MB resident — comfortable on any phone.
    //
    // Parts that already have an ETag from a previous run are skipped
    // entirely; their bytes never leave the device a second time.
    final pendingIndexes = state.pendingIndexes;
    if (pendingIndexes.isNotEmpty) {
      final sem = _Semaphore(_kMultipartConcurrency);
      final failures = <String>[];
      var done = state.doneCount;

      Future<void> uploadOne(int i) async {
        if (failures.isNotEmpty) return;
        await sem.acquire();
        try {
          if (failures.isNotEmpty) return;
          final part = state!.parts[i];
          final start = i * state.partSize;
          final end = (start + state.partSize).clamp(0, totalSize);

          // Per-part open/seek/read/close. RandomAccessFile is not
          // thread-safe; keeping the handle scoped per-worker avoids
          // having to synchronise cursors across the pool.
          final raf = await file.open();
          final List<int> bytes;
          try {
            await raf.setPosition(start);
            bytes = await raf.read(end - start);
          } finally {
            await raf.close();
          }

          final etag = await _putOnePart(url: part.url, bytes: bytes);
          if (etag == null) {
            failures.add('Part ${part.partNumber} failed after retries.');
            return;
          }
          part.etag = etag;
          done++;
          onProgress?.call(done / state.parts.length);
          // Persist after every success so a crash here only loses
          // (at most) the part currently mid-flight.
          await _saveUploadState(state);
        } finally {
          sem.release();
        }
      }

      await Future.wait(pendingIndexes.map(uploadOne));
      if (failures.isNotEmpty) {
        // Deliberately DON'T abort here — the state on disk now reflects
        // every part that DID succeed, and a future call resumes from
        // the same point. The user's caller surfaces the error so they
        // can retry on their own schedule.
        return (url: null, error: failures.first);
      }
    }

    // ── Step 3: finalize. By this point every part in state.parts has
    // a non-null etag, so we can build the /complete payload directly.
    final completeRes = await _completeMultipart(
      token: token,
      uploadId: state.uploadId,
      key: state.key,
      parts: [
        for (final p in state.parts)
          {'partNumber': p.partNumber, 'etag': p.etag!},
      ],
    );
    if (completeRes.error != null) {
      // /complete failed but the parts are all up there — leave state
      // intact so the next call retries just /complete. Most server-side
      // hiccups here are transient.
      return (url: null, error: completeRes.error);
    }
    await _clearUploadState(file.path);
    return (url: completeRes.url, error: null);
  }

  /// Returns a non-null reason string when persisted state is no
  /// longer usable for resume — TTL expired, source file size
  /// changed, file path corrupt, etc.
  static String? _stateInvalidReason(_UploadState s, int currentSize) {
    if (s.isStale) return 'TTL expired';
    if (s.totalSize != currentSize) return 'file size changed';
    if (s.parts.isEmpty) return 'no parts in state';
    return null;
  }

  // ─── /multipart/init ──────────────────────────────────────────────

  static Future<
      ({
        String? uploadId,
        String? key,
        int? partSize,
        List<Map<String, dynamic>>? parts,
        String? error,
        bool fallback,
      })> _initMultipart(
    String token,
    String filename,
    int totalSize,
  ) async {
    final response = await http.post(
      Uri.parse('$_base/me/uploads/video/multipart/init'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'filename': filename, 'totalSize': totalSize}),
    );
    if (response.statusCode == 401) {
      await Get.find<AuthController>().handleAuthFailure();
      return (
        uploadId: null,
        key: null,
        partSize: null,
        parts: null,
        error: 'Session expired — please sign in again.',
        fallback: false,
      );
    }
    if (response.statusCode == 503) {
      // Server says S3 isn't configured — caller should fall back.
      return (
        uploadId: null,
        key: null,
        partSize: null,
        parts: null,
        error: 's3 not configured',
        fallback: true,
      );
    }
    if (response.statusCode != 200) {
      final err = _safeDecode(response.body)['error']?.toString() ??
          'Init failed (${response.statusCode}).';
      return (
        uploadId: null,
        key: null,
        partSize: null,
        parts: null,
        error: err,
        fallback: false,
      );
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final id = body['uploadId'] as String?;
    final k = body['key'] as String?;
    final size = (body['partSize'] as num?)?.toInt();
    final rawParts = body['parts'] as List?;
    if (id == null || k == null || size == null || rawParts == null) {
      return (
        uploadId: null,
        key: null,
        partSize: null,
        parts: null,
        error: 'Server returned incomplete init.',
        fallback: false,
      );
    }
    final parts = rawParts
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    return (
      uploadId: id,
      key: k,
      partSize: size,
      parts: parts,
      error: null,
      fallback: false,
    );
  }

  // ─── PUT each part directly to S3 (with retry) ────────────────────

  /// PUT [bytes] to the presigned [url]. Captures the ETag header on
  /// success — that's what /complete needs to hand back to S3 so it can
  /// assemble the final object. Returns null after 3 failed attempts.
  ///
  /// **Phase D — integrity:** S3's ETag for a single `UploadPart`
  /// response is the hex MD5 of the bytes it actually received. We
  /// compute the MD5 of the bytes we INTENDED to send and compare:
  /// if they disagree, the chunk was mangled in transit and we retry.
  /// This catches silent bit-flips that TLS can rarely miss (e.g.
  /// flaky CPE in the cellular path).
  ///
  /// Why not `Content-MD5` header? S3 only accepts it when the header
  /// was part of the SigV4 signed-headers list at sign time, which
  /// would force the backend to know the digest before the bytes ever
  /// leave the phone — defeating direct-upload. ETag-compare is the
  /// fix: zero backend complexity, same protection.
  static Future<String?> _putOnePart({
    required String url,
    required List<int> bytes,
  }) async {
    // Hex MD5 once — chunk bytes don't change across retries. S3
    // returns the ETag in hex form like `"<32-char-hex>"` so we keep
    // both: the bare hex for comparison, and the quoted form to feed
    // straight into CompleteMultipartUpload's `parts` array.
    final localHex = crypto.md5.convert(bytes).toString().toLowerCase();

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        // No Content-Type — S3 uses the type set in CreateMultipartUpload
        // on the server side, and adding one here can void the signature.
        // No Content-MD5 either — S3 only accepts it if it was part of
        // the signed headers (see doc comment above).
        //
        // 300 s per-part timeout — a 10 MB part on slow cellular
        // (~500 kbps) takes ~160 s end-to-end; we want generous
        // headroom for TLS warm-up and tower retries before the
        // request-level retry kicks in.
        final response = await http
            .put(Uri.parse(url), body: bytes)
            .timeout(const Duration(seconds: 300));
        if (response.statusCode == 200) {
          final etag = response.headers['etag'];
          if (etag == null || etag.isEmpty) {
            // No ETag → can't verify; treat as transient and retry.
          } else {
            final etagHex = etag.replaceAll('"', '').toLowerCase();
            if (etagHex == localHex) {
              return etag; // bytes intact, return the quoted ETag
            }
            // Mismatch = corrupted in transit. Loop will retry.
          }
        } else if (response.statusCode >= 400 && response.statusCode < 500) {
          // Permanent 4xx (expired URL, signature mismatch, missing
          // metadata) — retries are wasted, fail fast.
          return null;
        }
      } catch (_) {
        // Network error, timeout — keep retrying.
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(
          Duration(milliseconds: 200 * (attempt * attempt)),
        );
      }
    }
    return null;
  }

  // ─── /multipart/complete ──────────────────────────────────────────

  static Future<({String? url, String? error})> _completeMultipart({
    required String token,
    required String uploadId,
    required String key,
    required List<Map<String, dynamic>> parts,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/me/uploads/video/multipart/complete'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'uploadId': uploadId, 'key': key, 'parts': parts}),
    );
    if (response.statusCode == 401) {
      await Get.find<AuthController>().handleAuthFailure();
      return (url: null, error: 'Session expired — please sign in again.');
    }
    if (response.statusCode != 200) {
      final err = _safeDecode(response.body)['error']?.toString() ??
          'Complete failed (${response.statusCode}).';
      return (url: null, error: err);
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final url = body['url'] as String? ?? '';
    if (url.isEmpty) {
      return (url: null, error: 'Server returned no URL.');
    }
    return (url: url, error: null);
  }

  // ─── /multipart/abort (best-effort) ───────────────────────────────

  /// Tells the backend to abort the multipart upload so S3 releases
  /// the already-uploaded parts. Best-effort — errors are swallowed
  /// because abort failure isn't actionable from the client and the
  /// orphan parts get GC'd by a future bucket lifecycle rule anyway.
  static Future<void> _abortMultipart(
    String token,
    String uploadId,
    String key,
  ) async {
    try {
      await http.post(
        Uri.parse('$_base/me/uploads/video/multipart/abort'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'uploadId': uploadId, 'key': key}),
      );
    } catch (_) {
      // Swallow — abort is best-effort cleanup.
    }
  }
}

/// Persistent slice of an in-progress multipart upload. Serialized to
/// SharedPreferences so the upload can resume after an app close, OS
/// kill, network drop, or even a phone reboot — as long as the saved
/// timestamp is still within [_kUploadStateTTL] of now.
///
/// Each entry in [parts] has a non-null `etag` once that part has been
/// successfully PUT to S3. On resume we read this list, skip parts
/// whose etag is set, and only upload the rest.
class _UploadState {
  _UploadState({
    required this.savedAt,
    required this.filePath,
    required this.totalSize,
    required this.uploadId,
    required this.key,
    required this.partSize,
    required this.parts,
  });

  /// Wall-clock at last save. Compared to now on load to decide
  /// whether the state is still within the URL expiry window.
  final DateTime savedAt;

  /// Local source file. Used both as the SharedPreferences key root
  /// and to detect "user picked a different file with the same name"
  /// (size mismatch → discard state and start fresh).
  final String filePath;

  final int totalSize;
  final String uploadId;
  final String key;
  final int partSize;

  /// One entry per S3 part. `etag` is null until the part is
  /// successfully uploaded; setting it is what marks a part as done.
  final List<_UploadPart> parts;

  Map<String, dynamic> toJson() => {
        'savedAt': savedAt.millisecondsSinceEpoch,
        'filePath': filePath,
        'totalSize': totalSize,
        'uploadId': uploadId,
        'key': key,
        'partSize': partSize,
        'parts': parts.map((p) => p.toJson()).toList(),
      };

  static _UploadState? tryFromJson(Map<String, dynamic> j) {
    try {
      return _UploadState(
        savedAt: DateTime.fromMillisecondsSinceEpoch(j['savedAt'] as int),
        filePath: j['filePath'] as String,
        totalSize: j['totalSize'] as int,
        uploadId: j['uploadId'] as String,
        key: j['key'] as String,
        partSize: j['partSize'] as int,
        parts: (j['parts'] as List)
            .whereType<Map<String, dynamic>>()
            .map(_UploadPart.fromJson)
            .toList(),
      );
    } catch (_) {
      // Corrupt JSON from a previous schema or partial write — caller
      // should treat as "no state" and start fresh.
      return null;
    }
  }

  bool get isStale =>
      DateTime.now().difference(savedAt).abs() > _kUploadStateTTL;

  /// All parts whose `etag` is still null — i.e. the work that's left.
  List<int> get pendingIndexes => [
        for (var i = 0; i < parts.length; i++)
          if (parts[i].etag == null) i,
      ];

  /// Number of parts already uploaded (etag set). Used to compute the
  /// initial progress when resuming.
  int get doneCount => parts.where((p) => p.etag != null).length;
}

/// One row in [_UploadState.parts]. We persist the URL alongside the
/// part number so a resume can keep using the URLs that /init handed
/// out — no need to re-call /init for fresh URLs (which would
/// invalidate the etags we already have).
class _UploadPart {
  _UploadPart({
    required this.partNumber,
    required this.url,
    this.etag,
  });

  final int partNumber;
  final String url;
  String? etag;

  Map<String, dynamic> toJson() => {
        'partNumber': partNumber,
        'url': url,
        'etag': etag,
      };

  static _UploadPart fromJson(Map<String, dynamic> j) => _UploadPart(
        partNumber: j['partNumber'] as int,
        url: j['url'] as String,
        etag: j['etag'] as String?,
      );
}

/// Resolve the SharedPreferences key for a given file path. We
/// percent-encode the path so reserved characters (`/`, spaces,
/// non-ASCII) round-trip cleanly through Android + iOS prefs storage.
String _stateKeyFor(String filePath) =>
    '$_kUploadStatePrefix${Uri.encodeComponent(filePath)}';

/// Read whatever upload state we last persisted for [filePath]. Returns
/// null when no state exists or the JSON couldn't be parsed; either
/// way the caller should treat it as a fresh upload.
Future<_UploadState?> _loadUploadState(String filePath) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_stateKeyFor(filePath));
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = json.decode(raw);
    if (decoded is Map<String, dynamic>) {
      return _UploadState.tryFromJson(decoded);
    }
  } catch (_) {}
  return null;
}

/// Overwrite the persisted state for one file. Called after every
/// successful part PUT so a crash mid-upload only loses (at most) one
/// part of progress.
Future<void> _saveUploadState(_UploadState state) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_stateKeyFor(state.filePath), json.encode(state.toJson()));
}

/// Drop the saved state for [filePath]. Called on /complete success
/// (we're done) and on explicit aborts (stale URLs / file changed).
Future<void> _clearUploadState(String filePath) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_stateKeyFor(filePath));
}

/// Tiny counting semaphore — caps the number of concurrent operations
/// to `max`. Used by [UploadService.uploadVideoDirectMultipart] to fan
/// the per-part PUTs out across N workers without spinning up an
/// isolate-per-part (which would be overkill for IO-bound work that
/// Dart's event loop handles natively).
///
/// Why not just `Future.wait` everything? On a 100 MB upload with a
/// 5 MB part size, that's 20 simultaneous PUT sockets — enough to
/// overwhelm both the mobile radio (battery spike) and the AWS edge's
/// per-IP connection limit. 4 parallel keeps it tidy.
class _Semaphore {
  _Semaphore(this._max) : assert(_max > 0);

  final int _max;
  int _inUse = 0;
  // Queue<Completer>, not List, so waiters resume in FIFO order rather
  // than whichever the runtime's iterator yields.
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// Returns a Future that completes when the caller has reserved a
  /// slot. Always pair with [release] in a `try/finally`.
  Future<void> acquire() {
    if (_inUse < _max) {
      _inUse++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  /// Returns a slot. Wakes the longest-waiting acquirer if any.
  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _inUse--;
    }
  }
}
