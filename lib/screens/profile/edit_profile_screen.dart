import 'dart:io';

import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';

import '../../widgets/dismiss_keyboard_on_tap.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get/get.dart';

import '../../config/api_config.dart';
import '../../controllers/auth_controller.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/upload_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/auth/auth_widgets.dart';

/// =============================================================================
/// Edit Profile Screen — modern editor.
///
/// Features:
///   ▸ Big avatar at the top — tap to pick a new image (gallery / camera) or
///     swap to a colored gradient avatar
///   ▸ Inline name field
///   ▸ Read-only email (with lock indicator)
///   ▸ Accent color picker (8 brand-friendly options) for the gradient
///     avatar fallback
///   ▸ Save CTA — disabled until something has actually changed
/// =============================================================================
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final String _initialName;

  /// The image file the user picked in *this* edit session — populated
  /// after a successful gallery / camera pick, cleared when they tap
  /// "Remove image". When non-null at save time we upload it to
  /// /me/uploads/image, then send the returned URL to PATCH /me/profile.
  String? _pickedImagePath;
  Color? _pickedAccent;
  bool _saving = false;
  bool _picking = false; // guards double-taps on the picker

  // Brand-friendly accent palette for the gradient avatar.
  static const List<Color> _accentChoices = [
    SocialTokens.cyan,
    SocialTokens.gold,
    SocialTokens.up,
    SocialTokens.down,
    Color(0xFF8B5CF6), // purple
    Color(0xFFF472B6), // pink
    Color(0xFF38BDF8), // sky
    Color(0xFFFB923C), // orange
  ];

  @override
  void initState() {
    super.initState();
    final auth = Get.find<AuthController>();
    _initialName = auth.user?.name ?? '';
    _name = TextEditingController(text: _initialName);
    _pickedImagePath = auth.avatarPath;
    _pickedAccent = auth.avatarAccent;
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final auth = Get.find<AuthController>();
    return _name.text.trim() != _initialName.trim() ||
        _pickedImagePath != auth.avatarPath ||
        _pickedAccent != auth.avatarAccent;
  }

  Future<void> _showAvatarSheet() async {
    if (_picking) return;
    HapticUtils.lightTap();
    final palette = SocialTheme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _AvatarPickerSheet(
          palette: palette,
          onGallery: () {
            Navigator.pop(ctx);
            _pickFromSource(ImageSource.gallery);
          },
          onCamera: () {
            Navigator.pop(ctx);
            _pickFromSource(ImageSource.camera);
          },
          onClearImage: _pickedImagePath == null
              ? null
              : () {
                  Navigator.pop(ctx);
                  setState(() => _pickedImagePath = null);
                },
        );
      },
    );
  }

  Future<void> _pickFromSource(ImageSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (picked != null) {
        setState(() {
          _pickedImagePath = picked.path;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'editProfile.pickImageFailed'.trParams({'error': '$e'}),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (!_hasChanges) return;
    setState(() => _saving = true);
    HapticUtils.lightTap();
    final auth = Get.find<AuthController>();

    // 1. If the user picked a NEW local image (path differs from what
    //    we started with), upload it first and capture the returned URL
    //    so it gets persisted on the backend's users.avatar_url column.
    //
    //    If they kept the same local path → no re-upload (cheap), and
    //    we don't touch avatar_url. If they cleared the image → send
    //    an empty avatarUrl so the server clears the column too.
    String? avatarUrlForPatch;
    bool clearAvatarUrl = false;
    final picked = _pickedImagePath;
    final initial = auth.avatarPath;

    if (picked != null && picked != initial && !picked.startsWith('http')) {
      // Fresh local file picked this session — upload to S3 / disk.
      final result = await UploadService.uploadImage(File(picked));
      if (!mounted) return;
      if (result.error != null || result.url == null) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error ?? 'editProfile.avatarUploadFailed'.tr,
            ),
          ),
        );
        return;
      }
      avatarUrlForPatch = result.url;
    } else if (picked == null && (auth.user?.avatarUrl ?? '').isNotEmpty) {
      // User cleared the image AND the backend currently has a URL —
      // tell the backend to clear it too.
      clearAvatarUrl = true;
    }

    final error = await auth.updateProfile(
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      avatarUrl: avatarUrlForPatch,
      clearAvatarUrl: clearAvatarUrl,
      avatarPath: _pickedImagePath,
      avatarAccent: _pickedAccent,
      clearAvatarPath: _pickedImagePath == null && auth.avatarPath != null,
      clearAvatarAccent: _pickedAccent == null && auth.avatarAccent != null,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    await HapticUtils.success();
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// Resolve a relative `/uploads/...` path to an absolute URL the
  /// network image widget can fetch. S3-presigned URLs (already absolute)
  /// pass through unchanged.
  String _resolveAvatarUrl(String value) {
    if (value.startsWith('http')) return value;
    final origin = ApiConfig.baseUrl.split('/api').first;
    return '$origin$value';
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final auth = Get.find<AuthController>();
    final email = auth.user?.email ?? '';

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        leading: IconButton(
          icon: DirectionalIcon(
            Icons.arrow_back_rounded,
            color: palette.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'editProfile.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: DismissKeyboardOnTap(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              // Avatar editor. Priority for the source image:
              //   1. Local pick this session → render the file directly
              //   2. Backend users.avatar_url (already-uploaded avatar)
              //      → render via NetworkImage
              //   3. Fall back to gradient + initials.
              Center(
                child: _AvatarEditor(
                  palette: palette,
                  imagePath: _pickedImagePath,
                  remoteUrl: (auth.user?.avatarUrl ?? '').isEmpty
                      ? null
                      : _resolveAvatarUrl(auth.user!.avatarUrl!),
                  accent: _pickedAccent ?? SocialTokens.cyan,
                  initials: _initialsFor(_name.text, email),
                  onTap: _showAvatarSheet,
                  loading: _picking,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _showAvatarSheet,
                  icon: const Icon(
                    Icons.camera_alt_outlined,
                    size: 16,
                  ),
                  label: Text(
                    'editProfile.changeAvatar'.tr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: SocialTokens.cyan,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Accent picker (used when no image is set)
              _AccentPicker(
                palette: palette,
                accents: _accentChoices,
                selected: _pickedAccent,
                disabled: _pickedImagePath != null,
                onSelect: (c) {
                  HapticUtils.lightTap();
                  setState(() => _pickedAccent = c);
                },
              ),
              const SizedBox(height: 22),
              // Name + email
              _SectionLabel(
                palette: palette,
                eyebrow: 'editProfile.accountEyebrow'.tr,
                title: 'editProfile.informationTitle'.tr,
              ),
              const SizedBox(height: 10),
              AuthField(
                controller: _name,
                label: 'editProfile.nameLabel'.tr,
                hint: 'editProfile.nameHint'.tr,
                icon: Icons.person_outline_rounded,
                accent: SocialTokens.cyan,
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 10),
              _ReadonlyEmailField(palette: palette, email: email),
              const SizedBox(height: 20),
              // Save CTA
              GradientCTA(
                label: 'editProfile.saveChanges'.tr,
                trailingIcon: Icons.check_rounded,
                enabled: _hasChanges,
                loading: _saving,
                onPressed: _save,
              ),
              const SizedBox(height: 12),
              if (_pickedImagePath != null)
                _DangerLink(
                  label: 'editProfile.removeAvatarImage'.tr,
                  onTap: () {
                    HapticUtils.lightTap();
                    setState(() => _pickedImagePath = null);
                  },
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  String _initialsFor(String name, String email) {
    final source = name.trim().isNotEmpty
        ? name
        : (email.isNotEmpty ? email.split('@').first : '?');
    final parts = source.trim().split(RegExp(r'\s+|\.'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

// ============================================================================
// Avatar editor — big circle with tap-to-edit indicator
// ============================================================================
class _AvatarEditor extends StatelessWidget {
  final SocialPalette palette;
  /// Local file path freshly picked this session. Takes priority over
  /// [remoteUrl] so the user sees their new pick instantly.
  final String? imagePath;
  /// Absolute URL of the backend-persisted avatar (users.avatar_url).
  /// Falls back to gradient + initials when both this and [imagePath]
  /// are null.
  final String? remoteUrl;
  final Color accent;
  final String initials;
  final VoidCallback onTap;
  final bool loading;

  const _AvatarEditor({
    required this.palette,
    required this.imagePath,
    required this.remoteUrl,
    required this.accent,
    required this.initials,
    required this.onTap,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    const size = 132.0;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Outer ring with brand sweep gradient
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [accent, accent.withValues(alpha: 0.4), accent],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 28,
                    spreadRadius: -4,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(3.4),
              child: ClipOval(
                child: imagePath != null
                    ? Image.file(File(imagePath!), fit: BoxFit.cover)
                    : (remoteUrl != null
                        ? Image.network(
                            remoteUrl!,
                            fit: BoxFit.cover,
                            // Quietly fall through to the gradient when
                            // the network image fails (e.g. presigned
                            // URL expired). The user can tap the camera
                            // badge and re-upload.
                            errorBuilder: (_, __, ___) =>
                                _gradientInitials(),
                          )
                        : _gradientInitials()),
              ),
            ),
            // Camera badge bottom-right
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: SocialTokens.cyan, width: 1.6),
                  boxShadow: [
                    BoxShadow(
                      color: SocialTokens.cyan.withValues(alpha: 0.4),
                      blurRadius: 14,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: SocialTokens.cyan,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.photo_camera_rounded,
                        color: SocialTokens.cyan,
                        size: 18,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gradient avatar with the user's initials in the middle — used as
  /// the placeholder when no image is set, and as the error-state for
  /// remote images that fail to load (expired presigned URL etc.).
  Widget _gradientInitials() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.92),
            accent.withValues(alpha: 0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Color(0xFF0A1628),
          fontWeight: FontWeight.w900,
          fontSize: 44,
          letterSpacing: -1,
        ),
      ),
    );
  }
}

// ============================================================================
// Avatar picker sheet — gallery / camera / clear
// ============================================================================
class _AvatarPickerSheet extends StatelessWidget {
  final SocialPalette palette;
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final VoidCallback? onClearImage;

  const _AvatarPickerSheet({
    required this.palette,
    required this.onGallery,
    required this.onCamera,
    required this.onClearImage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.textMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'editProfile.chooseAvatar'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 14),
            _row(
              palette: palette,
              icon: Icons.photo_library_outlined,
              accent: SocialTokens.cyan,
              label: 'editProfile.photoLibrary'.tr,
              onTap: onGallery,
            ),
            _divider(palette),
            _row(
              palette: palette,
              icon: Icons.photo_camera_outlined,
              accent: SocialTokens.gold,
              label: 'editProfile.takePhoto'.tr,
              onTap: onCamera,
            ),
            if (onClearImage != null) ...[
              _divider(palette),
              _row(
                palette: palette,
                icon: Icons.delete_outline_rounded,
                accent: SocialTokens.down,
                label: 'editProfile.removeCurrentImage'.tr,
                onTap: onClearImage!,
                destructive: true,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _divider(SocialPalette palette) =>
      Container(height: 1, color: palette.subtleDivider);

  Widget _row({
    required SocialPalette palette,
    required IconData icon,
    required Color accent,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: destructive ? SocialTokens.down : palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              DirectionalIcon(
                Icons.chevron_right_rounded,
                size: 18,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Accent color picker
// ============================================================================
class _AccentPicker extends StatelessWidget {
  final SocialPalette palette;
  final List<Color> accents;
  final Color? selected;
  final bool disabled;
  final ValueChanged<Color> onSelect;

  const _AccentPicker({
    required this.palette,
    required this.accents,
    required this.selected,
    required this.disabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.palette_outlined,
                size: 14,
                color: palette.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                'editProfile.avatarColor'.tr.toUpperCase(),
                style: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                ),
              ),
              if (disabled) ...[
                const Spacer(),
                Text(
                  'editProfile.usingImage'.tr,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Opacity(
            opacity: disabled ? 0.45 : 1,
            child: IgnorePointer(
              ignoring: disabled,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: accents.map((c) {
                  final isSelected = selected == c;
                  return GestureDetector(
                    onTap: () => onSelect(c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [c, c.withValues(alpha: 0.55)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: isSelected
                              ? Colors.white
                              : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: c.withValues(alpha: 0.55),
                                  blurRadius: 14,
                                  spreadRadius: -2,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              color: Color(0xFF0A1628),
                              size: 18,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Read-only email field (just visual — can't be edited in test mode)
// ============================================================================
class _ReadonlyEmailField extends StatelessWidget {
  final SocialPalette palette;
  final String email;
  const _ReadonlyEmailField({required this.palette, required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SocialTokens.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.alternate_email_rounded,
              color: SocialTokens.gold,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'editProfile.emailLabel'.tr,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email.isEmpty ? '—' : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: palette.textMuted,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Section header
// ============================================================================
class _SectionLabel extends StatelessWidget {
  final SocialPalette palette;
  final String eyebrow;
  final String title;
  const _SectionLabel({
    required this.palette,
    required this.eyebrow,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: SocialTokens.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Inline destructive text link (used for "Remove image")
// ============================================================================
class _DangerLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DangerLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.delete_outline_rounded, size: 16),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        style: TextButton.styleFrom(
          foregroundColor: SocialTokens.down,
        ),
      ),
    );
  }
}
