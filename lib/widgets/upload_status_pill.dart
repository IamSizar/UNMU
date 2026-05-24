import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/upload_controller.dart';

/// Global, app-wide upload status indicator. Injected once into the app
/// shell (GetMaterialApp.builder) so it floats over EVERY screen — the
/// upload runs in [UploadController], so it keeps going as the user roams.
///
/// Collapsed: a compact pill with a circular progress ring + %.
/// Tapped:    expands to a card with a full progress line + Retry/Dismiss.
/// Animated:  slides down + fades in when an upload starts; phase-colored
///            (cyan = working, green = done, red = failed).
class UploadStatusPill extends StatefulWidget {
  const UploadStatusPill({super.key});

  @override
  State<UploadStatusPill> createState() => _UploadStatusPillState();
}

class _UploadStatusPillState extends State<UploadStatusPill> {
  bool _expanded = false;

  static const _cyan = Color(0xFF22D3EE);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFFF6B7A);

  @override
  Widget build(BuildContext context) {
    final c = Get.find<UploadController>();

    return Obx(() {
      if (!c.isVisible) return const SizedBox.shrink();

      final phase = c.phase.value;
      final p = c.progress.value;
      final pct = (p * 100).clamp(0, 100).round();

      final Color accent;
      final IconData icon;
      final String label;
      switch (phase) {
        case UploadPhase.reading:
          accent = _cyan;
          icon = Icons.movie_outlined;
          label = c.statusNote.value.isNotEmpty
              ? c.statusNote.value
              : 'Reading video…';
          break;
        case UploadPhase.uploading:
          accent = _cyan;
          icon = Icons.cloud_upload_outlined;
          label = 'Uploading video…';
          break;
        case UploadPhase.finalizing:
          accent = _cyan;
          icon = Icons.cloud_upload_outlined;
          label = 'Finishing up…';
          break;
        case UploadPhase.success:
          accent = _green;
          icon = Icons.check_circle_rounded;
          label = 'Video uploaded';
          break;
        case UploadPhase.failed:
          accent = _red;
          icon = Icons.error_outline_rounded;
          label = 'Upload failed';
          break;
        case UploadPhase.idle:
          return const SizedBox.shrink();
      }

      final indeterminate = phase == UploadPhase.reading ||
          phase == UploadPhase.finalizing;
      final done = phase == UploadPhase.success;
      final failed = phase == UploadPhase.failed;

      // Slide-down + fade entrance each time the pill (re)appears.
      return SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(phase),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, (t - 1) * -16), child: child),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: (done || failed)
                      ? null
                      : () => setState(() => _expanded = !_expanded),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    constraints: const BoxConstraints(maxWidth: 460),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B1F).withValues(alpha: 0.97),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent.withValues(alpha: 0.45)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            _Leading(
                              accent: accent,
                              icon: icon,
                              indeterminate: indeterminate,
                              done: done,
                              failed: failed,
                              progress: p,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (c.fileName.value.isNotEmpty && !done && !failed)
                                    Text(
                                      c.fileName.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  if (failed && c.error.value.isNotEmpty)
                                    Text(
                                      c.error.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (phase == UploadPhase.uploading)
                              Text(
                                '$pct%',
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            if (failed)
                              TextButton(
                                onPressed: c.retry,
                                style: TextButton.styleFrom(
                                  foregroundColor: accent,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: const Size(0, 32),
                                ),
                                child: const Text(
                                  'Retry',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            if (done || failed)
                              IconButton(
                                onPressed: c.dismiss,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close_rounded,
                                    size: 18, color: Colors.white54),
                              )
                            else
                              Icon(
                                _expanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 20,
                                color: Colors.white38,
                              ),
                          ],
                        ),
                        // Tap-to-reveal full progress line.
                        if (_expanded && !done && !failed) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: indeterminate ? null : p,
                              minHeight: 6,
                              backgroundColor: Colors.white12,
                              valueColor: AlwaysStoppedAnimation(accent),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Leading badge: a circular progress ring with the phase icon (or spinner
/// for indeterminate steps), check on success, warning on failure.
class _Leading extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final bool indeterminate;
  final bool done;
  final bool failed;
  final double progress;

  const _Leading({
    required this.accent,
    required this.icon,
    required this.indeterminate,
    required this.done,
    required this.failed,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!done && !failed)
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                value: indeterminate ? null : progress,
                strokeWidth: 2.4,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          Icon(icon, size: 15, color: accent),
        ],
      ),
    );
  }
}
