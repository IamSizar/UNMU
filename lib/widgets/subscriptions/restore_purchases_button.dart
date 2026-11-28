import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/iap_service.dart';

/// "Restore purchases" action (App Store Review Guideline 3.1.1 requires a
/// way to restore in-app purchases). Shown on iOS only: Android purchases
/// cannot be verified by the backend yet, so a restore there would fail.
///
/// The restore result arrives later on the IAP purchase stream; screens
/// listening to [IAPService.verifiedRestores] reload when it lands.
class RestorePurchasesButton extends StatefulWidget {
  /// Starts a restore; returns false when the store is unavailable.
  /// Defaults to the real store. Tests pass a fake.
  final Future<bool> Function()? onRestore;

  const RestorePurchasesButton({super.key, this.onRestore});

  @override
  State<RestorePurchasesButton> createState() => _RestorePurchasesButtonState();
}

class _RestorePurchasesButtonState extends State<RestorePurchasesButton> {
  bool _busy = false;

  Future<void> _restore() async {
    setState(() => _busy = true);
    final restore = widget.onRestore ?? IAPService.instance.restorePurchases;
    var started = false;
    try {
      started = await restore();
    } catch (e) {
      debugPrint('[iap] restore failed: $e');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(started
          ? 'mySubscriptions.restoreStarted'.tr
          : 'mySubscriptions.restoreUnavailable'.tr),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }
    return TextButton(
      onPressed: _busy ? null : _restore,
      child: _busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            )
          : Text('mySubscriptions.restore'.tr),
    );
  }
}
