// May 2026 brand refresh: dropped the dark trading-themed background +
// candlestick/particle/ticker layers. Some animation fields and the
// legacy painter classes are kept (commented as such) in case we want
// to bring those layers back later, so we suppress the dead-code lints
// for this file as a whole rather than littering individual ignores.
// ignore_for_file: unused_field, unused_element

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:get/get.dart';

import '../social/social_tokens.dart';

/// =============================================================================
/// Splash Screen — "Live Market Pulse"
///
/// A cinematic, trading-themed splash that signals what UNMU actually is:
/// a live halal-investing platform. Built entirely in Flutter — no
/// Lottie, no Rive, no asset images. Every element is a CustomPainter
/// or animated transform driven off a single master controller.
///
/// Visual layers (back → front):
///
///   ┌──────────────────────────────────────────────┐
///   │  · · · · · · · · · ·    ← faint financial    │
///   │  · · · · · · · · · ·       grid background   │
///   │           ◜ ◝               ← radar pulse     │
///   │         ◜  U N M U  ◝         rings emanate   │
///   │      ◜  ─ shine ─  ◝          from center     │
///   │           ◟ ◞                  + 3D tilt      │
///   │   Halal markets. Verified  ← typewriter       │
///   │   experts. Live.              tagline         │
///   │                                                │
///   │   $0.24·+1.2%·✓ ← floating data particles     │
///   │   ▍▌▍▍▎▌▍▎▎▍▌▍▎ ← animated candlestick chart  │
///   │   ┃$AAPL·✓·┃$TSLA·⚠·┃$ARAMCO·✓·┃ ← ticker tape │
///   └──────────────────────────────────────────────┘
///
/// Choreography (~1600ms total — _entry.duration):
///
///    0–200ms : background gradient + grid fade in
///   200–700ms: candlestick chart draws itself left → right (one
///              candle per ~30ms, with a tiny bounce on each)
///   400–1600ms: 12 floating particles drift upward (staggered)
///   600–1600ms: 3 pulse rings emanate from the wordmark (looping)
///   650–1100ms: UNMU wordmark scales in 0.6 → 1.0 with a subtle 3D
///               Y-axis tilt + a cyan→white→cyan shine sweep
///  1050–1500ms: tagline types itself one character at a time
///  1300–1600ms: bottom ticker strip slides in from below
///
/// Brand-locked dark palette regardless of system theme — splash should
/// always feel "first impression of a serious financial app".
/// =============================================================================
class SplashScreen extends StatefulWidget {
  final Duration minDuration;
  const SplashScreen({
    super.key,
    this.minDuration = const Duration(milliseconds: 3200),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Single master controller drives the entrance choreography. Every
  // sub-animation is a CurvedAnimation derived from this so they all
  // stay phase-locked.
  late final AnimationController _entry;
  // Separate looping controller for the pulse rings + particle drift —
  // they keep moving after the entrance finishes, which makes the
  // splash feel alive instead of "frozen waiting for auth check".
  late final AnimationController _loop;

  // Derived per-element animations.
  late final Animation<double> _bgOpacity;
  late final Animation<double> _chartProgress; // 0..1 left→right draw
  late final Animation<double> _wordScale; // 0.6..1.0
  late final Animation<double> _wordOpacity;
  late final Animation<double> _wordTilt; // -0.10..0.0 rad on Y axis
  late final Animation<double> _shineProgress; // 0..1 sweeps across
  late final Animation<double> _taglineProgress; // 0..1 typewriter
  late final Animation<double> _tickerSlide; // 1..0 (offscreen → in)

  @override
  void initState() {
    super.initState();
    // 3.2s entrance — gives every layer breathing room: candlesticks
    // visibly draw, the shine sweep is readable, and the typewriter
    // tagline doesn't feel like a frame flash. Sub-animations reference
    // fractional intervals of this controller, so they all re-time
    // automatically when this duration changes.
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();

    // 3.6s loop for the pulse rings + drifting particles. Independent
    // from [_entry] so the looping ambient motion keeps going at its
    // own pace whether the splash is mid-entrance or holding for auth.
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    // Each derived animation owns a slice of [0..1] of the master clock.
    _bgOpacity = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.0, 0.15, curve: Curves.easeOut),
    );
    _chartProgress = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.12, 0.55, curve: Curves.easeOutCubic),
    );
    _wordScale = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.40, 0.75, curve: Curves.easeOutBack),
      ),
    );
    _wordOpacity = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.40, 0.65, curve: Curves.easeOut),
    );
    // Tilt anim runs slightly past the scale-in so the wordmark settles
    // into a flat-on pose at the end. Starting with a subtle Y-rotation
    // and easing to 0 reads as "the logo just landed".
    _wordTilt = Tween<double>(begin: -0.18, end: 0.0).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.40, 0.85, curve: Curves.easeOutCubic),
      ),
    );
    _shineProgress = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.55, 0.90, curve: Curves.easeOut),
    );
    _taglineProgress = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.66, 0.94, curve: Curves.easeOut),
    );
    _tickerSlide = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.81, 1.0, curve: Curves.easeOutCubic),
    );

  }

  @override
  void dispose() {
    _entry.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Clean white base — the brand wordmark has BLACK text ("unmu") that
      // got lost on the previous dark trading-themed background. White lets
      // the teal arch and the black letters both read perfectly.
      backgroundColor: const Color(0xFFFFFFFF),
      body: AnimatedBuilder(
        animation: Listenable.merge([_entry, _loop]),
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // ── Background: soft radial halo in pale cyan ──────
              // Very light tint at the center so the white doesn't feel
              // sterile, fading to pure white at the edges. Picks up the
              // teal in the logo without competing with it.
              const _GradientBackground(),

              // ── Pulse rings (teal, very low opacity) ───────────
              // Single tasteful accent — replaces the previous busy
              // grid + candlesticks + particles which were fighting
              // the minimal logo.
              if (_wordOpacity.value > 0.01)
                Center(
                  child: SizedBox(
                    width: 380,
                    height: 380,
                    child: CustomPaint(
                      painter: _PulseRingPainter(
                        loopT: _loop.value,
                        opacity: _wordOpacity.value,
                      ),
                    ),
                  ),
                ),

              // ── Centre wordmark with 3D tilt + shine ───────────
              Center(
                child: Transform(
                  alignment: Alignment.center,
                  // Perspective + Y-rotation. setEntry(3,2,0.001) is
                  // the canonical "give me real perspective" matrix
                  // tweak in Flutter — without it the rotation is
                  // an orthographic shear, not a 3D tilt.
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(_wordTilt.value)
                    ..scale(_wordScale.value),
                  child: Opacity(
                    opacity: _wordOpacity.value,
                    child: _Wordmark(shineProgress: _shineProgress.value),
                  ),
                ),
              ),

              // ── Tagline (typewriter) ───────────────────────────
              // Kept but recolored for the light background — see
              // _TypewriterTagline.
              Positioned(
                left: 32,
                right: 32,
                top: MediaQuery.of(context).size.height * 0.5 + 70,
                child: _TypewriterTagline(
                  progress: _taglineProgress.value,
                ),
              ),

              // NOTE: previously this screen also rendered an animated
              // candlestick chart, floating data particles, a financial
              // grid lattice, a ticker tape and top status dots — every
              // one of those was designed for the old dark trading
              // theme and looked busy under the new clean logo. We've
              // removed them in favour of the minimal layout above.
              // The painter classes (kept further down in this file)
              // are still referenced for backward compat in case we
              // want to bring any element back later.
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// Layer 1 — gradient background. Soft pale-cyan glow at center (under the
// wordmark) fading to clean white at the edges. Picks up the teal in the
// logo arch without being aggressive — the wordmark stays the hero.
// ============================================================================
class _GradientBackground extends StatelessWidget {
  const _GradientBackground();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [
            Color(0xFFE6F8FB), // very pale cyan halo at center
            Color(0xFFF4FAFC), // soft near-white
            Color(0xFFFFFFFF), // pure white at edges
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

// ============================================================================
// Layer 3 — pulse rings. Three concentric circles emanate outward and
// fade out, looping forever off [_loop]. Effect: "the logo is broadcasting".
// ============================================================================
class _PulseRingPainter extends CustomPainter {
  final double loopT; // 0..1 from the looping controller
  final double opacity;
  _PulseRingPainter({required this.loopT, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide / 2;
    // Three offset waves so the rings overlap rhythmically.
    for (int i = 0; i < 3; i++) {
      final t = (loopT + i / 3) % 1.0;
      final r = maxRadius * t;
      // Fade out as the ring expands — quadratic feels more "radio
      // wave" than linear. Slightly stronger now that the splash bg is
      // white (cyan strokes need more weight on light surfaces to read).
      final ringOpacity = (1.0 - t) * (1.0 - t) * 0.55 * opacity;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = SocialTokens.cyan.withValues(alpha: ringOpacity);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter old) =>
      old.loopT != loopT || old.opacity != opacity;
}

// ============================================================================
// LEGACY — _Particle / _ParticlesPainter / _Candle / _CandlestickPainter
// powered the floating data labels + bottom candlestick chart in the old
// dark trading-themed splash. They were dropped from the May 2026 brand
// refresh in favour of the new minimal white-background layout. Kept
// here in case we ever want to bring the trading-vibe back; otherwise
// they're safe to delete in a future cleanup.
// ============================================================================
class _Particle {
  final double x; // 0..1 horizontal position
  final double phase; // 0..1 offset into the loop cycle
  final double speed; // 0.5..1.4 lifespan multiplier
  final String label;
  final Color color;
  _Particle({
    required this.x,
    required this.phase,
    required this.speed,
    required this.label,
    required this.color,
  });

  static _Particle seed(math.Random rng, int i) {
    const labels = [
      r'+0.24%',
      r'$1.18',
      r'✓ Halal',
      r'+1.6%',
      r'−0.42%',
      r'$AAPL',
      r'$ARAMCO',
      r'✓',
      r'+12%',
      r'1m',
    ];
    final label = labels[i % labels.length];
    final isUp = label.startsWith('+') ||
        label.startsWith(r'✓') ||
        label.startsWith(r'$');
    return _Particle(
      x: rng.nextDouble(),
      phase: rng.nextDouble(),
      speed: 0.5 + rng.nextDouble() * 0.9,
      label: label,
      color: isUp
          ? const Color(0xFF22D3A8) // bullish green
          : const Color(0xFFFF6B7A), // bearish red
    );
  }
}

class _ParticlesPainter extends CustomPainter {
  final List<_Particle> particles;
  final double loopT;
  final double fade;
  _ParticlesPainter({
    required this.particles,
    required this.loopT,
    required this.fade,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = ((loopT * p.speed) + p.phase) % 1.0;
      // y goes from 1.0 (bottom) → 0.0 (top) as t advances.
      final y = (1.0 - t) * size.height;
      // Triangle fade so it's invisible at the start + end.
      final particleAlpha = math.sin(t * math.pi) * 0.7 * fade;
      if (particleAlpha <= 0.02) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: p.label,
          style: TextStyle(
            color: p.color.withValues(alpha: particleAlpha),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.x * size.width - tp.width / 2, y));
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter old) =>
      old.loopT != loopT || old.fade != fade;
}

// ============================================================================
// Layer 5 — animated candlestick chart. Bars draw left → right driven
// off [progress]. Each candle is a body (open→close rectangle) + a wick
// (high→low line). Bullish candles are green, bearish red.
// ============================================================================
class _Candle {
  final double open; // 0..1
  final double close; // 0..1
  final double high; // 0..1
  final double low; // 0..1
  bool get isBull => close >= open;
  _Candle({
    required this.open,
    required this.close,
    required this.high,
    required this.low,
  });

  static _Candle seed(math.Random rng, int i) {
    // Build a random-walk-ish sequence so consecutive candles look
    // related — pure rng would produce stripes, not a chart.
    final mid = 0.5 + math.sin(i * 0.5) * 0.18 + (rng.nextDouble() - 0.5) * 0.12;
    final spread = 0.04 + rng.nextDouble() * 0.10;
    final open = (mid - spread / 2).clamp(0.05, 0.95);
    final close = (mid + spread / 2).clamp(0.05, 0.95) +
        (rng.nextDouble() - 0.5) * 0.06;
    final high = math.max(open, close) + rng.nextDouble() * 0.06;
    final low = math.min(open, close) - rng.nextDouble() * 0.06;
    return _Candle(
      open: open,
      close: close.clamp(0.05, 0.95),
      high: high.clamp(0.05, 0.98),
      low: low.clamp(0.02, 0.95),
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  final List<_Candle> candles;
  final double progress; // 0..1 — fraction of candles drawn

  _CandlestickPainter({required this.candles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final n = candles.length;
    final candleW = size.width / n;
    final bodyW = candleW * 0.55;
    // How many candles to fully draw + partial of the next one.
    final shownF = progress * n;
    final fullCount = shownF.floor();
    final partial = shownF - fullCount;

    for (int i = 0; i < n; i++) {
      // Each candle's individual reveal so they pop in sequence.
      double localT;
      if (i < fullCount) {
        localT = 1.0;
      } else if (i == fullCount) {
        localT = partial.clamp(0.0, 1.0);
      } else {
        localT = 0.0;
      }
      if (localT <= 0.001) continue;

      final c = candles[i];
      final cx = candleW * i + candleW / 2;
      final yOpen = (1.0 - c.open) * size.height;
      final yClose = (1.0 - c.close) * size.height;
      final yHigh = (1.0 - c.high) * size.height;
      final yLow = (1.0 - c.low) * size.height;
      final color = c.isBull
          ? const Color(0xFF22D3A8)
          : const Color(0xFFFF6B7A);

      // Wick (vertical line). Reveal expands from middle outward.
      final wickPaint = Paint()
        ..color = color.withValues(alpha: 0.85 * localT)
        ..strokeWidth = 1.4;
      final yMid = (yHigh + yLow) / 2;
      final yLowDrawn = yMid + (yLow - yMid) * localT;
      final yHighDrawn = yMid + (yHigh - yMid) * localT;
      canvas.drawLine(
        Offset(cx, yHighDrawn),
        Offset(cx, yLowDrawn),
        wickPaint,
      );

      // Body (rectangle). Same middle-out reveal so wick + body grow
      // together — feels like the candle is "forming live".
      final yBodyTop = math.min(yOpen, yClose);
      final yBodyBottom = math.max(yOpen, yClose);
      final yBodyMid = (yBodyTop + yBodyBottom) / 2;
      final bodyTopDrawn = yBodyMid + (yBodyTop - yBodyMid) * localT;
      final bodyBottomDrawn = yBodyMid + (yBodyBottom - yBodyMid) * localT;
      final bodyRect = Rect.fromLTRB(
        cx - bodyW / 2,
        bodyTopDrawn,
        cx + bodyW / 2,
        bodyBottomDrawn,
      );
      final bodyPaint = Paint()
        ..color = color.withValues(alpha: (c.isBull ? 0.95 : 0.85) * localT);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bodyRect, const Radius.circular(1.5)),
        bodyPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter old) =>
      old.progress != progress;
}

// ============================================================================
// Layer 6 — centre wordmark. Previously this was a stylised text "UNMU"
// with a metal-finish gradient + animated shine sweep. Now that we have
// real brand artwork (`assets/branding/unmu_wordmark.png` — the
// horizontal teal wordmark + arch), we render the actual image instead.
// The 3D tilt + scale animations are still applied by the parent
// Transform, so the entrance still feels cinematic — just over the real
// logo instead of fake text.
//
// The `shineProgress` parameter is kept on the constructor so the parent
// AnimatedBuilder code path doesn't have to change. We use it to drive a
// subtle bright sweep across the PNG via a `ClipPath` + white overlay
// (BlendMode.plus), which keeps the metallic feel on the new artwork.
// ============================================================================
class _Wordmark extends StatelessWidget {
  final double shineProgress; // 0..1
  const _Wordmark({required this.shineProgress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Real wordmark artwork.
          Image.asset(
            'assets/branding/unmu_wordmark.png',
            width: 280,
            fit: BoxFit.contain,
            // If the asset is missing for any reason, fall back to a
            // small bit of text so the splash isn't a black hole.
            errorBuilder: (_, __, ___) => const Text(
              'UNMU',
              style: TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
          ),
          // Shine sweep — re-rendered on top, clipped to a narrow band
          // that travels left → right once. Uses BlendMode.plus so the
          // teal glyphs flash brighter where the band overlaps rather
          // than being blanketed in white.
          if (shineProgress > 0.0 && shineProgress < 1.0)
            ClipPath(
              clipper: _ShineClipper(progress: shineProgress),
              child: Image.asset(
                'assets/branding/unmu_wordmark.png',
                width: 280,
                fit: BoxFit.contain,
                color: Colors.white.withValues(alpha: 0.55),
                colorBlendMode: BlendMode.plus,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          // Subtle outer glow halo so the wordmark sits on the dark
          // background like it's lit from behind.
          IgnorePointer(
            child: Container(
              width: 360,
              height: 150,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    SocialTokens.cyan.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShineClipper extends CustomClipper<Path> {
  final double progress; // 0..1
  _ShineClipper({required this.progress});
  @override
  Path getClip(Size size) {
    // Diagonal shine band. Width is ~1/4 of the wordmark width; the
    // band's centre travels from -0.25..1.25 so it fully enters and
    // exits the glyph bounds.
    final bandW = size.width * 0.25;
    final cx = size.width * (-0.25 + 1.5 * progress);
    final path = Path()
      ..moveTo(cx - bandW / 2 - size.height * 0.3, 0)
      ..lineTo(cx + bandW / 2 - size.height * 0.3, 0)
      ..lineTo(cx + bandW / 2 + size.height * 0.3, size.height)
      ..lineTo(cx - bandW / 2 + size.height * 0.3, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _ShineClipper old) => old.progress != progress;
}

// ============================================================================
// Layer 7 — typewriter tagline. Reveals one character at a time off
// [progress], with a blinking caret while typing.
// ============================================================================
class _TypewriterTagline extends StatelessWidget {
  final double progress; // 0..1
  const _TypewriterTagline({required this.progress});

  @override
  Widget build(BuildContext context) {
    // Localized tagline — Arabic mode shows the Arabic line, no English.
    final full = 'splash.tagline'.tr;
    final cutoff = (progress * full.length).round().clamp(0, full.length);
    final shown = full.substring(0, cutoff);
    final showCaret = progress > 0.0 && progress < 1.0;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              shown,
              textAlign: TextAlign.center,
              style: const TextStyle(
                // Dark slate — readable on the new white splash bg.
                color: Color(0xFF425063),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                height: 1.4,
              ),
            ),
          ),
          if (showCaret)
            Container(
              width: 2,
              height: 14,
              margin: const EdgeInsets.only(left: 2),
              color: SocialTokens.cyan,
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Layer 8 — bottom ticker tape. Static (not scrolling) since the splash
// only lasts ~1.6s — animating it would just be visual noise. Looks
// like a Bloomberg footer strip with pipe separators.
// ============================================================================
class _TickerTape extends StatelessWidget {
  const _TickerTape();
  static const _items = [
    (r'$AAPL', '+0.24%', true),
    (r'$ARAMCO', '+1.12%', true),
    (r'$TSLA', '−0.84%', false),
    (r'$NVDA', '+2.31%', true),
    (r'$DXY', '104.3', true),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < _items.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                Text(
                  _items[i].$1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _items[i].$2,
                  style: TextStyle(
                    color: _items[i].$3
                        ? const Color(0xFF22D3A8)
                        : const Color(0xFFFF6B7A),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Top status dots — tiny detail that signals "system online".
// Lit dots cycle subtly via the pulse loop so they feel "alive".
// ============================================================================
class _StatusDots extends StatelessWidget {
  const _StatusDots();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Top-left: brand mark in micro
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Text(
            'UNMU · ${'splash.live'.tr}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.2,
            ),
          ),
        ),
        // Top-right: 3 dot indicator
        Padding(
          padding: const EdgeInsets.only(right: 22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < 3; i++) ...[
                Container(
                  width: 6,
                  height: 6,
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == 2
                        ? const Color(0xFF22D3A8) // last dot = green = "live"
                        : Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
