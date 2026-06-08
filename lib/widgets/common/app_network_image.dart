import 'package:flutter/material.dart';

/// A network image with a polished load, used in place of bare
/// [Image.network] for covers, thumbnails and avatars.
///
/// Why this exists: plain `Image.network` shows nothing while bytes stream in
/// and then pops the picture on screen abruptly — and on a source swap it
/// flashes to blank. That's the "bad" cover loading. This widget instead:
///   * shows a soft **shimmer placeholder** while loading,
///   * **fades the image in** once it's decoded (no pop),
///   * uses **gaplessPlayback** so swapping the URL never flashes blank,
///   * falls back to a tidy icon on error.
///
/// Caching: Flutter's in-memory [ImageCache] already keeps decoded frames for
/// the session, so a cover scrolled back into view is instant and isn't
/// re-fetched. (Cross-launch disk caching would need the cached_network_image
/// package — a separate, optional upgrade.)
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.placeholderColor,
    this.errorWidget,
    this.fadeDuration = const Duration(milliseconds: 280),
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  /// Base colour of the placeholder/shimmer. Defaults to a theme-aware grey.
  final Color? placeholderColor;

  /// Shown when the image fails to load. Defaults to a broken-image icon on
  /// the placeholder colour.
  final Widget? errorWidget;
  final Duration fadeDuration;

  @override
  Widget build(BuildContext context) {
    Widget image = Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      // Keep the previous frame on a URL swap instead of flashing to blank.
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child; // already cached → no fade
        return AnimatedOpacity(
          opacity: frame == null ? 0.0 : 1.0,
          duration: fadeDuration,
          curve: Curves.easeOut,
          child: child,
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child; // done
        return _Shimmer(base: _baseColor(context), width: width, height: height);
      },
      errorBuilder: (context, _, __) =>
          errorWidget ?? _errorBox(context),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Color _baseColor(BuildContext context) =>
      placeholderColor ??
      (Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1B2330)
          : const Color(0xFFE7ECF3));

  Widget _errorBox(BuildContext context) {
    final base = _baseColor(context);
    final fg = base.computeLuminance() > 0.5 ? Colors.black26 : Colors.white30;
    Widget box = Container(
      width: width,
      height: height,
      color: base,
      alignment: Alignment.center,
      child: Icon(Icons.image_not_supported_rounded, color: fg, size: 26),
    );
    if (borderRadius != null) {
      box = ClipRRect(borderRadius: borderRadius!, child: box);
    }
    return box;
  }
}

/// Lightweight shimmer placeholder — a highlight band sweeping across a base
/// colour. Pure Flutter (no package); one cheap [AnimationController] that
/// only runs while this placeholder is on screen (disposed with the widget).
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.base, this.width, this.height});
  final Color base;
  final double? width;
  final double? height;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlight = widget.base.computeLuminance() > 0.5
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.07);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Sweep the gradient's window from left (-) to right (+) of the frame.
        final dx = _c.value * 3.0 - 1.5;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(dx - 1.0, 0),
              end: Alignment(dx + 1.0, 0),
              colors: [widget.base, highlight, widget.base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
          child: SizedBox(width: widget.width, height: widget.height),
        );
      },
    );
  }
}
