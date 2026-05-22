import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/expert_post.dart';
import '../../services/community_messages_service.dart';
import '../../services/community_service.dart';
import '../../services/expert_post_service.dart';
import '../../services/upload_service.dart';
import '../../utils/haptic_utils.dart';
import '../social/social_tokens.dart';

/// Expert-only "share this index chart" flow.
///
/// Opens a sheet that renders a branded chart card for a chosen period
/// (7 / 30 / 90 days), then lets the expert publish it — as an image-cover
/// article — to their own profile or to one of their communities.
///
/// The card is captured straight off the widget tree via a RepaintBoundary
/// → PNG → uploaded to /me/uploads/image → used as the post's coverUrl.
Future<void> showShareIndexChartSheet(
  BuildContext context, {
  required String name,
  required String symbol,
  required double value,
  required double changePercent,
  required List<double> sparkline,
  required Color color,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareSheet(
      name: name,
      symbol: symbol,
      value: value,
      changePercent: changePercent,
      sparkline: sparkline,
      color: color,
    ),
  );
}

enum _Dest { profile, community }

class _ShareSheet extends StatefulWidget {
  final String name;
  final String symbol;
  final double value;
  final double changePercent;
  final List<double> sparkline;
  final Color color;

  const _ShareSheet({
    required this.name,
    required this.symbol,
    required this.value,
    required this.changePercent,
    required this.sparkline,
    required this.color,
  });

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  final TextEditingController _caption = TextEditingController();

  int _days = 7; // 7 | 30 | 90
  _Dest _dest = _Dest.profile;
  bool _chatMode = false; // community sub-choice: false = post (article), true = chat
  bool _sharing = false;
  String? _error;

  List<Map<String, dynamic>> _communities = [];
  String? _communityId;

  @override
  void initState() {
    super.initState();
    _loadCommunities();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _loadCommunities() async {
    final expertId = Get.find<AuthController>().user?.expertId;
    if (expertId == null || expertId.isEmpty) return;
    final res = await CommunityService.listCommunitiesForExpert(expertId);
    if (!mounted) return;
    setState(() {
      _communities = res.rows ?? [];
      if (_communities.isNotEmpty) {
        _communityId = _communities.first['id']?.toString();
      }
    });
  }

  // Period-sliced data (sparkline is daily, so N days ≈ last N points).
  List<double> get _data {
    final f = widget.sparkline;
    if (f.length <= _days) return f;
    return f.sublist(f.length - _days);
  }

  String _periodLabel() {
    switch (_days) {
      case 30:
        return 'shareChart.last30Days'.tr;
      case 90:
        return 'shareChart.last90Days'.tr;
      default:
        return 'shareChart.last7Days'.tr;
    }
  }

  Future<File?> _captureCard() async {
    try {
      // Grab the render boundary BEFORE awaiting (a RenderObject, not a
      // BuildContext, so it's safe to keep across the async gap).
      final ctx = _cardKey.currentContext;
      if (ctx == null) return null;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      // Make sure the current frame is fully painted before snapshotting,
      // so the chart/labels are guaranteed to be in the captured image.
      await WidgetsBinding.instance.endOfFrame;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/index_chart_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    if (_dest == _Dest.community &&
        (_communityId == null || _communityId!.isEmpty)) {
      setState(() => _error = 'shareChart.pickCommunityFirst'.tr);
      return;
    }
    // Snapshot everything we need BEFORE any await. The upload can take a
    // few seconds; if the sheet is dismissed during it, this State (and its
    // controllers) get disposed — so we must not read them afterwards, and
    // the publish must still complete. Capturing locals up-front makes the
    // whole flow lifecycle-independent.
    final dest = _dest;
    final chatMode = _chatMode;
    final communityId = _communityId;
    final caption = _caption.text.trim();
    final periodLabel = _periodLabel();
    final title = '${widget.name} · $periodLabel';
    final body = caption.isNotEmpty ? caption : '${widget.name} — $periodLabel';
    final expertId = Get.find<AuthController>().user?.expertId ?? '';

    setState(() {
      _sharing = true;
      _error = null;
    });
    await HapticUtils.lightTap();

    // Capture happens while the sheet is on screen (Share was just tapped).
    final file = await _captureCard();
    if (file == null) {
      if (mounted) {
        setState(() {
          _sharing = false;
          _error = 'shareChart.renderFailed'.tr;
        });
      }
      return;
    }

    final up = await UploadService.uploadImage(file);
    if (up.url == null || up.url!.isEmpty) {
      if (mounted) {
        setState(() {
          _sharing = false;
          _error = up.error ?? 'shareChart.uploadFailed'.tr;
        });
      }
      return;
    }

    // From here it's pure HTTP — it MUST complete even if the sheet was
    // dismissed mid-upload, so we deliberately don't gate on `mounted`.
    String? err;
    if (dest == _Dest.profile) {
      final r = await ExpertPostService.create(
        expertId: expertId,
        type: PostType.article,
        visibility: PostVisibility.public,
        title: title,
        body: body,
        coverUrl: up.url,
      );
      err = r.error;
    } else if (chatMode) {
      // Send the chart as an image message into the community chat.
      final r = await CommunityMessagesService.send(
        communityId!,
        caption,
        attachmentUrl: up.url,
        attachmentType: 'image',
      );
      err = r.error;
    } else {
      final r = await ExpertPostService.createCommunityPost(
        communityId: communityId!,
        type: PostType.article,
        visibility: PostVisibility.public,
        title: title,
        body: body,
        ticker: '',
        stance: 'HOLD',
        coverUrl: up.url,
      );
      err = r.error;
    }

    if (err != null) {
      await HapticUtils.error();
      if (mounted) {
        setState(() {
          _sharing = false;
          _error = err;
        });
      } else {
        Get.snackbar(
          'shareChart.shareFailed'.tr,
          err,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 4),
        );
      }
      return;
    }

    await HapticUtils.success();
    // Context-free feedback so it shows even if the sheet already closed.
    Get.snackbar(
      'shareChart.shared'.tr,
      'shareChart.sharedBody'.tr,
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 3),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final canShare = !_sharing &&
        (_dest == _Dest.profile ||
            (_communityId != null && _communityId!.isNotEmpty));

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    const Icon(Icons.ios_share_rounded,
                        color: SocialTokens.cyan, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'shareChart.title'.tr,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  // Drag/scroll the sheet to dismiss the caption keyboard.
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    // ── Branded card (the capture target) ──
                    Center(
                      child: RepaintBoundary(
                        key: _cardKey,
                        child: _ShareCard(
                          name: widget.name,
                          symbol: widget.symbol,
                          value: widget.value,
                          changePercent: widget.changePercent,
                          data: _data,
                          accent: widget.color,
                          periodLabel: _periodLabel(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── Period selector ──
                    _Label(text: 'shareChart.period'.tr, palette: palette),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _periodChip(7, 'shareChart.days7'.tr, palette),
                        const SizedBox(width: 8),
                        _periodChip(30, 'shareChart.days30'.tr, palette),
                        const SizedBox(width: 8),
                        _periodChip(90, 'shareChart.days90'.tr, palette),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ── Destination ──
                    _Label(text: 'shareChart.postTo'.tr, palette: palette),
                    const SizedBox(height: 8),
                    _destTile(
                      dest: _Dest.profile,
                      icon: Icons.account_circle_outlined,
                      label: 'shareChart.myProfile'.tr,
                      sub: 'shareChart.myProfileSub'.tr,
                      palette: palette,
                    ),
                    const SizedBox(height: 8),
                    _destTile(
                      dest: _Dest.community,
                      icon: Icons.groups_outlined,
                      label: 'shareChart.community'.tr,
                      sub: 'shareChart.communitySub'.tr,
                      palette: palette,
                    ),
                    if (_dest == _Dest.community) ...[
                      const SizedBox(height: 10),
                      _communityPicker(palette),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _modeChip(false, 'shareChart.post'.tr,
                              Icons.article_outlined, palette),
                          const SizedBox(width: 8),
                          _modeChip(true, 'shareChart.chat'.tr,
                              Icons.chat_bubble_outline_rounded, palette),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),

                    // ── Caption ──
                    _Label(
                        text: 'shareChart.captionOptional'.tr,
                        palette: palette),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _caption,
                      maxLength: 280,
                      maxLines: 3,
                      minLines: 1,
                      style: TextStyle(color: palette.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'shareChart.captionHint'.tr,
                        hintStyle: TextStyle(color: palette.textMuted),
                        filled: true,
                        fillColor: palette.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: SocialTokens.cyan),
                        ),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: SocialTokens.down, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: SocialTokens.down,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: canShare ? () => _share() : null,
                        icon: _sharing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Color(0xFF0A1628),
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          _sharing
                              ? 'shareChart.sharing'.tr
                              : 'shareChart.share'.tr,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SocialTokens.cyan,
                          foregroundColor: const Color(0xFF0A1628),
                          disabledBackgroundColor: palette.surfaceElevated,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _periodChip(int days, String label, SocialPalette palette) {
    final active = _days == days;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _days = days),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? SocialTokens.cyan.withValues(alpha: 0.16)
                : palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? SocialTokens.cyan : palette.border,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? SocialTokens.cyan : palette.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeChip(bool chat, String label, IconData icon, SocialPalette palette) {
    final active = _chatMode == chat;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _chatMode = chat),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? SocialTokens.cyan.withValues(alpha: 0.16) : palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? SocialTokens.cyan : palette.border,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: active ? SocialTokens.cyan : palette.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? SocialTokens.cyan : palette.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _destTile({
    required _Dest dest,
    required IconData icon,
    required String label,
    required String sub,
    required SocialPalette palette,
  }) {
    final active = _dest == dest;
    return GestureDetector(
      onTap: () => setState(() => _dest = dest),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? SocialTokens.cyan.withValues(alpha: 0.10) : palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? SocialTokens.cyan.withValues(alpha: 0.5) : palette.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (active ? SocialTokens.cyan : palette.textMuted)
                    .withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 20, color: active ? SocialTokens.cyan : palette.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  Text(sub,
                      style: TextStyle(color: palette.textMuted, fontSize: 11.5)),
                ],
              ),
            ),
            if (active)
              const Icon(Icons.check_circle_rounded,
                  color: SocialTokens.cyan, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _communityPicker(SocialPalette palette) {
    if (_communities.isEmpty) {
      return Text(
        'shareChart.notInCommunity'.tr,
        style: TextStyle(color: palette.textMuted, fontSize: 12.5),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _communityId,
          isExpanded: true,
          dropdownColor: palette.surface,
          icon: Icon(Icons.expand_more_rounded, color: palette.textSecondary),
          style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700),
          items: _communities.map((c) {
            final id = c['id']?.toString() ?? '';
            final name = c['name']?.toString() ?? id;
            return DropdownMenuItem(value: id, child: Text(name));
          }).toList(),
          onChanged: (v) => setState(() => _communityId = v),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final SocialPalette palette;
  const _Label({required this.text, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: palette.textMuted,
        fontWeight: FontWeight.w800,
        fontSize: 10.5,
        letterSpacing: 1.0,
      ),
    );
  }
}

/// The shareable card itself — a fixed-size, dark, branded panel. Rendered
/// in the sheet inside a RepaintBoundary so it can be snapshotted to PNG.
class _ShareCard extends StatelessWidget {
  final String name;
  final String symbol;
  final double value;
  final double changePercent;
  final List<double> data;
  final Color accent;
  final String periodLabel;

  const _ShareCard({
    required this.name,
    required this.symbol,
    required this.value,
    required this.changePercent,
    required this.data,
    required this.accent,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final up = changePercent >= 0;
    final changeColor =
        up ? const Color(0xFF22D3A8) : const Color(0xFFFF6B7A);
    final lineColor = accent;

    return Container(
      width: 340,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12203A), Color(0xFF0A1424)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF233149)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (symbol.isNotEmpty)
                      Text(
                        symbol,
                        style: const TextStyle(
                          color: Color(0xFF94A0B5),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmt(value),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    '${up ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: changeColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: data.length < 2
                ? Center(
                    child: Text(
                      'shareChart.noDataForPeriod'.tr,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      minX: 0,
                      maxX: (data.length - 1).toDouble(),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (int i = 0; i < data.length; i++)
                              FlSpot(i.toDouble(), data[i]),
                          ],
                          isCurved: true,
                          color: lineColor,
                          barWidth: 2.6,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                lineColor.withValues(alpha: 0.28),
                                lineColor.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                periodLabel,
                style: const TextStyle(
                  color: Color(0xFF94A0B5),
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
              const Spacer(),
              const Text(
                'UNMU',
                style: TextStyle(
                  color: SocialTokens.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000) {
      return v.toStringAsFixed(0).replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
          );
    }
    return v.toStringAsFixed(2);
  }
}
