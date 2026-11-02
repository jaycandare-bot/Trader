import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'delta_ict_service.dart';

/// Reusable Delta Exchange / TradingView-Grade Interactive Zoomable & Pannable Chart Widget
/// Features a Collision-Free Smart Label Engine & TOLAG CRT Hybrid Fusion HUD
class DeltaProInteractiveChart extends StatefulWidget {
  final IctSignal signal;
  final double height;
  final bool isFullScreen;
  final VoidCallback? onOpenFullScreen;

  const DeltaProInteractiveChart({
    super.key,
    required this.signal,
    this.height = 420,
    this.isFullScreen = false,
    this.onOpenFullScreen,
  });

  @override
  State<DeltaProInteractiveChart> createState() => _DeltaProInteractiveChartState();
}

class _DeltaProInteractiveChartState extends State<DeltaProInteractiveChart> {
  double _visibleCandles = 34.0;
  double _baseVisibleCandles = 34.0;
  double _scrollBackBars = 0.0;
  double _verticalZoom = 1.0;
  bool _fitToTargets = false;
  bool _crosshairMode = false;
  bool _showCrtHud = true;
  Offset? _crosshairPos;

  // Layer View Modes: 'ALL', 'CLEAN', 'ICT', 'PATTERNS', 'ORDERFLOW'
  String _viewMode = 'ALL';

  void _zoomIn() {
    setState(() {
      _visibleCandles = (_visibleCandles * 0.78).clamp(12.0, 95.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _visibleCandles = (_visibleCandles * 1.28).clamp(12.0, 95.0);
    });
  }

  void _panLeft() {
    setState(() {
      final maxBack = max(0.0, widget.signal.candles.length - _visibleCandles);
      _scrollBackBars = (_scrollBackBars + (_visibleCandles * 0.25)).clamp(0.0, maxBack);
    });
  }

  void _panRight() {
    setState(() {
      _scrollBackBars = (_scrollBackBars - (_visibleCandles * 0.25)).clamp(0.0, 100.0);
    });
  }

  void _resetChart() {
    setState(() {
      _visibleCandles = 34.0;
      _scrollBackBars = 0.0;
      _verticalZoom = 1.0;
      _crosshairPos = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sig = widget.signal;
    final candles = sig.candles;
    final dec = sig.markPrice < 1 ? 5 : (sig.markPrice < 100 ? 3 : 1);
    final isLong = sig.direction == 'LONG';

    Candle inspected = candles.isNotEmpty
        ? candles.last
        : Candle(open: sig.markPrice, high: sig.markPrice, low: sig.markPrice, close: sig.markPrice, volume: 0, timestamp: 0);

    final int total = candles.length;
    final int visCount = _visibleCandles.round().clamp(10, max(10, total));
    final int endIdx = (total - _scrollBackBars.round()).clamp(visCount, total);
    final int startIdx = max(0, endIdx - visCount);

    if (_crosshairPos != null && total > 0) {
      final double approxChartW = MediaQuery.of(context).size.width - 96;
      final double relX = (_crosshairPos!.dx / max(approxChartW, 1.0)).clamp(0.0, 1.0);
      final int idx = (startIdx + (relX * visCount).floor()).clamp(0, total - 1);
      inspected = candles[idx];
    }

    final double chgPct = inspected.open > 0 ? ((inspected.close - inspected.open) / inspected.open) * 100.0 : 0.0;
    final bool isBullBar = inspected.close >= inspected.open;

    return Container(
      height: widget.isFullScreen ? null : widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E2636), width: 1.2),
      ),
      child: Column(
        children: [
          // 1. Clean Aligned Header: Session + Signal Time + OHLCV + Layer Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF111622),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row A: Killzone + Signal Timestamp
                Builder(
                  builder: (ctx) {
                    final sess = DeltaExchangeIctService.getLiveSessionTelemetry();
                    final sessColor = sess.activeSessionColorHex == 'GREEN'
                        ? const Color(0xFF00E676)
                        : (sess.activeSessionColorHex == 'AMBER' ? Colors.amberAccent : Colors.cyanAccent);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: sessColor.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: sessColor.withOpacity(0.6)),
                              ),
                              child: Text(
                                '${sess.killzoneBadge} • ${sess.sessionName}',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: sessColor),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.amberAccent.withOpacity(0.45)),
                              ),
                              child: Text(
                                '🕒 ${sig.launchedAgo}',
                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // Row B: Aligned Strategy & Pattern Strip (Never covers candles!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _strategyChip(
                          'CRT HYBRID: ${isLong ? 'ACTIVE LONG' : 'ACTIVE SHORT'} (${sig.confluenceScore}/100)',
                          isLong ? const Color(0xFF00E676) : const Color(0xFFFF3D57),
                        ),
                        const SizedBox(width: 5),
                        _strategyChip('📐 ${sig.patternAnalysis.formedPattern}', Colors.cyanAccent),
                        const SizedBox(width: 5),
                        _strategyChip('PO3: ${sig.strategyExtras.po3Phase}', Colors.amberAccent),
                        const SizedBox(width: 5),
                        _strategyChip('OTE: \$${sig.otePrice.toStringAsFixed(dec)}', Colors.purpleAccent),
                        const SizedBox(width: 5),
                        _strategyChip('EQ 50%: \$${sig.equilibrium.toStringAsFixed(dec)}', Colors.white70),
                      ],
                    ),
                  ),
                ),
                // Row C: Live OHLCV Bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text('O ${inspected.open.toStringAsFixed(dec)}  ', style: const TextStyle(fontSize: 10, color: Colors.white70, fontFamily: 'monospace')),
                      Text('H ${inspected.high.toStringAsFixed(dec)}  ', style: const TextStyle(fontSize: 10, color: Color(0xFF00E676), fontFamily: 'monospace')),
                      Text('L ${inspected.low.toStringAsFixed(dec)}  ', style: const TextStyle(fontSize: 10, color: Color(0xFFFF5252), fontFamily: 'monospace')),
                      Text(
                        'C ${inspected.close.toStringAsFixed(dec)}  ',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isBullBar ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        '(${chgPct >= 0 ? '+' : ''}${chgPct.toStringAsFixed(2)}%)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isBullBar ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sig.mtfStructure,
                        style: const TextStyle(fontSize: 9.5, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                // Row D: Layer Mode Selector + Zoom/Pan Toolbar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _modeBtn('All Pro', 'ALL'),
                      _modeBtn('Clean Chart', 'CLEAN'),
                      _modeBtn('ICT + CRT', 'ICT'),
                      _modeBtn('Patterns + Wave', 'PATTERNS'),
                      _modeBtn('CVD + VP', 'ORDERFLOW'),
                      const SizedBox(width: 6),
                      _toolTextBtn(
                        'CRT HUD',
                        _showCrtHud,
                        () => setState(() => _showCrtHud = !_showCrtHud),
                      ),
                      _toolTextBtn(
                        _fitToTargets ? 'Fit: TP/SL' : 'Fit: Candles',
                        _fitToTargets,
                        () => setState(() => _fitToTargets = !_fitToTargets),
                      ),
                      _toolIconBtn(Icons.add, 'Zoom In', _zoomIn),
                      _toolIconBtn(Icons.remove, 'Zoom Out', _zoomOut),
                      _toolIconBtn(Icons.chevron_left, 'Pan Left', _panLeft),
                      _toolIconBtn(Icons.chevron_right, 'Pan Right', _panRight),
                      _toolTextBtn(
                        'Crosshair',
                        _crosshairMode,
                        () => setState(() {
                          _crosshairMode = !_crosshairMode;
                          if (!_crosshairMode) _crosshairPos = null;
                        }),
                      ),
                      _toolIconBtn(Icons.restart_alt, 'Reset View', _resetChart),
                      if (!widget.isFullScreen && widget.onOpenFullScreen != null)
                        _toolIconBtn(Icons.open_in_full, 'Fullscreen', widget.onOpenFullScreen!),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Interactive Pinch-Zoom & Horizontal Drag Canvas with Floating TOLAG CRT HUD
          Expanded(
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _resetChart,
                  onScaleStart: (details) {
                    _baseVisibleCandles = _visibleCandles;
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      if (details.pointerCount >= 2) {
                        _visibleCandles = (_baseVisibleCandles / details.scale).clamp(12.0, 95.0);
                      } else if (_crosshairMode) {
                        _crosshairPos = details.localFocalPoint;
                      } else {
                        final double sensitivity = _visibleCandles / 260.0;
                        final double maxBack = max(0.0, candles.length - _visibleCandles);
                        _scrollBackBars = (_scrollBackBars + (details.focalPointDelta.dx * sensitivity)).clamp(0.0, maxBack);
                      }
                    });
                  },
                  onTapDown: (details) {
                    setState(() => _crosshairPos = details.localPosition);
                  },
                  child: ClipRect(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _DeltaExchangeProChartPainter(
                        signal: sig,
                        startIdx: startIdx,
                        endIdx: endIdx,
                        verticalZoom: _verticalZoom,
                        fitToTargets: _fitToTargets,
                        viewMode: _viewMode,
                        crosshairPos: _crosshairPos,
                      ),
                    ),
                  ),
                ),

                // Compact Non-Overlapping TOLAG CRT Precision HUD Box (Top-Left Corner, Toggleable)
                if (_showCrtHud)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1422).withOpacity(0.86),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.35), width: 0.9),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.diamond, size: 10, color: isLong ? const Color(0xFF00E676) : const Color(0xFFFF3D57)),
                                const SizedBox(width: 4),
                                Text(
                                  'TOLAG CRT FUSION • ${sig.confluenceScore}/100',
                                  style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'CRT High: ${sig.swingHighBsl.toStringAsFixed(dec)} | CRT Low: ${sig.swingLowSsl.toStringAsFixed(dec)}',
                              style: const TextStyle(fontSize: 8.0, color: Colors.white70),
                            ),
                            Text(
                              'EQ 50%: ${sig.equilibrium.toStringAsFixed(dec)} | OTE 70.5%: ${sig.otePrice.toStringAsFixed(dec)}',
                              style: const TextStyle(fontSize: 8.0, color: Colors.amberAccent),
                            ),
                          ],
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
  }

  Widget _strategyChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _modeBtn(String title, String mode) {
    final active = _viewMode == mode;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: () => setState(() => _viewMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2979FF) : const Color(0xFF182030),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: active ? Colors.cyanAccent : Colors.white12),
          ),
          child: Text(
            title,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.white70),
          ),
        ),
      ),
    );
  }

  Widget _toolIconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF182030),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, size: 13, color: Colors.cyanAccent),
        ),
      ),
    );
  }

  Widget _toolTextBtn(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF00E676).withOpacity(0.22) : const Color(0xFF182030),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: active ? const Color(0xFF00E676) : Colors.white24),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: active ? const Color(0xFF00E676) : Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _DeltaExchangeProChartPainter extends CustomPainter {
  final IctSignal signal;
  final int startIdx;
  final int endIdx;
  final double verticalZoom;
  final bool fitToTargets;
  final String viewMode;
  final Offset? crosshairPos;

  _DeltaExchangeProChartPainter({
    required this.signal,
    required this.startIdx,
    required this.endIdx,
    required this.verticalZoom,
    required this.fitToTargets,
    required this.viewMode,
    this.crosshairPos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final allCandles = signal.candles;
    if (allCandles.isEmpty || endIdx <= startIdx) return;

    final visible = allCandles.sublist(startIdx, endIdx);
    final int visLen = visible.length;
    final int dec = signal.markPrice < 1 ? 5 : (signal.markPrice < 100 ? 3 : 1);

    const double rightAxisW = 68.0;
    const double bottomAxisH = 20.0;
    final double chartW = max(size.width - rightAxisW, 50.0);
    final double totalPlotH = max(size.height - bottomAxisH, 80.0);
    final double pricePaneH = totalPlotH * 0.82;
    final double volPaneTop = pricePaneH;
    final double volPaneH = totalPlotH - pricePaneH;

    // Smart Vertical Collision Trackers so labels NEVER stack on top of each other!
    final List<double> usedLeftY = [];
    final List<double> usedMidRightY = [];
    final List<double> usedAxisY = [];

    double? reserveY(List<double> tracker, double targetY, {double minGap = 13.0, double minY = 6.0, double maxY = 9999.0}) {
      final clamped = targetY.clamp(minY, min(maxY, pricePaneH - 14.0));
      for (final existing in tracker) {
        if ((existing - clamped).abs() < minGap) {
          return null; // Skip or displace overlapping label
        }
      }
      tracker.add(clamped);
      return clamped;
    }

    // 1. Dynamic Y-Axis Auto-Scaling to Visible Candles
    double maxP = visible.map((c) => c.high).reduce(max);
    double minP = visible.map((c) => c.low).reduce(min);

    if (fitToTargets) {
      maxP = max(maxP, max(signal.tp3, signal.swingHighBsl));
      minP = min(minP, min(signal.stopLoss, signal.swingLowSsl));
    } else {
      maxP = max(maxP, max(signal.entry, signal.tp1));
      minP = min(minP, min(signal.entry, signal.stopLoss));
    }

    final double midP = (maxP + minP) / 2.0;
    final double halfSpan = max((maxP - minP) / 2.0, signal.markPrice * 0.002) * (1.15 / verticalZoom);
    maxP = midP + halfSpan;
    minP = midP - halfSpan;
    final double spanP = max(maxP - minP, 0.0000001);

    final bool atLiveEdge = endIdx >= allCandles.length;
    final int futureSlots = atLiveEdge ? 5 : 1;
    final double stepX = chartW / (visLen + futureSlots);

    double idxToX(int globalIdx) => ((globalIdx - startIdx) + 0.5) * stepX;
    double priceToY(double p) => (pricePaneH - ((p - minP) / spanP) * pricePaneH).clamp(4.0, pricePaneH - 4.0);
    double yToPrice(double y) => minP + ((pricePaneH - y) / pricePaneH) * spanP;

    final bool showIct = viewMode == 'ALL' || viewMode == 'ICT';
    final bool showPatterns = viewMode == 'ALL' || viewMode == 'PATTERNS';
    final bool showOrderflow = viewMode == 'ALL' || viewMode == 'ORDERFLOW';
    final bool showAvwap = viewMode == 'ALL' || viewMode == 'CLEAN' || viewMode == 'ICT';

    // 2. Draw Grid & Axis Borders
    final gridPaint = Paint()..color = const Color(0xFF1A2232)..strokeWidth = 0.8;
    const int priceSteps = 5;
    for (int i = 1; i < priceSteps; i++) {
      final y = pricePaneH * (i / priceSteps);
      _drawDashedLine(canvas, Offset(0, y), Offset(chartW, y), gridPaint, dashW: 3, spaceW: 3);
      final tickPrice = yToPrice(y);
      _drawBadge(
        canvas,
        tickPrice.toStringAsFixed(dec),
        Offset(chartW + 4, y - 6),
        Colors.white38,
        fontSize: 8.0,
      );
    }

    final int timeStep = max(1, (visLen / 5).round());
    for (int i = 0; i < visLen; i += timeStep) {
      final x = (i + 0.5) * stepX;
      _drawDashedLine(canvas, Offset(x, 0), Offset(x, totalPlotH), gridPaint, dashW: 3, spaceW: 3);
      final ts = visible[i].timestamp;
      if (ts > 0) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        final tStr = DateFormat('HH:mm').format(dt);
        _drawBadge(canvas, tStr, Offset(x - 14, totalPlotH + 4), Colors.white54, fontSize: 8.0);
      }
    }

    final borderPaint = Paint()..color = const Color(0xFF253044)..strokeWidth = 1.0;
    canvas.drawLine(Offset(chartW, 0), Offset(chartW, totalPlotH), borderPaint);
    canvas.drawLine(Offset(0, pricePaneH), Offset(chartW, pricePaneH), borderPaint);
    canvas.drawLine(Offset(0, totalPlotH), Offset(size.width, totalPlotH), borderPaint);

    // 3. Draw Composite Volume Profile (CVP) on Left Wall
    if (showOrderflow && signal.strategyExtras.volumeProfileBins.isNotEmpty) {
      final bins = signal.strategyExtras.volumeProfileBins;
      final binH = pricePaneH / bins.length;
      for (int b = 0; b < bins.length; b++) {
        final w = bins[b] * (chartW * 0.22);
        final yTop = pricePaneH - ((b + 1) * binH);
        final isPocBin = b == (bins.length ~/ 2);
        final vpPaint = Paint()
          ..color = (isPocBin ? Colors.amberAccent : Colors.cyanAccent).withOpacity(isPocBin ? 0.20 : 0.08);
        canvas.drawRect(Rect.fromLTWH(0, yTop, w, max(binH - 1, 1)), vpPaint);
      }
      final pocY = priceToY(signal.patternAnalysis.compositePoc);
      if (pocY > 12 && pocY < pricePaneH - 12) {
        _drawDashedLine(
          canvas,
          Offset(0, pocY),
          Offset(chartW, pocY),
          Paint()..color = Colors.amberAccent.withOpacity(0.65)..strokeWidth = 1.0,
        );
        final ry = reserveY(usedLeftY, pocY - 10, minY: 42);
        if (ry != null) {
          _drawBadge(canvas, 'VP POC', Offset(4, ry), Colors.amberAccent, bg: true, fontSize: 7.5);
        }
      }
    }

    // 4. Draw CRT Reference Range Box (TOLAG CRT High, CRT Low, 50% Equilibrium, 70.5% OTE)
    if (showIct) {
      final double bslY = priceToY(signal.swingHighBsl);
      final double sslY = priceToY(signal.swingLowSsl);
      final double eqY = priceToY(signal.equilibrium);
      final double oteY = priceToY(signal.otePrice);

      // TOLAG CRT Reference Box outline on right 65% of chart
      final double crtLeft = chartW * 0.32;
      final Rect crtRect = Rect.fromLTRB(crtLeft, min(bslY, sslY), chartW, max(bslY, sslY));
      canvas.drawRect(crtRect, Paint()..color = Colors.cyanAccent.withOpacity(0.03));
      canvas.drawRect(
        crtRect,
        Paint()
          ..color = Colors.cyanAccent.withOpacity(0.28)
          ..strokeWidth = 0.9
          ..style = PaintingStyle.stroke,
      );

      if (bslY > 8 && bslY < pricePaneH - 8) {
        final ry = reserveY(usedMidRightY, bslY - 11);
        if (ry != null) {
          _drawBadge(canvas, 'CRT HIGH / BSL', Offset(crtLeft + 4, ry), const Color(0xFFFF5252), bg: true, fontSize: 7.5);
        }
      }
      if (sslY > 8 && sslY < pricePaneH - 8) {
        final ry = reserveY(usedMidRightY, sslY + 2);
        if (ry != null) {
          _drawBadge(canvas, 'CRT LOW / SSL', Offset(crtLeft + 4, ry), const Color(0xFF00E676), bg: true, fontSize: 7.5);
        }
      }
      if (eqY > 10 && eqY < pricePaneH - 10) {
        _drawDashedLine(
          canvas,
          Offset(crtLeft, eqY),
          Offset(chartW, eqY),
          Paint()..color = Colors.white38..strokeWidth = 0.9,
        );
        final ry = reserveY(usedMidRightY, eqY - 10);
        if (ry != null) {
          _drawBadge(canvas, 'EQ 50%', Offset(crtLeft + 4, ry), Colors.white70, bg: true, fontSize: 7.5);
        }
      }
      if (oteY > 10 && oteY < pricePaneH - 10) {
        final double oteBandPx = (pricePaneH * 0.03).clamp(5.0, 13.0);
        canvas.drawRect(
          Rect.fromLTRB(crtLeft, oteY - oteBandPx / 2, chartW, oteY + oteBandPx / 2),
          Paint()..color = Colors.amberAccent.withOpacity(0.11),
        );
        final ry = reserveY(usedMidRightY, oteY - 10);
        if (ry != null) {
          _drawBadge(canvas, '🎯 70.5% OTE', Offset(crtLeft + 54, ry), Colors.amberAccent, bg: true, fontSize: 7.5);
        }
      }

      // Draw Deduplicated ICT Zone Boxes (Max 3 Non-Overlapping Zones in Visible Range!)
      // Labels are anchored cleanly on the right-inside edge of the zone so they NEVER stack on the left wall!
      int drawnZones = 0;
      for (final z in signal.zoneBoxes) {
        if (drawnZones >= 3) break;
        if (z.bottom > maxP || z.top < minP) continue;
        final topY = priceToY(z.top);
        final botY = priceToY(z.bottom);
        final midY = (topY + botY) / 2.0;

        // Check vertical collision before drawing zone label
        final ry = reserveY(usedMidRightY, min(topY, botY) + 1, minGap: 14.0);
        if (ry == null && drawnZones > 0) continue;

        final bool isUnicorn = z.type == 'UNICORN';
        final bool isBullZone = z.type.contains('BISI') || z.type.contains('BULL') || (isUnicorn && signal.direction == 'LONG');
        final Color zoneColor = isUnicorn
            ? Colors.amberAccent
            : (isBullZone ? const Color(0xFF00E676) : const Color(0xFFFF5252));

        final double xStart = idxToX(z.startIndex).clamp(chartW * 0.18, chartW * 0.72);
        final rect = Rect.fromLTRB(xStart, min(topY, botY), chartW, max(max(topY, botY), min(topY, botY) + 4));
        canvas.drawRect(rect, Paint()..color = zoneColor.withOpacity(isUnicorn ? 0.16 : 0.10));
        canvas.drawLine(Offset(xStart, topY), Offset(chartW, topY), Paint()..color = zoneColor.withOpacity(0.5)..strokeWidth = 0.9);
        canvas.drawLine(Offset(xStart, botY), Offset(chartW, botY), Paint()..color = zoneColor.withOpacity(0.5)..strokeWidth = 0.9);

        if (ry != null) {
          _drawBadge(canvas, z.label, Offset((chartW - 88).clamp(xStart + 4, chartW - 50), ry), zoneColor, bg: true, fontSize: 7.5);
        }
        drawnZones++;
      }
    }

    // 5. Draw PhenLabs Anchored VWAP ±1σ Value Cloud & EMA 9/21 Ribbon
    if (showAvwap && signal.avwapState.avwapCurve.isNotEmpty) {
      final isBull = signal.direction == 'LONG';
      final spineColor = isBull ? Colors.cyanAccent : Colors.deepOrangeAccent;
      final curve = signal.avwapState.avwapCurve;
      final upC = signal.avwapState.upperBandCurve;
      final dnC = signal.avwapState.lowerBandCurve;
      final int curveStartGlobal = max(0, allCandles.length - curve.length);

      final avwapPath = Path();
      final cloudPoly = Path();
      bool started = false;
      final List<Offset> lowerPts = [];

      for (int i = 0; i < curve.length; i++) {
        final gIdx = curveStartGlobal + i;
        if (gIdx < startIdx || gIdx >= endIdx) continue;
        final x = idxToX(gIdx);
        final y = priceToY(curve[i]);
        final yUp = priceToY(upC[i]);
        final yDn = priceToY(dnC[i]);

        if (!started) {
          avwapPath.moveTo(x, y);
          cloudPoly.moveTo(x, yUp);
          started = true;
        } else {
          avwapPath.lineTo(x, y);
          cloudPoly.lineTo(x, yUp);
        }
        lowerPts.add(Offset(x, yDn));
      }
      for (int i = lowerPts.length - 1; i >= 0; i--) {
        cloudPoly.lineTo(lowerPts[i].dx, lowerPts[i].dy);
      }
      if (started) {
        cloudPoly.close();
        canvas.drawPath(cloudPoly, Paint()..color = spineColor.withOpacity(0.07));
        canvas.drawPath(
          avwapPath,
          Paint()
            ..color = spineColor
            ..strokeWidth = 1.6
            ..style = PaintingStyle.stroke,
        );
      }
    }

    _drawLineSeries(canvas, signal.strategyExtras.ema9Series, startIdx, endIdx, idxToX, priceToY, Colors.cyanAccent.withOpacity(0.55), 1.1);
    _drawLineSeries(canvas, signal.strategyExtras.ema21Series, startIdx, endIdx, idxToX, priceToY, Colors.amber.withOpacity(0.55), 1.1);

    // 6. Draw Candlesticks + Volume & CVD Bars
    final double maxVol = max(visible.map((c) => c.volume).reduce(max), 1.0);
    final double candleBodyW = (stepX * 0.72).clamp(2.5, 18.0);

    for (int i = 0; i < visLen; i++) {
      final c = visible[i];
      final gIdx = startIdx + i;
      final x = idxToX(gIdx);
      final isBull = c.close >= c.open;
      final Color candleColor = isBull ? const Color(0xFF00E676) : const Color(0xFFFF3D57);

      final highY = priceToY(c.high);
      final lowY = priceToY(c.low);
      final openY = priceToY(c.open);
      final closeY = priceToY(c.close);

      canvas.drawLine(
        Offset(x, highY),
        Offset(x, lowY),
        Paint()
          ..color = candleColor
          ..strokeWidth = (stepX > 8 ? 1.4 : 1.0),
      );

      final bodyTop = min(openY, closeY);
      final bodyBot = max(max(openY, closeY), bodyTop + 2.0);
      canvas.drawRect(
        Rect.fromLTRB(x - candleBodyW / 2, bodyTop, x + candleBodyW / 2, bodyBot),
        Paint()..color = candleColor,
      );

      final double vRatio = (c.volume / maxVol).clamp(0.05, 1.0);
      final double barH = vRatio * (volPaneH * 0.80);
      final double barTop = volPaneTop + volPaneH - barH;
      canvas.drawRect(
        Rect.fromLTRB(x - candleBodyW / 2, barTop, x + candleBodyW / 2, volPaneTop + volPaneH),
        Paint()..color = candleColor.withOpacity(showOrderflow ? 0.55 : 0.28),
      );
    }

    _drawBadge(
      canvas,
      signal.strategyExtras.hasCvdAbsorption ? 'CVD ORDERFLOW (ABSORPTION ⚡)' : 'VOLUME & CVD DELTA',
      Offset(6, volPaneTop + 3),
      signal.strategyExtras.hasCvdAbsorption ? const Color(0xFF00E676) : Colors.white54,
      bg: true,
      fontSize: 7.5,
    );

    // 7. Draw Spaced Geometric Chart Patterns & Elliott Waves (Anti-Crowding Filter)
    if (showPatterns) {
      for (final line in signal.patternAnalysis.patternLines) {
        if (line.role == 'CVP_POC') continue;
        final x1 = idxToX(line.startIndex).clamp(0.0, chartW);
        final y1 = priceToY(line.startPrice);
        final x2 = idxToX(line.endIndex).clamp(0.0, chartW);
        final y2 = priceToY(line.endPrice);

        Color lineColor = Colors.purpleAccent;
        double strokeW = 1.6;
        if (line.role == 'NECKLINE') {
          lineColor = Colors.amberAccent;
          strokeW = 1.3;
        } else if (line.role == 'UPPER_TREND' || line.role == 'LOWER_TREND') {
          lineColor = Colors.lightBlueAccent.withOpacity(0.85);
          strokeW = 1.3;
        }

        final p = Paint()
          ..color = lineColor
          ..strokeWidth = strokeW
          ..style = PaintingStyle.stroke;

        if (line.isDashed) {
          _drawDashedLine(canvas, Offset(x1, y1), Offset(x2, y2), p);
        } else {
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), p);
        }
      }

      // Filter KeyPoints so badges are at least 26px apart horizontally
      double lastKpX = -999.0;
      for (final kp in signal.patternAnalysis.patternKeyPoints) {
        if (kp.index < startIdx || kp.index >= endIdx) continue;
        final x = idxToX(kp.index);
        if ((x - lastKpX).abs() < 26.0) continue;
        lastKpX = x;

        final y = priceToY(kp.price);
        final kpColor = kp.tag.contains('BOS') || kp.tag.contains('CHoCH')
            ? Colors.cyanAccent
            : (kp.isBullish ? const Color(0xFF00E676) : const Color(0xFFFF5252));

        canvas.drawCircle(Offset(x, y), 3.0, Paint()..color = kpColor);
        final offsetY = (kp.isBullish ? y + 4 : y - 14).clamp(6.0, pricePaneH - 14.0);
        _drawBadge(canvas, kp.tag, Offset((x - 10).clamp(4.0, chartW - 36.0), offsetY), kpColor, bg: true, fontSize: 7.5);
      }

      if (signal.patternAnalysis.waves.isNotEmpty) {
        final wavePaint = Paint()..color = Colors.amberAccent..strokeWidth = 1.6..style = PaintingStyle.stroke;
        final projPaint = Paint()..color = const Color(0xFF00E676)..strokeWidth = 1.6..style = PaintingStyle.stroke;

        Offset? prevPt;
        for (final w in signal.patternAnalysis.waves) {
          if (w.index < startIdx) continue;
          final x = idxToX(w.index).clamp(6.0, chartW - 8.0);
          final y = priceToY(w.price);
          final pt = Offset(x, y);

          if (prevPt != null) {
            if (w.isProjected) {
              _drawDashedLine(canvas, prevPt, pt, projPaint);
            } else {
              canvas.drawLine(prevPt, pt, wavePaint);
            }
          }
          prevPt = pt;
          final c = w.isProjected ? const Color(0xFF00E676) : Colors.amberAccent;
          canvas.drawCircle(pt, 2.8, Paint()..color = c);
          _drawBadge(canvas, w.label, Offset((x - 8).clamp(4.0, chartW - 28.0), (y - 13).clamp(4.0, pricePaneH - 14.0)), c, bg: true, fontSize: 7.5);
        }
      }
    }

    // 8. Draw Non-Overlapping Right Axis Execution Pills (MARK, ENTRY, TP1, TP2, TP3, SL)
    // Reserve Mark Price Pill FIRST so it always takes priority
    final double markY = priceToY(signal.markPrice);
    final Color markColor = signal.direction == 'LONG' ? const Color(0xFF00C853) : const Color(0xFFFF3D57);
    _drawDashedLine(canvas, Offset(0, markY), Offset(chartW, markY), Paint()..color = markColor.withOpacity(0.85)..strokeWidth = 1.0);
    usedAxisY.add(markY);

    _drawAxisTagLine(canvas, chartW, rightAxisW, pricePaneH, priceToY(signal.entry), 'ENTRY', Colors.white, usedAxisY, dashed: false);
    _drawAxisTagLine(canvas, chartW, rightAxisW, pricePaneH, priceToY(signal.tp1), 'TP1', Colors.cyanAccent, usedAxisY, dashed: true);
    _drawAxisTagLine(canvas, chartW, rightAxisW, pricePaneH, priceToY(signal.tp2), 'TP2', const Color(0xFF69F0AE), usedAxisY, dashed: true);
    _drawAxisTagLine(canvas, chartW, rightAxisW, pricePaneH, priceToY(signal.tp3), 'TP3', const Color(0xFF00E676), usedAxisY, dashed: true);
    _drawAxisTagLine(canvas, chartW, rightAxisW, pricePaneH, priceToY(signal.stopLoss), 'SL', const Color(0xFFFF3D57), usedAxisY, dashed: true);

    // Draw Live Mark Price Pill on top
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(chartW + 1, (markY - 8).clamp(2.0, pricePaneH - 16.0), rightAxisW - 2, 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(pillRect, Paint()..color = markColor);
    _drawBadge(
      canvas,
      signal.markPrice.toStringAsFixed(dec),
      Offset(chartW + 4, (markY - 6).clamp(4.0, pricePaneH - 14.0)),
      Colors.black,
      fontSize: 8.5,
    );

    // 9. Precision Magnetic Crosshair
    if (crosshairPos != null && crosshairPos!.dx <= chartW && crosshairPos!.dy <= totalPlotH) {
      final int snapLocalIdx = ((crosshairPos!.dx / stepX).floor()).clamp(0, visLen - 1);
      final double snapX = (snapLocalIdx + 0.5) * stepX;
      final double chY = crosshairPos!.dy;

      final chPaint = Paint()..color = Colors.white70..strokeWidth = 0.9;
      _drawDashedLine(canvas, Offset(0, chY), Offset(chartW, chY), chPaint);
      _drawDashedLine(canvas, Offset(snapX, 0), Offset(snapX, totalPlotH), chPaint);

      if (chY <= pricePaneH) {
        final hoverP = yToPrice(chY);
        final yPill = RRect.fromRectAndRadius(
          Rect.fromLTWH(chartW + 1, chY - 8, rightAxisW - 2, 16),
          const Radius.circular(3),
        );
        canvas.drawRRect(yPill, Paint()..color = const Color(0xFF2979FF));
        _drawBadge(canvas, hoverP.toStringAsFixed(dec), Offset(chartW + 4, chY - 6), Colors.white, fontSize: 8.5);
      }

      final ts = visible[snapLocalIdx].timestamp;
      if (ts > 0) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        final timeStr = DateFormat('dd MMM HH:mm').format(dt);
        final xPill = RRect.fromRectAndRadius(
          Rect.fromLTWH((snapX - 34).clamp(0.0, chartW - 68), totalPlotH + 2, 68, 16),
          const Radius.circular(3),
        );
        canvas.drawRRect(xPill, Paint()..color = const Color(0xFF2979FF));
        _drawBadge(canvas, timeStr, Offset((snapX - 30).clamp(2.0, chartW - 64), totalPlotH + 4), Colors.white, fontSize: 8.0);
      }
    }
  }

  void _drawLineSeries(
    Canvas canvas,
    List<double> series,
    int startIdx,
    int endIdx,
    double Function(int) idxToX,
    double Function(double) priceToY,
    Color color,
    double width,
  ) {
    if (series.isEmpty) return;
    final path = Path();
    bool started = false;
    for (int i = startIdx; i < min(endIdx, series.length); i++) {
      final x = idxToX(i);
      final y = priceToY(series[i]);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    if (started) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawAxisTagLine(
    Canvas canvas,
    double chartW,
    double rightAxisW,
    double pricePaneH,
    double y,
    String tag,
    Color color,
    List<double> usedAxisY, {
    bool dashed = true,
  }) {
    if (y < 6 || y > pricePaneH - 6) return;
    final p = Paint()..color = color.withOpacity(0.60)..strokeWidth = 1.0;
    if (dashed) {
      _drawDashedLine(canvas, Offset(0, y), Offset(chartW, y), p);
    } else {
      canvas.drawLine(Offset(0, y), Offset(chartW, y), p);
    }

    // Check right-axis collision so tags never overlap!
    for (final existingY in usedAxisY) {
      if ((existingY - y).abs() < 13.5) {
        return; // Line is drawn, skip overlapping axis badge
      }
    }
    usedAxisY.add(y);
    final pill = RRect.fromRectAndRadius(
      Rect.fromLTWH(chartW + 2, y - 7, rightAxisW - 4, 14),
      const Radius.circular(3),
    );
    canvas.drawRRect(pill, Paint()..color = const Color(0xFF121A28));
    _drawBadge(canvas, tag, Offset(chartW + 5, y - 5), color, bg: false, fontSize: 7.5);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, {double dashW = 5.0, double spaceW = 3.5}) {
    final double dx = p2.dx - p1.dx;
    final double dy = p2.dy - p1.dy;
    final double dist = sqrt(dx * dx + dy * dy);
    if (dist <= 0.1) return;
    final double ux = dx / dist;
    final double uy = dy / dist;
    double cur = 0.0;
    while (cur < dist) {
      final double end = min(cur + dashW, dist);
      canvas.drawLine(
        Offset(p1.dx + ux * cur, p1.dy + uy * cur),
        Offset(p1.dx + ux * end, p1.dy + uy * end),
        paint,
      );
      cur += dashW + spaceW;
    }
  }

  void _drawBadge(
    Canvas canvas,
    String text,
    Offset pos,
    Color color, {
    bool bg = false,
    double fontSize = 8.5,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (bg) {
      final rect = Rect.fromLTWH(pos.dx - 2, pos.dy - 1, tp.width + 4, tp.height + 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = const Color(0xFF0B0E14).withOpacity(0.88),
      );
    }
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Full-Screen Dedicated Delta Exchange Pro Chart Screen with All-Timeframe Sniper Levels
class IctChartScreen extends StatefulWidget {
  final IctSignal signal;
  final DeltaExchangeIctService? service;

  const IctChartScreen({super.key, required this.signal, this.service});

  @override
  State<IctChartScreen> createState() => _IctChartScreenState();
}

class _IctChartScreenState extends State<IctChartScreen> {
  late DeltaExchangeIctService _service;
  late IctSignal _activeSignal;
  String _selectedTf = '15m';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DeltaExchangeIctService();
    _activeSignal = widget.signal;
  }

  Future<void> _reloadTimeframe(String tf) async {
    setState(() {
      _selectedTf = tf;
      _loading = true;
    });
    try {
      final candles = await _service.fetchCandles(_activeSignal.symbol, resolution: tf, count: 110);
      final htf = await _service.fetchCandles(_activeSignal.symbol, resolution: '4h', count: 50);
      final macro = await _service.fetchMacroRegime(btcCandles: candles, resolution: tf);
      final updated = _service.evaluateIctConfluence(
        symbol: _activeSignal.symbol,
        productId: _activeSignal.productId,
        markPrice: candles.isNotEmpty ? candles.last.close : _activeSignal.markPrice,
        fundingRate: _activeSignal.fundingRate,
        openInterest: _activeSignal.openInterest,
        candles: candles,
        htfCandles: htf,
        btcCandles: candles,
        macro: macro,
        timeframe: tf,
      );
      if (mounted && updated != null) {
        setState(() {
          _activeSignal = updated;
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Widget _copyPill(String label, double val, int dec, Color color) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: val.toStringAsFixed(dec)));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied $label: ${val.toStringAsFixed(dec)}'), duration: const Duration(milliseconds: 500)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF162032),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 8.0, color: Colors.white54, fontWeight: FontWeight.bold)),
            Text(val.toStringAsFixed(dec), style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sig = _activeSignal;
    final isLong = sig.direction == 'LONG';
    final dec = sig.markPrice < 1 ? 5 : (sig.markPrice < 100 ? 3 : 1);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F141F),
        titleSpacing: 4,
        title: Row(
          children: [
            Text(
              '${sig.symbol} • ${_selectedTf.toUpperCase()}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isLong ? const Color(0xFF00E676).withOpacity(0.2) : const Color(0xFFFF5252).withOpacity(0.2),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '${sig.direction} ${sig.confluenceScore}%',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isLong ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                ),
              ),
            ),
          ],
        ),
        actions: [
          ...['5m', '15m', '1h', '4h', '1d'].map((tf) {
            final active = _selectedTf == tf;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 11),
              child: InkWell(
                onTap: () => _reloadTimeframe(tf),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF2979FF) : const Color(0xFF161F2E),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(tf.toUpperCase(), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // Top Sniper Entry / SL / TP1 / TP2 / TP3 Strip + Pump/Dump Brief
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF121A28),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sig.reversalFlipBrief,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _copyPill('ENTRY', sig.entry, dec, Colors.white),
                    _copyPill('STOP LOSS', sig.stopLoss, dec, const Color(0xFFFF3D57)),
                    _copyPill('TP1 (1.1R)', sig.tp1, dec, Colors.cyanAccent),
                    _copyPill('TP2 (2.2R)', sig.tp2, dec, const Color(0xFF69F0AE)),
                    _copyPill('TP3 (WIDE)', sig.tp3, dec, const Color(0xFF00E676)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: DeltaProInteractiveChart(
                      signal: sig,
                      isFullScreen: true,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
