import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/report_service.dart';

/// Bottom-sheet that lets the user pick a reason, optionally add a note,
/// and submit a report. Returns true when the report was accepted (or
/// already existed) so the caller can show a "Thanks — we'll review it"
/// toast.
///
/// Usage from a post-overflow menu:
/// ```dart
/// final ok = await ReportSheet.show(
///   context,
///   targetType: 'post',
///   targetId: post.id.toString(),
/// );
/// if (ok && context.mounted) {
///   ScaffoldMessenger.of(context).showSnackBar(...);
/// }
/// ```
class ReportSheet extends StatefulWidget {
  final String targetType;
  final String targetId;

  /// What the user is reporting, in plain English — used in the sheet's
  /// header so the user knows what they're flagging.
  /// (e.g. "this post", "@arman", "this comment".)
  final String? targetLabel;

  const ReportSheet({
    super.key,
    required this.targetType,
    required this.targetId,
    this.targetLabel,
  });

  /// Convenience launcher. Returns true on accepted, false on cancel.
  static Future<bool> show(
    BuildContext context, {
    required String targetType,
    required String targetId,
    String? targetLabel,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: ReportSheet(
          targetType: targetType,
          targetId: targetId,
          targetLabel: targetLabel,
        ),
      ),
    );
    return result == true;
  }

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  String? _selectedReason;
  final _detailsController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) {
      setState(() => _error = 'report.pickReason'.tr);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ReportService.submit(
      targetType: widget.targetType,
      targetId: widget.targetId,
      reason: _selectedReason!,
      details: _detailsController.text.trim().isEmpty
          ? null
          : _detailsController.text.trim(),
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _error = result.error;
        _submitting = false;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle.
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'report.title'.trParams(
              {'target': widget.targetLabel ?? 'report.targetDefault'.tr},
            ),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'report.subtitle'.tr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                children: ReportService.reasons
                    .map((code) => _ReasonTile(
                          code: code,
                          label: ReportService.reasonLabel(code),
                          selected: _selectedReason == code,
                          onTap: () => setState(() => _selectedReason = code),
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _detailsController,
            maxLines: 3,
            maxLength: 2000,
            decoration: InputDecoration(
              labelText: 'report.detailsLabel'.tr,
              hintText: 'report.detailsHint'.tr,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                  child: Text('common.cancel'.tr),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text('report.submit'.tr),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ReasonTile({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.hintColor,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
