import 'package:vibration/vibration.dart';

class HapticUtils {
  /// Light tap for card selections, day pickers, etc.
  static Future<void> lightTap() async {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 10);
    }
  }

  /// Success vibration for primary actions (form submission, etc.)
  static Future<void> success() async {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 50);
    }
  }

  /// Selection feedback for switches, toggles
  static Future<void> selection() async {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 10);
    }
  }

  /// Error feedback
  static Future<void> error() async {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(pattern: [0, 100, 50, 100]);
    }
  }
}

