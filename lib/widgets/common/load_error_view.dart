import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Designed "couldn't load" state with a Retry button, for screens whose
/// first load failed and that have nothing cached to show.
/// While [busy] the button is replaced by a spinner so a tap gives feedback.
class LoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final bool busy;

  const LoadErrorView({super.key, required this.onRetry, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'common.loadFailed.title'.tr,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'common.loadFailed.body'.tr,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: busy
                ? const Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child:
                          CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                  )
                : FilledButton(
                    onPressed: onRetry,
                    child: Text('common.retry'.tr),
                  ),
          ),
        ],
      ),
    );
  }
}
