import 'package:flutter/material.dart';

import '../../screens/social/social_tokens.dart';

/// =============================================================================
/// Shared auth screen primitives — used by Login + Register.
/// =============================================================================

/// Brand mark — a small version of the splash screen's "H" logo. Used at the
/// top of auth screens to anchor the brand.
class AuthBrandMark extends StatelessWidget {
  final double size;
  const AuthBrandMark({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    // Renders the real UNMU app-icon artwork from `assets/branding/`. We
    // keep the soft cyan glow shadow so the icon still feels lit on dark
    // backgrounds, and clip to a rounded square for visual continuity
    // with the launcher icon on the user's home screen.
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow.
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: SocialTokens.cyan.withValues(alpha: 0.32),
                  blurRadius: 22,
                  spreadRadius: -4,
                ),
              ],
            ),
          ),
          // Brand icon — rounded square so it matches the home-screen
          // launcher silhouette on iOS / Android.
          ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.22),
            child: Container(
              width: size,
              height: size,
              color: Colors.white,
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.all(size * 0.08),
                child: Image.asset(
                  'assets/branding/unmu_icon.png',
                  fit: BoxFit.contain,
                  // Defensive fallback so login screens still render
                  // SOMETHING if the asset goes missing post-build.
                  errorBuilder: (_, __, ___) => Text(
                    'U',
                    style: TextStyle(
                      color: SocialTokens.cyan,
                      fontSize: size * 0.50,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A premium auth input field with a colored icon tile, floating label,
/// cyan focus glow, and optional show/hide toggle for passwords.
class AuthField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color accent;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.accent = SocialTokens.cyan,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  late final FocusNode _focus;
  bool _isObscured = true;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(() {
      if (_focus.hasFocus != _isFocused) {
        setState(() => _isFocused = _focus.hasFocus);
      }
    });
    _isObscured = widget.obscureText;
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isFocused ? widget.accent : palette.border,
          width: _isFocused ? 1.4 : 1,
        ),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.20),
                  blurRadius: 20,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Icon tile
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.accent.withValues(alpha: _isFocused ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, color: widget.accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label.toUpperCase(),
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  obscureText: widget.obscureText && _isObscured,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  onSubmitted: widget.onSubmitted,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: TextStyle(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ],
            ),
          ),
          if (widget.obscureText)
            IconButton(
              onPressed: () => setState(() => _isObscured = !_isObscured),
              icon: Icon(
                _isObscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: palette.textMuted,
                size: 18,
              ),
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

/// Big primary CTA — cyan gradient with glow when enabled, faded when not.
class GradientCTA extends StatelessWidget {
  final String label;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool loading;

  const GradientCTA({
    super.key,
    required this.label,
    this.trailingIcon,
    this.onPressed,
    this.enabled = true,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final isInteractive = enabled && !loading;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isInteractive
            ? [
                BoxShadow(
                  color: SocialTokens.cyan.withValues(alpha: 0.45),
                  blurRadius: 20,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isInteractive ? onPressed : null,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: isInteractive
                  ? const LinearGradient(
                      colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isInteractive ? null : palette.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isInteractive
                    ? Colors.transparent
                    : palette.border,
              ),
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Color(0xFF0A1628),
                      strokeWidth: 2.4,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isInteractive
                              ? const Color(0xFF0A1628)
                              : palette.textMuted,
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (trailingIcon != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          trailingIcon,
                          color: isInteractive
                              ? const Color(0xFF0A1628)
                              : palette.textMuted,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Inline social-login button placeholder (Apple, Google, Email link).
class SocialAuthButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  final VoidCallback? onPressed;

  const SocialAuthButton({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: iconColor ?? palette.textPrimary, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "or continue with" divider used between primary CTA and social buttons.
class OrDivider extends StatelessWidget {
  final String label;
  const OrDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: palette.subtleDivider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: palette.textMuted,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: palette.subtleDivider)),
      ],
    );
  }
}

/// Inline error pill — replaces the boring red Text from before.
class AuthErrorBanner extends StatelessWidget {
  final String message;
  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: SocialTokens.down.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SocialTokens.down.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: SocialTokens.down,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: SocialTokens.down,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
