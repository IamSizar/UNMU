import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Layered haptic feedback. Each method:
///
///   1. Calls the Flutter [HapticFeedback] hook — this drives the native
///      iOS taptic engine and the Android system haptic actuator at the
///      OS-recommended intensity for that gesture. Feels "modern" on
///      iPhone 8+ / iPad Pro / most Pixel-class Androids.
///
///   2. Fires a short supplemental [Vibration] pulse on devices where the
///      native HapticFeedback hook isn't expressive enough — older
///      Android phones in particular. The pulse is small and adds
///      perceptible texture; on devices that already produced a sharp
///      taptic click, the extra pulse is below the noticeable threshold.
///
/// The async [Vibration.hasVibrator] check is cached per-process to
/// avoid the platform channel hop on every tap (which adds frame jank
/// when tapping rapidly).
class HapticUtils {
  static bool? _hasVibrator;
  static Future<bool> _supportsVibration() async {
    _hasVibrator ??= await Vibration.hasVibrator();
    return _hasVibrator!;
  }

  /// Brief click — buttons, card taps, list items, FAB taps. Most common;
  /// reach for this first.
  static Future<void> tap() async {
    HapticFeedback.lightImpact();
    if (await _supportsVibration()) {
      Vibration.vibrate(duration: 8, amplitude: 32);
    }
  }

  /// Tactile picker click — tab switches, segmented controls, toggle
  /// chips, scroll-snap selections.
  static Future<void> pick() async {
    HapticFeedback.selectionClick();
    if (await _supportsVibration()) {
      Vibration.vibrate(duration: 6, amplitude: 24);
    }
  }

  /// Heavier confirm — successful submit, post published, payment
  /// accepted. Reserve for state-changing interactions, not routine taps.
  static Future<void> confirm() async {
    HapticFeedback.mediumImpact();
    if (await _supportsVibration()) {
      Vibration.vibrate(duration: 18, amplitude: 80);
    }
  }

  /// Strong success burst — celebrate big moments (subscription accepted,
  /// expert role unlocked). Two short pulses so it feels like a chord
  /// rather than a click.
  static Future<void> celebrate() async {
    HapticFeedback.heavyImpact();
    if (await _supportsVibration()) {
      Vibration.vibrate(
        pattern: [0, 16, 60, 24],
        intensities: [0, 120, 0, 200],
      );
    }
  }

  /// Pattern that reads as "wrong" — used for failed submissions or
  /// locked content the user just bumped into.
  static Future<void> errorBuzz() async {
    HapticFeedback.heavyImpact();
    if (await _supportsVibration()) {
      Vibration.vibrate(pattern: [0, 90, 50, 90]);
    }
  }

  // ─── Backwards-compatible aliases for existing call sites ──────────
  // These names predate the semantic naming above. Keep the API stable
  // so nothing breaks; new code should use [tap] / [pick] / [confirm].
  static Future<void> lightTap() => tap();
  static Future<void> success() => confirm();
  static Future<void> selection() => pick();
  static Future<void> error() => errorBuzz();
}
