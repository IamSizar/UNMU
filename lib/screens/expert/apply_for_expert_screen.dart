import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/api_config.dart';
import '../../models/expert_application.dart';
import '../../services/expert_application_service.dart';
import '../../services/upload_service.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';

/// Form screen where a regular user submits their request to become an expert.
///
/// Shows:
///  - Avatar + resume PDF upload pickers (mig 0023)
///  - Full name, expertise (e.g. "Tech Stocks", "Sukuk"), bio
///  - Country (optional)
///  - Credentials list (chip-style add/remove)
///  - Sample work links (optional)
///
/// `prefill` lets the re-apply flow seed the form with the user's last
/// rejected application so they only edit what changed (item A5).
///
/// On success, pops with the freshly-created [ExpertApplication] so the
/// caller (profile screen) can refresh its banner.
class ApplyForExpertScreen extends StatefulWidget {
  final ExpertApplication? prefill;
  const ApplyForExpertScreen({super.key, this.prefill});

  @override
  State<ApplyForExpertScreen> createState() => _ApplyForExpertScreenState();
}

class _ApplyForExpertScreenState extends State<ApplyForExpertScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _expertise = TextEditingController();
  final _bio = TextEditingController();
  final _country = TextEditingController();
  final _credentialInput = TextEditingController();
  final _linkInput = TextEditingController();
  final List<String> _credentials = [];
  final List<String> _sampleLinks = [];

  // Resume + avatar uploads (A6). The relative URL the backend returns
  // is what we send in the submit payload.
  String? _resumeUrl;
  String? _resumeFileName;
  bool _resumeUploading = false;

  String? _avatarUrl;
  bool _avatarUploading = false;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p != null) {
      _fullName.text = p.fullName;
      _expertise.text = p.expertise;
      _bio.text = p.bio;
      _country.text = p.country ?? '';
      _credentials.addAll(p.credentials);
      _sampleLinks.addAll(p.sampleLinks);
      _resumeUrl = p.resumeUrl;
      _avatarUrl = p.avatarUrl;
      if (p.resumeUrl != null) {
        _resumeFileName = p.resumeUrl!.split('/').last;
      }
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _expertise.dispose();
    _bio.dispose();
    _country.dispose();
    _credentialInput.dispose();
    _linkInput.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() {
      _avatarUploading = true;
      _error = null;
    });
    final res = await UploadService.uploadImage(File(picked.path));
    if (!mounted) return;
    setState(() {
      _avatarUploading = false;
      if (res.error != null) {
        _error = res.error;
      } else {
        _avatarUrl = res.url;
      }
    });
  }

  Future<void> _pickResume() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    setState(() {
      _resumeUploading = true;
      _error = null;
    });
    final res = await UploadService.uploadDocument(File(path));
    if (!mounted) return;
    setState(() {
      _resumeUploading = false;
      if (res.error != null) {
        _error = res.error;
      } else {
        _resumeUrl = res.url;
        _resumeFileName = result.files.single.name;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ExpertApplicationService.submit(
      fullName: _fullName.text.trim(),
      expertise: _expertise.text.trim(),
      bio: _bio.text.trim(),
      country: _country.text.trim().isEmpty ? null : _country.text.trim(),
      credentials: _credentials,
      sampleLinks: _sampleLinks,
      resumeUrl: _resumeUrl,
      avatarUrl: _avatarUrl,
    );

    if (!mounted) return;

    if (result.app != null) {
      Navigator.of(context).pop(result.app);
      return;
    }
    setState(() {
      _submitting = false;
      // Cool-down message preferred over the raw error so it explains
      // _when_ they can retry, not just "rejected".
      if (result.retryAfterSeconds != null) {
        _error = _formatCooldown(result.retryAfterSeconds!);
      } else {
        _error = result.error ?? 'apply.submitFailed'.tr;
      }
    });
  }

  String _formatCooldown(int seconds) {
    final hours = (seconds / 3600).ceil();
    if (hours >= 24) {
      final days = (hours / 24).ceil();
      return 'apply.cooldownDays'.trParams({
        'count': '$days',
        'plural': days == 1 ? '' : 's',
      });
    }
    return 'apply.cooldownHours'.trParams({
      'count': '$hours',
      'plural': hours == 1 ? '' : 's',
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isReapply = widget.prefill != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isReapply ? 'apply.titleReapply'.tr : 'apply.title'.tr),
        elevation: 0,
      ),
      body: SafeArea(
        child: DismissKeyboardOnTap(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _IntroCard(),
              const SizedBox(height: 20),

              // Step 28 — on the re-apply flow, surface the admin's
              // rejection reason inline at the top of the form so
              // the applicant can directly address it instead of
              // guessing what to change. Only fires when there's
              // both a prefill (re-apply) AND a non-empty reason.
              if (isReapply &&
                  (widget.prefill!.rejectionReason ?? '').isNotEmpty) ...[
                _RejectionBanner(reason: widget.prefill!.rejectionReason!),
                const SizedBox(height: 20),
              ],

              _SectionLabel('apply.avatarSection'.tr),
              const SizedBox(height: 8),
              _AvatarPickerTile(
                avatarUrl: _avatarUrl,
                uploading: _avatarUploading,
                onTap: _avatarUploading ? null : _pickAvatar,
                onClear: _avatarUrl == null
                    ? null
                    : () => setState(() => _avatarUrl = null),
              ),

              const SizedBox(height: 20),
              _SectionLabel('apply.resumeSection'.tr),
              const SizedBox(height: 8),
              _ResumePickerTile(
                fileName: _resumeFileName,
                resumeUrl: _resumeUrl,
                uploading: _resumeUploading,
                onTap: _resumeUploading ? null : _pickResume,
                onClear: _resumeUrl == null
                    ? null
                    : () => setState(() {
                          _resumeUrl = null;
                          _resumeFileName = null;
                        }),
              ),

              const SizedBox(height: 24),
              _SectionLabel('apply.detailsSection'.tr),
              const SizedBox(height: 8),
              TextFormField(
                controller: _fullName,
                decoration: InputDecoration(
                  labelText: 'apply.fullNameLabel'.tr,
                  hintText: 'apply.fullNameHint'.tr,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'common.required'.tr : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _expertise,
                decoration: InputDecoration(
                  labelText: 'apply.expertiseLabel'.tr,
                  hintText: 'apply.expertiseHint'.tr,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'common.required'.tr : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _country,
                decoration: InputDecoration(
                  labelText: 'apply.countryLabel'.tr,
                  hintText: 'apply.countryHint'.tr,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bio,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'apply.bioLabel'.tr,
                  hintText: 'apply.bioHint'.tr,
                ),
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.length < 20) return 'apply.bioTooShort'.tr;
                  return null;
                },
              ),
              const SizedBox(height: 24),

              _SectionLabel('apply.credentialsSection'.tr),
              const SizedBox(height: 8),
              _ChipInput(
                controller: _credentialInput,
                hint: 'apply.credentialsHint'.tr,
                items: _credentials,
                onAdd: (v) => setState(() => _credentials.add(v)),
                onRemove: (i) => setState(() => _credentials.removeAt(i)),
              ),

              const SizedBox(height: 24),
              _SectionLabel('apply.sampleSection'.tr),
              const SizedBox(height: 8),
              _ChipInput(
                controller: _linkInput,
                hint: 'apply.sampleHint'.tr,
                items: _sampleLinks,
                onAdd: (v) => setState(() => _sampleLinks.add(v)),
                onRemove: (i) => setState(() => _sampleLinks.removeAt(i)),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.error.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: cs.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(color: cs.onErrorContainer)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isReapply ? 'apply.resubmit'.tr : 'apply.submit'.tr),
              ),
              const SizedBox(height: 16),
              Text(
                'apply.reviewNote'.tr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.15),
            cs.tertiary.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.school_outlined, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('apply.introTitle'.tr,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 2),
                Text(
                  'apply.introSubtitle'.tr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _ChipInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final List<String> items;
  final ValueChanged<String> onAdd;
  final ValueChanged<int> onRemove;

  const _ChipInput({
    required this.controller,
    required this.hint,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  void _commit() {
    final raw = controller.text.trim();
    if (raw.isEmpty) return;
    onAdd(raw);
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(hintText: hint),
                onSubmitted: (_) => _commit(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _commit,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < items.length; i++)
                InputChip(
                  label: Text(items[i]),
                  onDeleted: () => onRemove(i),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// Avatar + resume tiles
//
// Both render a single row "tap to choose / replace" with status text and
// a remove button when populated. Visual style mirrors the rest of the
// form's input chips so the page feels coherent.
// =============================================================================

class _AvatarPickerTile extends StatelessWidget {
  final String? avatarUrl;
  final bool uploading;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  const _AvatarPickerTile({
    required this.avatarUrl,
    required this.uploading,
    required this.onTap,
    required this.onClear,
  });

  String _absolute(String relative) {
    if (relative.startsWith('http')) return relative;
    final base = ApiConfig.baseUrl;
    final origin = base.split('/api').first;
    return '$origin$relative';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: cs.primary.withValues(alpha: 0.15),
                backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                    ? NetworkImage(_absolute(avatarUrl!))
                    : null,
                child: (avatarUrl == null || avatarUrl!.isEmpty)
                    ? Icon(Icons.person, color: cs.primary, size: 26)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      avatarUrl == null
                          ? 'apply.avatarAdd'.tr
                          : 'apply.avatarUploaded'.tr,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      avatarUrl == null
                          ? 'apply.avatarHint'.tr
                          : 'apply.tapToReplace'.tr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (uploading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (onClear != null)
                IconButton(
                  tooltip: 'common.remove'.tr,
                  onPressed: onClear,
                  icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                )
              else
                Icon(Icons.add_a_photo_outlined, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumePickerTile extends StatelessWidget {
  final String? fileName;
  final String? resumeUrl;
  final bool uploading;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  const _ResumePickerTile({
    required this.fileName,
    required this.resumeUrl,
    required this.uploading,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.picture_as_pdf_rounded,
                  color: cs.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      resumeUrl == null
                          ? 'apply.resumeAdd'.tr
                          : (fileName ?? 'apply.resumeUploaded'.tr),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      resumeUrl == null
                          ? 'apply.resumeHint'.tr
                          : 'apply.tapToReplace'.tr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (uploading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (onClear != null)
                IconButton(
                  tooltip: 'common.remove'.tr,
                  onPressed: onClear,
                  icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                )
              else
                Icon(Icons.upload_file, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Step 28 — Inline rejection-reason banner shown at the top of the
// re-apply form so the applicant can see what the admin said before
// editing fields. Soft amber styling so it reads as guidance, not
// failure.
// =============================================================================
class _RejectionBanner extends StatelessWidget {
  final String reason;
  const _RejectionBanner({required this.reason});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'apply.rejectionTitle'.tr,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
