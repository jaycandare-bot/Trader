import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'delta_ict_service.dart';

/// Reusable Delta Exchange / TradingView-Grade Interactive Zoomable & Pannable Chart Widget
/// Works both inside scrollable tabs (Manual Inspector) and full-screen view!
class DeltaProInteractiveChart extends StatefulWidget {
  final IctSignal signal;
  final double height;
  final bool isFullScreen;
  final VoidCallback? onOpenFullScreen;

  const DeltaProInteractiveChart({
    super.key,
    required this.signal,
    this.height = 380,
    this.isFullScreen = false,
    this.onOpenFullScreen,
  });

  @override
  State<DeltaProInteractiveChart> createState() => _DeltaProInteractiveChartState();
}

class _DeltaProInteractiveChartState extends State<DeltaProInteractiveChart> {
  // Visible candle window count: smaller = zoomed in (min 12), larger = zoomed out (max 95)
  double _visibleCandles = 34.0;
  double _baseVisibleCandles = 34.0;

  // How many candles scrolled back from the latest live right edge (0 = live edge)
  double _scrollBackBars = 0.0;

  // Vertical Y-axis zoom multiplier (1.0 = auto-fit visible candles)
  double _verticalZoom = 1.0;

  // Whether to fit Y-axis tightly to visible candles (Delta Exchange default) or expand to include Wide TP3/SL
  bool _fitToTargets = false;

  // Crosshair mode: when true, 1-finger drag moves precision OHLCV crosshair; when false, 1-finger drag pans history
  bool _crosshairMode = false;
  Offset? _crosshairPos;

  // Clean Layer View Mode: 'ALL', 'CLEAN', 'ICT', 'PATTERNS', 'ORDERFLOW'
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

    // Determine currently inspected candle for OHLCV bar
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
          // 1. Delta Exchange Style Live OHLCV + Layer Mode Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF111622),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Live Session & Killzone Status Row inside Chart
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
                            Text(
                              '⏱ ${sess.istTimeStr} (${sess.utcTimeStr}) • ${sess.countdownLabel}',
                              style: const TextStyle(fontSize: 9.5, color: Colors.white70, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        'O ${inspected.open.toStringAsFixed(dec)}  ',
                        style: const TextStyle(fontSize: 10, color: Colors.white70, fontFamily: 'monospace'),
                      ),
                      Text(
                        'H ${inspected.high.toStringAsFixed(dec)}  ',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF00E676), fontFamily: 'monospace'),
                      ),
                      Text(
                        'L ${inspected.low.toStringAsFixed(dec)}  ',
                        style: const TextStyle(fontSize: 10, color: Color(0xFFFF5252), fontFamily: 'monospace'),
                      ),
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
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                // Layer Mode Selector + Zoom/Pan Toolbar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _modeBtn('All Layers', 'ALL'),
                      _modeBtn('Clean Delta', 'CLEAN'),
                      _modeBtn('ICT + Unicorn', 'ICT'),
                      _modeBtn('Patterns + Wave', 'PATTERNS'),
                      _modeBtn('Orderflow CVD', 'ORDERFLOW'),
                      const SizedBox(width: 6),
                      _toolIconBtn(Icons.add, 'Zoom In', _zoomIn),
                      _toolIconBtn(Icons.remove, 'Zoom Out', _zoomOut),
                      _toolIconBtn(Icons.chevron_left, 'Pan Left', _panLeft),
                      _toolIconBtn(Icons.chevron_right, 'Pan Right', _panRight),
                      _toolTextBtn(
                        _fitToTargets ? 'Fit: TP/SL' : 'Fit: Candles',
                        _fitToTargets,
                        () => setState(() => _fitToTargets = !_fitToTargets),
                      ),
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
          // 2. Interactive Pinch-Zoom & Horizontal Drag Canvas
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _resetChart,
              onScaleStart: (details) {
                _baseVisibleCandles = _visibleCandles;
              },
              onScaleUpdate: (details) {
                setState(() {
                  if (details.pointerCount >= 2) {
                    // Pinch to zoom horizontally & vertically
                    _visibleCandles = (_baseVisibleCandles / details.scale).clamp(12.0, 95.0);
                  } else if (_crosshairMode) {
                    // 1-finger precision crosshair inspection
                    _crosshairPos = details.localFocalPoint;
                  } else {
                    // 1-finger smooth horizontal history pan
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
          ),
        ],
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

    // Layout Regions:
    // - Right Price Axis Sidebar: 66px wide
    // - Bottom Time Axis Bar: 20px high
    // - Main Price Chart Area: 82% of remaining height
    // - Bottom Volume + CVD Orderflow Pane: 18% of remaining height
    const double rightAxisW = 66.0;
    const double bottomAxisH = 20.0;
    final double chartW = max(size.width - rightAxisW, 50.0);
    final double totalPlotH = max(size.height - bottomAxisH, 80.0);
    final double pricePaneH = totalPlotH * 0.82;
    final double volPaneTop = pricePaneH;
    final double volPaneH = totalPlotH - pricePaneH;

    // 1. Dynamic Y-Axis Auto-Scaling to Visible Candles (Delta Exchange Crispness!)
    double maxP = visible.map((c) => c.high).reduce(max);
    double minP = visible.map((c) => c.low).reduce(min);

    if (fitToTargets) {
      maxP = max(maxP, max(signal.tp3, signal.swingHighBsl));
      minP = min(minP, min(signal.stopLoss, signal.swingLowSsl));
    } else {
      // Include nearby entry/TP1 so immediate trade setup is always clear without squishing candles
      maxP = max(maxP, max(signal.entry, signal.tp1));
      minP = min(minP, min(signal.entry, signal.stopLoss));
    }

    final double midP = (maxP + minP) / 2.0;
    final double halfSpan = max((maxP - minP) / 2.0, signal.markPrice * 0.002) * (1.14 / verticalZoom);
    maxP = midP + halfSpan;
    minP = midP - halfSpan;
    final double spanP = max(maxP - minP, 0.0000001);

    // Reserve 5 future slots on the right when viewing the live edge (for Elliott Wave 5 & ABC projection)
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

    // 2. Draw Delta Exchange Grid & Axis Borders
    final gridPaint = Paint()..color = const Color(0xFF1A2232)..strokeWidth = 0.8;
    const int priceSteps = 6;
    for (int i = 1; i < priceSteps; i++) {
      final y = pricePaneH * (i / priceSteps);
      _drawDashedLine(canvas, Offset(0, y), Offset(chartW, y), gridPaint, dashW: 3, spaceW: 3);
      final tickPrice = yToPrice(y);
      _drawBadge(
        canvas,
        tickPrice.toStringAsFixed(dec),
        Offset(chartW + 4, y - 6),
        Colors.white54,
        fontSize: 8.5,
      );
    }

    // Vertical time gridlines + Bottom Time Labels
    final int timeStep = max(1, (visLen / 5).round());
    for (int i = 0; i < visLen; i += timeStep) {
      final x = (i + 0.5) * stepX;
      _drawDashedLine(canvas, Offset(x, 0), Offset(x, totalPlotH), gridPaint, dashW: 3, spaceW: 3);
      final ts = visible[i].timestamp;
      if (ts > 0) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        final tStr = DateFormat('HH:mm').format(dt);
        _drawBadge(canvas, tStr, Offset(x - 14, totalPlotH + 4), Colors.white54, fontSize: 8.5);
      }
    }

    // Axis Dividers
    final borderPaint = Paint()..color = const Color(0xFF253044)..strokeWidth = 1.0;
    canvas.drawLine(Offset(chartW, 0), Offset(chartW, totalPlotH), borderPaint);
    canvas.drawLine(Offset(0, pricePaneH), Offset(chartW, pricePaneH), borderPaint);
    canvas.drawLine(Offset(0, totalPlotH), Offset( size.width, totalPlotH), borderPaint);

    // 3. Draw Composite Volume Profile (CVP) Horizontal Histogram on Left Wall
    if (showOrderflow && signal.strategyExtras.volumeProfileBins.isNotEmpty) {
      final bins = signal.strategyExtras.volumeProfileBins;
      final binH = pricePaneH / bins.length;
      for (int b = 0; b < bins.length; b++) {
        final w = bins[b] * (chartW * 0.26);
        final yTop = pricePaneH - ((b + 1) * binH);
        final isPocBin = b == (bins.length ~/ 2);
        final vpPaint = Paint()
          ..color = (isPocBin ? Colors.amberAccent : Colors.cyanAccent).withOpacity(isPocBin ? 0.24 : 0.10);
        canvas.drawRect(Rect.fromLTWH(0, yTop, w, max(binH - 1, 1)), vpPaint);
      }
      final pocY = priceToY(signal.patternAnalysis.compositePoc);
      _drawDashedLine(
        canvas,
        Offset(0, pocY),
        Offset(chartW, pocY),
        Paint()..color = Colors.amberAccent.withOpacity(0.75)..strokeWidth = 1.1,
      );
      _drawBadge(canvas, 'POC', Offset(4, pocY - 11), Colors.amberAccent, bg: true);
    }

    // 3B. Draw Live Session Zones (Asian Range High/Low Box + True Day Session Open Line)
    if (viewMode == 'ALL' || viewMode == 'ICT' || viewMode == 'CLEAN') {
      final double ashY = priceToY(signal.strategyExtras.asianHigh);
      final double aslY = priceToY(signal.strategyExtras.asianLow);
      final double sessOpenY = priceToY(signal.strategyExtras.sessionOpenPrice);

      // Shaded Asian Accumulation Range Box on left half of visible session
      final Rect asianRect = Rect.fromLTRB(0, min(ashY, aslY), chartW * 0.45, max(ashY, aslY));
      canvas.drawRect(asianRect, Paint()..color = Colors.blueAccent.withOpacity(0.06));
      _drawDashedLine(
        canvas,
        Offset(0, ashY),
        Offset(chartW * 0.65, ashY),
        Paint()..color = Colors.lightBlueAccent.withOpacity(0.6)..strokeWidth = 1.0,
      );
      _drawDashedLine(
        canvas,
        Offset(0, aslY),
        Offset(chartW * 0.65, aslY),
        Paint()..color = Colors.lightBlueAccent.withOpacity(0.6)..strokeWidth = 1.0,
      );
      _drawBadge(canvas, 'ASIAN HIGH (ASH)', Offset(6, ashY - 11), Colors.lightBlueAccent, bg: true, fontSize: 8.0);
      _drawBadge(canvas, 'ASIAN LOW (ASL)', Offset(6, aslY + 2), Colors.lightBlueAccent, bg: true, fontSize: 8.0);

      // True Day / Session Open 00:00 UTC Line (Power of 3 AMD Pivot)
      _drawDashedLine(
        canvas,
        Offset(0, sessOpenY),
        Offset(chartW, sessOpenY),
        Paint()..color = Colors.purpleAccent.withOpacity(0.65)..strokeWidth = 1.0,
      );
      _drawBadge(
        canvas,
        'SESSION OPEN (${signal.strategyExtras.po3Phase})',
        Offset(chartW * 0.38, sessOpenY - 11),
        Colors.purpleAccent,
        bg: true,
        fontSize: 8.0,
      );
    }

    // 4. Draw ICT Order Blocks (+OB / -OB), Unicorn Setup, and BISI/SIBI FVGs
    if (showIct) {
      for (final z in signal.zoneBoxes.take(4)) {
        final topY = priceToY(z.top);
        final botY = priceToY(z.bottom);
        final bool isUnicorn = z.type == 'UNICORN';
        final bool isBullZone = z.type.contains('BISI') || z.type.contains('BULL') || (isUnicorn && signal.direction == 'LONG');
        final Color zoneColor = isUnicorn
            ? Colors.amberAccent
            : (isBullZone ? const Color(0xFF00E676) : const Color(0xFFFF5252));

        final double xStart = idxToX(z.startIndex).clamp(0.0, chartW * 0.75);
        final rect = Rect.fromLTRB(xStart, min(topY, botY), chartW, max(topY, botY) + 3);
        canvas.drawRect(rect, Paint()..color = zoneColor.withOpacity(isUnicorn ? 0.18 : 0.11));
        canvas.drawLine(Offset(xStart, topY), Offset(chartW, topY), Paint()..color = zoneColor.withOpacity(0.55)..strokeWidth = 1.0);
        canvas.drawLine(Offset(xStart, botY), Offset(chartW, botY), Paint()..color = zoneColor.withOpacity(0.55)..strokeWidth = 1.0);
        _drawBadge(canvas, z.label, Offset(xStart + 4, min(topY, botY) + 2), zoneColor, bg: true);
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
        canvas.drawPath(cloudPoly, Paint()..color = spineColor.withOpacity(0.08));
        canvas.drawPath(
          avwapPath,
          Paint()
            ..color = spineColor
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // Draw EMA 9 (Cyan thin) & EMA 21 (Amber thin) like Delta Exchange
    _drawLineSeries(canvas, signal.strategyExtras.ema9Series, startIdx, endIdx, idxToX, priceToY, Colors.cyanAccent.withOpacity(0.55), 1.1);
    _drawLineSeries(canvas, signal.strategyExtras.ema21Series, startIdx, endIdx, idxToX, priceToY, Colors.amber.withOpacity(0.55), 1.1);

    // 6. Draw Crisp Delta Exchange Candlesticks + Bottom Volume & CVD Orderflow Bars
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

      // Sharp Wick
      canvas.drawLine(
        Offset(x, highY),
        Offset(x, lowY),
        Paint()
          ..color = candleColor
          ..strokeWidth = (stepX > 8 ? 1.4 : 1.0),
      );

      // Crisp Candle Body
      final bodyTop = min(openY, closeY);
      final bodyBot = max(max(openY, closeY), bodyTop + 2.0);
      final bodyRect = Rect.fromLTRB(x - candleBodyW / 2, bodyTop, x + candleBodyW / 2, bodyBot);
      canvas.drawRect(bodyRect, Paint()..color = candleColor);

      // Bottom Volume & CVD Delta Bar
      final double vRatio = (c.volume / maxVol).clamp(0.05, 1.0);
      final double barH = vRatio * (volPaneH * 0.82);
      final double barTop = volPaneTop + volPaneH - barH;
      canvas.drawRect(
        Rect.fromLTRB(x - candleBodyW / 2, barTop, x + candleBodyW / 2, volPaneTop + volPaneH),
        Paint()..color = candleColor.withOpacity(showOrderflow ? 0.55 : 0.28),
      );
    }

    // Label CVD Pane
    _drawBadge(
      canvas,
      signal.strategyExtras.hasCvdAbsorption ? 'CVD ORDERFLOW (ABSORPTION DETECTED ⚡)' : 'VOLUME & CVD DELTA',
      Offset(6, volPaneTop + 3),
      signal.strategyExtras.hasCvdAbsorption ? const Color(0xFF00E676) : Colors.white54,
      bg: true,
    );

    // 7. Draw Geometric Chart Patterns (W-Bottom, M-Top, H&S, Wedges, Neckline, BOS/CHoCH)
    if (showPatterns) {
      for (final line in signal.patternAnalysis.patternLines) {
        if (line.role == 'CVP_POC') continue;
        final x1 = idxToX(line.startIndex).clamp(0.0, chartW);
        final y1 = priceToY(line.startPrice);
        final x2 = idxToX(line.endIndex).clamp(0.0, chartW);
        final y2 = priceToY(line.endPrice);

        Color lineColor = Colors.purpleAccent;
        double strokeW = 1.8;
        if (line.role == 'NECKLINE') {
          lineColor = Colors.amberAccent;
          strokeW = 1.4;
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

      for (final kp in signal.patternAnalysis.patternKeyPoints) {
        if (kp.index < startIdx || kp.index >= endIdx) continue;
        final x = idxToX(kp.index);
        final y = priceToY(kp.price);
        final kpColor = kp.tag.contains('BOS') || kp.tag.contains('CHoCH')
            ? Colors.cyanAccent
            : (kp.isBullish ? const Color(0xFF00E676) : const Color(0xFFFF5252));

        canvas.drawCircle(Offset(x, y), 3.2, Paint()..color = kpColor);
        final offsetY = kp.isBullish ? y + 4 : y - 14;
        _drawBadge(canvas, kp.tag, Offset(x - 10, offsetY), kpColor, bg: true);
      }

      // Draw Elliott Wave (1)-(5) + (A)-(B)-(C)
      if (signal.patternAnalysis.waves.isNotEmpty) {
        final wavePaint = Paint()..color = Colors.amberAccent..strokeWidth = 1.8..style = PaintingStyle.stroke;
        final projPaint = Paint()..color = const Color(0xFF00E676)..strokeWidth = 1.8..style = PaintingStyle.stroke;

        Offset? prevPt;
        for (final w in signal.patternAnalysis.waves) {
          if (w.index < startIdx) continue;
          final x = idxToX(w.index).clamp(4.0, chartW - 6.0);
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
          canvas.drawCircle(pt, 3.0, Paint()..color = c);
          _drawBadge(canvas, w.label, Offset(x - 8, y - 13), c, bg: true);
        }
      }
    }

    // 8. Draw Key Execution Levels & Right Axis Pills (MARK, ENTRY, TP1, TP3, SL)
    _drawAxisTagLine(canvas, chartW, pricePaneH, priceToY(signal.tp3), 'TP3', const Color(0xFF00E676), dashed: true);
    _drawAxisTagLine(canvas, chartW, pricePaneH, priceToY(signal.tp1), 'TP1', Colors.cyanAccent, dashed: true);
    _drawAxisTagLine(canvas, chartW, pricePaneH, priceToY(signal.entry), 'ENTRY', Colors.white, dashed: false);
    _drawAxisTagLine(canvas, chartW, pricePaneH, priceToY(signal.stopLoss), 'SL', const Color(0xFFFF3D57), dashed: true);

    // Highlighted Live Mark Price Pill on Right Axis (Delta Exchange Signature Tag)
    final double markY = priceToY(signal.markPrice);
    final Color markColor = signal.direction == 'LONG' ? const Color(0xFF00C853) : const Color(0xFFFF3D57);
    _drawDashedLine(canvas, Offset(0, markY), Offset(chartW, markY), Paint()..color = markColor.withOpacity(0.8)..strokeWidth = 1.0);
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(chartW + 1, markY - 8, rightAxisW - 2, 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(pillRect, Paint()..color = markColor);
    _drawBadge(
      canvas,
      signal.markPrice.toStringAsFixed(dec),
      Offset(chartW + 4, markY - 6),
      Colors.black,
      fontSize: 8.5,
    );

    // 9. Precision Magnetic Crosshair with X/Y Coordinate Pills
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
    double pricePaneH,
    double y,
    String tag,
    Color color, {
    bool dashed = true,
  }) {
    if (y < 6 || y > pricePaneH - 6) return;
    final p = Paint()..color = color.withOpacity(0.65)..strokeWidth = 1.0;
    if (dashed) {
      _drawDashedLine(canvas, Offset(0, y), Offset(chartW, y), p);
    } else {
      canvas.drawLine(Offset(0, y), Offset(chartW, y), p);
    }
    _drawBadge(canvas, tag, Offset(chartW + 4, y - 6), color, bg: true, fontSize: 8.0);
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
        Paint()..color = const Color(0xFF0B0E14).withOpacity(0.85),
      );
    }
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Full-Screen Dedicated Delta Exchange Pro Chart Screen
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

  @override
  Widget build(BuildContext context) {
    final sig = _activeSignal;
    final isLong = sig.direction == 'LONG';
    final dec = sig.markPrice < 1 ? 5 : (sig.markPrice < 100 ? 3 : 1);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F141F),
        title: Row(
          children: [
            Text('${sig.symbol} • ${_selectedTf.toUpperCase()}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isLong ? const Color(0xFF00E676).withOpacity(0.2) : const Color(0xFFFF5252).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${sig.direction} • ${sig.confluenceScore}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isLong ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                ),
              ),
            ),
          ],
        ),
        actions: [
          ...['5m', '15m', '1h', '4h'].map((tf) {
            final active = _selectedTf == tf;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
              child: InkWell(
                onTap: () => _reloadTimeframe(tf),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF2979FF) : const Color(0xFF161F2E),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(tf.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // Institutional Strategy Telemetry Banner
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF131A26),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '📐 FORMED: ${sig.patternAnalysis.formedPattern}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'PO3: ${sig.strategyExtras.po3Phase}',
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '🚀 UPCOMING: ${sig.patternAnalysis.upcomingPattern}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      sig.strategyExtras.squeezeSignal,
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.purpleAccent),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Interactive Zoomable & Pannable Delta Chart
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
          // Bottom Live Execution Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: const Color(0xFF101722),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _metricCol('LIVE MARK', '\$${sig.markPrice.toStringAsFixed(dec)}', Colors.white),
                _metricCol('CVP POC', '\$${sig.patternAnalysis.compositePoc.toStringAsFixed(dec)}', Colors.amberAccent),
                _metricCol('AVWAP SPINE', '\$${sig.avwapState.currentAvwap.toStringAsFixed(dec)}', Colors.cyanAccent),
                _metricCol('WAVE (5)', '\$${sig.patternAnalysis.targetProjection.toStringAsFixed(dec)}', const Color(0xFF00E676)),
                _metricCol('WIDE TP3', '\$${sig.tp3.toStringAsFixed(dec)}', const Color(0xFF00E676)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCol(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.white54, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
