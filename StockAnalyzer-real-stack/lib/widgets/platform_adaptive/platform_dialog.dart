import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../utils/platform_utils.dart';

class PlatformDialog {
  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String content,
    String? confirmText,
    String? cancelText,
    VoidCallback? onConfirm,
    bool isDestructive = false,
  }) {
    if (PlatformUtils.isIOS) {
      // iOS: Use Cupertino alert dialog
      return showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            if (cancelText != null)
              CupertinoDialogAction(
                child: Text(cancelText),
                onPressed: () => Navigator.pop(context, false),
              ),
            CupertinoDialogAction(
              isDestructiveAction: isDestructive,
              child: Text(confirmText ?? 'OK'),
              onPressed: () {
                Navigator.pop(context, true);
                onConfirm?.call();
              },
            ),
          ],
        ),
      );
    } else {
      // Android: Use Material alert dialog
      return showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            if (cancelText != null)
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(cancelText),
              ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
                onConfirm?.call();
              },
              style: isDestructive
                  ? TextButton.styleFrom(foregroundColor: Colors.red)
                  : null,
              child: Text(confirmText ?? 'OK'),
            ),
          ],
        ),
      );
    }
  }
}

