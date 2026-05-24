import 'dart:io';

import 'package:get/get.dart';

import '../services/upload_service.dart';

/// Lifecycle phases of a media upload, surfaced by the global status pill.
enum UploadPhase { idle, reading, uploading, finalizing, success, failed }

/// App-wide background upload manager.
///
/// Owns the long-running video upload so it KEEPS RUNNING when the user
/// leaves the composer and roams the app — the upload lives here, not in any
/// screen's State. A single global pill (UploadStatusPill, injected into the
/// app shell) renders this controller's reactive state on every screen.
///
/// The composer kicks an upload off with [startVideoUpload] and then reads
/// [resultUrl] / [progress] / [phase] reactively; publishing uses [resultUrl].
class UploadController extends GetxController {
  final Rx<UploadPhase> phase = UploadPhase.idle.obs;

  /// 0..1 upload progress (driven by the direct-to-S3 multipart per-part
  /// callback). Only meaningful while [phase] is uploading/finalizing.
  final RxDouble progress = 0.0.obs;

  /// Human-readable label for the "Reading video…" pre-upload step (e.g. a
  /// duration probe) so the pill never looks frozen while we prepare.
  final RxString statusNote = ''.obs;

  final RxString error = ''.obs;
  final RxString fileName = ''.obs;

  /// Set the moment the upload finishes; the composer reads this to fill the
  /// post's media URL. Survives the auto-reset of [phase] back to idle.
  final RxnString resultUrl = RxnString();

  File? _lastFile;

  /// True while a real upload is mid-flight — drives whether the pill shows.
  bool get isActive =>
      phase.value == UploadPhase.reading ||
      phase.value == UploadPhase.uploading ||
      phase.value == UploadPhase.finalizing;

  bool get isVisible => phase.value != UploadPhase.idle;

  /// Mark the "reading / preparing" phase (the composer probes duration
  /// before handing the file over). Keeps the pill informative during the
  /// step that used to feel like a silent freeze.
  void beginReading([String note = '']) {
    _lastFile = null;
    resultUrl.value = null;
    error.value = '';
    progress.value = 0.0;
    statusNote.value = note;
    phase.value = UploadPhase.reading;
  }

  /// Cancel the reading state without starting an upload (e.g. the user
  /// cancelled the picker, or the file failed validation).
  void cancelReading() {
    if (phase.value == UploadPhase.reading) dismiss();
  }

  /// Upload [file] in the background. Returns immediately for the caller;
  /// progress + completion land on the reactive fields. Validation
  /// (duration, type) is the caller's job — this owns only the transfer.
  Future<void> startVideoUpload(File file) async {
    _lastFile = file;
    fileName.value = file.path.split(Platform.pathSeparator).last;
    error.value = '';
    resultUrl.value = null;
    statusNote.value = '';
    progress.value = 0.0;
    phase.value = UploadPhase.uploading;

    final res = await UploadService.uploadVideoDirectMultipart(
      file,
      onProgress: (p) {
        progress.value = p;
        if (p >= 0.999 && phase.value == UploadPhase.uploading) {
          phase.value = UploadPhase.finalizing;
        }
      },
    );

    if (res.url != null) {
      resultUrl.value = res.url;
      progress.value = 1.0;
      phase.value = UploadPhase.success;
      // Linger on success briefly, then fade the pill out. resultUrl stays
      // so the composer can still read it after the pill is gone.
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (phase.value == UploadPhase.success) phase.value = UploadPhase.idle;
      });
    } else {
      error.value = res.error ?? 'Upload failed';
      phase.value = UploadPhase.failed;
    }
  }

  /// Re-run the last upload (the pill's "Retry" on failure). Direct-multipart
  /// resumes from the parts already on S3, so this is cheap.
  Future<void> retry() async {
    final f = _lastFile;
    if (f != null) await startVideoUpload(f);
  }

  void dismiss() {
    phase.value = UploadPhase.idle;
    progress.value = 0.0;
    error.value = '';
    statusNote.value = '';
  }
}
