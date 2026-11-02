import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeltaInstitutionalTerminalApp());
}

class DeltaInstitutionalTerminalApp extends StatelessWidget {
  const DeltaInstitutionalTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Delta ICT Institutional Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
        primaryColor: const Color(0xFF00E676),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF2979FF),
          surface: Color(0xFF131822),
        ),
      ),
      home: const TerminalHomeScreen(),
    );
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

class Candle {
  final int time;
  double open;
  double high;
  double low;
  double close;
  double volume;

  Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      time: (json['time'] as num).toInt(),
      open: (json['open'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class HtfZone {
  final double top;
  final double bottom;
  final String label;
  final bool isBullish;

  HtfZone({
    required this.top,
    required this.bottom,
    required this.label,
    required this.isBullish,
  });
}

class TradeSignal {
  final String symbol;
  final String direction; // LONG or SHORT
  final int confidence;
  final String strategyName;
  final String patternTag;
  final double entry;
  final double stopLoss;
  final double tp1;
  final double tp2;
  final double markPrice;
  final double change24h;
  final bool isSmtStrong;
  final bool isPullback;
  final int quadrant;
  final String actionBrief;
  final DateTime signalTimeIst;

  TradeSignal({
    required this.symbol,
    required this.direction,
    required this.confidence,
    required this.strategyName,
    required this.patternTag,
    required this.entry,
    required this.stopLoss,
    required this.tp1,
    required this.tp2,
    required this.markPrice,
    required this.change24h,
    required this.isSmtStrong,
    required this.isPullback,
    required this.quadrant,
    required this.actionBrief,
    required this.signalTimeIst,
  });
}

// ============================================================================
// MAIN TERMINAL SCREEN
// ============================================================================

class TerminalHomeScreen extends StatefulWidget {
  const TerminalHomeScreen({super.key});

  @override
  State<TerminalHomeScreen> createState() => _TerminalHomeScreenState();
}

class _TerminalHomeScreenState extends State<TerminalHomeScreen> {
  static const String baseUrl = 'https://api.india.delta.exchange';
  static const String wsUrl = 'wss://socket.india.delta.exchange';

  int _bottomNavIndex = 0;
  bool _scanAll150Plus = true;
  String _selectedFilter = 'ALL_75';
  String _searchQuery = '';

  double _capitalUsd = 190.0;
  int _leverage = 10;
  bool _autoAlert = false;

  double _btcPrice = 77395.0;
  double _btcChange24h = -1.25;
  double _btcDominance = 58.40;
  int _currentQuad = 3;
  String _istTimeStr = '';
  String _killzoneTitle = '';
  String _killzoneSubtitle = '';
  String _killzoneCountdown = '';

  bool _isScanning = false;
  int _scannedCoinsCount = 0;
  int _totalCoinsToScan = 0;
  List<String> _allPerpSymbols = [];
  List<TradeSignal> _signals = [];

  // Live Chart & Search State
  String _selectedChartSymbol = 'BTCUSD';
  String _selectedResolution = '15m';
  bool _useMarkPriceChart = true;
  List<Candle> _chartCandles = [];
  List<Candle> _htf1hCandles = [];
  List<HtfZone> _htfZones = [];
  bool _isLoadingChart = false;
  double _liveMarkPrice = 0.0;
  double _liveLastPrice = 0.0;
  WebSocketChannel? _wsChannel;

  Timer? _clockTimer;
  Timer? _scannerTimer;

  final List<String> _coreSymbols = [
    'BTCUSD', 'ETHUSD', 'SOLUSD', 'BNBUSD', 'XRPUSD', 'ADAUSD',
    'DOGEUSD', 'AVAXUSD', 'LINKUSD', 'DOTUSD', 'SUIUSD', 'APTUSD',
    'ARBUSD', 'OPUSD', 'NEARUSD', 'INJUSD', 'LTCUSD', 'BCHUSD',
    'TONUSD', 'PEPEUSD', 'WIFUSD', 'RENDERUSD', 'FETUSD', 'AAVEUSD',
    'UNIUSD', 'TIAUSD', 'SEIUSD', 'ONDOUSD', 'JUPUSD', 'STXUSD'
  ];

  @override
  void initState() {
    super.initState();
    _updateIstClockAndKillzone();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateIstClockAndKillzone();
    });
    _initializeTerminal();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _scannerTimer?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  Future<void> _initializeTerminal() async {
    await _fetchPerpetualSymbols();
    await _runBatchScanner();
    await _loadLiveChart(_selectedChartSymbol, _selectedResolution);
    _scannerTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_isScanning) _runBatchScanner();
    });
  }

  void _updateIstClockAndKillzone() {
    final nowUtc = DateTime.now().toUtc();
    final istNow = nowUtc.add(const Duration(hours: 5, minutes: 30));

    final hh = istNow.hour.toString().padLeft(2, '0');
    final mm = istNow.minute.toString().padLeft(2, '0');
    final ss = istNow.second.toString().padLeft(2, '0');
    final totalMinutes = istNow.hour * 60 + istNow.minute;

    String title = 'INSTITUTIONAL MACRO ACCUMULATION';
    String sub = 'High-Probability 85%+ Unicorn & FVG Sniper';
    int minutesRemaining = 0;

    if (totalMinutes >= 330 && totalMinutes < 570) {
      title = 'ASIAN KILLZONE SESSION';
      sub = 'Liquidity Build & Range High/Low Sweep';
      minutesRemaining = 570 - totalMinutes;
    } else if (totalMinutes >= 810 && totalMinutes < 990) {
      title = 'LONDON SILVER BULLET';
      sub = 'High-Probability 85%+ Unicorn & FVG Sniper';
      minutesRemaining = 990 - totalMinutes;
    } else if (totalMinutes >= 1080 && totalMinutes < 1170) {
      title = 'NEW YORK OPEN KILLZONE';
      sub = 'CME Open Manipulation & Judas Swing';
      minutesRemaining = 1170 - totalMinutes;
    } else if (totalMinutes >= 1170 && totalMinutes < 1230) {
      title = 'NY AM SILVER BULLET';
      sub = 'High-Probability 85%+ Unicorn & FVG Sniper';
      minutesRemaining = 1230 - totalMinutes;
    } else if (totalMinutes >= 1410 || totalMinutes < 30) {
      title = 'NY PM SILVER BULLET';
      sub = 'Late Session Liquidity Raid & Reversal';
      minutesRemaining = totalMinutes >= 1410 ? (1470 - totalMinutes) : (30 - totalMinutes);
    } else {
      if (totalMinutes < 810) {
        minutesRemaining = 810 - totalMinutes;
      } else if (totalMinutes < 1170) {
        minutesRemaining = 1170 - totalMinutes;
      } else {
        minutesRemaining = 1410 - totalMinutes;
      }
    }

    final remH = (minutesRemaining ~/ 60).toString().padLeft(2, '0');
    final remM = (minutesRemaining % 60).toString().padLeft(2, '0');
    final remS = (59 - istNow.second).toString().padLeft(2, '0');

    if (mounted) {
      setState(() {
        _istTimeStr = '$hh:$mm:$ss IST';
        _killzoneTitle = title;
        _killzoneSubtitle = sub;
        _killzoneCountdown = 'Ends in ${remH}h ${remM}m ${remS}s';
      });
    }
  }

  Future<void> _fetchPerpetualSymbols() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/v2/tickers')).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['result'] ?? [];
        final List<String> perpSymbols = [];

        for (final item in list) {
          final sym = item['symbol']?.toString() ?? '';
          final contractType = item['contract_type']?.toString() ?? '';
          if (contractType == 'perpetual_futures' || (sym.endsWith('USD') && !sym.contains('-'))) {
            perpSymbols.add(sym);
          }
        }

        if (perpSymbols.isNotEmpty && mounted) {
          setState(() {
            _allPerpSymbols = perpSymbols.toList();
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted && _allPerpSymbols.isEmpty) {
      setState(() {
        _allPerpSymbols = List.from(_coreSymbols);
      });
    }
  }

  Future<void> _runBatchScanner() async {
    if (_isScanning) return;

    final List<String> targetList = _scanAll150Plus
        ? (_allPerpSymbols.isNotEmpty ? _allPerpSymbols : _coreSymbols)
        : _coreSymbols;

    setState(() {
      _isScanning = true;
      _scannedCoinsCount = 0;
      _totalCoinsToScan = targetList.length;
    });

    try {
      final Map<String, Map<String, dynamic>> tickerMap = {};
      try {
        final tickerRes = await http.get(Uri.parse('$baseUrl/v2/tickers')).timeout(const Duration(seconds: 8));
        if (tickerRes.statusCode == 200) {
          final List results = jsonDecode(tickerRes.body)['result'] ?? [];
          for (final t in results) {
            final s = t['symbol']?.toString() ?? '';
            if (s.isNotEmpty) tickerMap[s] = Map<String, dynamic>.from(t);
          }
        }
      } catch (_) {}

      double btcChange = _btcChange24h;
      if (tickerMap.containsKey('BTCUSD')) {
        final btcT = tickerMap['BTCUSD']!;
        _btcPrice = double.tryParse(btcT['mark_price']?.toString() ?? '') ??
            double.tryParse(btcT['close']?.toString() ?? '') ??
            _btcPrice;
        final open24 = double.tryParse(btcT['open']?.toString() ?? '') ?? _btcPrice;
        if (open24 > 0) {
          btcChange = ((_btcPrice - open24) / open24) * 100.0;
          _btcChange24h = btcChange;
        }
      }

      int greenAlts = 0;
      int totalCheckedAlts = 0;
      for (final sym in targetList) {
        if (sym == 'BTCUSD') continue;
        final t = tickerMap[sym];
        if (t != null) {
          final c = double.tryParse(t['mark_price']?.toString() ?? '') ?? 0;
          final o = double.tryParse(t['open']?.toString() ?? '') ?? 0;
          if (o > 0) {
            totalCheckedAlts++;
            final chg = ((c - o) / o) * 100.0;
            if (chg > btcChange) greenAlts++;
          }
        }
      }

      final bool btcUp = _btcChange24h >= 0;
      final bool btcDomUp = totalCheckedAlts == 0 ? true : (greenAlts / totalCheckedAlts) < 0.45;

      if (btcUp && !btcDomUp) {
        _currentQuad = 1;
      } else if (btcUp && btcDomUp) {
        _currentQuad = 2;
      } else if (!btcUp && btcDomUp) {
        _currentQuad = 3;
      } else {
        _currentQuad = 4;
      }

      final List<TradeSignal> discoveredSignals = [];
      const int batchSize = 12;

      for (int i = 0; i < targetList.length; i += batchSize) {
        final batch = targetList.skip(i).take(batchSize).toList();

        final batchResults = await Future.wait(batch.map((sym) async {
          try {
            final candles = await _fetchCandlesForSymbol(
              symbol: sym,
              resolution: '15m',
              useMarkPrice: true,
              candleCount: 60,
            );
            if (candles.length >= 20) {
              final ticker = tickerMap[sym];
              return _evaluateIctSignal(sym, candles, ticker);
            }
          } catch (_) {}
          return null;
        }));

        for (final sig in batchResults) {
          if (sig != null) discoveredSignals.add(sig);
        }

        if (mounted) {
          setState(() {
            _scannedCoinsCount = math.min(i + batch.length, targetList.length);
            _signals = List.from(discoveredSignals)..sort((a, b) => b.confidence.compareTo(a.confidence));
          });
        }

        await Future.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<List<Candle>> _fetchCandlesForSymbol({
    required String symbol,
    required String resolution,
    required bool useMarkPrice,
    int candleCount = 100,
  }) async {
    final int nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final int resSeconds = _resolutionToSeconds(resolution);
    final int startSec = nowSec - (resSeconds * candleCount);

    final String querySymbol = useMarkPrice ? 'MARK:$symbol' : symbol;
    final uri = Uri.parse(
      '$baseUrl/v2/history/candles?resolution=$resolution&symbol=$querySymbol&start=$startSec&end=$nowSec',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return [];

    final decoded = jsonDecode(response.body);
    final List rawList = decoded['result'] ?? [];
    final List<Candle> candles = rawList.map((e) => Candle.fromJson(e)).toList();

    candles.sort((a, b) => a.time.compareTo(b.time));
    return candles;
  }

  int _resolutionToSeconds(String res) {
    switch (res) {
      case '1m':
        return 60;
      case '5m':
        return 300;
      case '15m':
        return 900;
      case '1h':
        return 3600;
      case '4h':
        return 14400;
      default:
        return 900;
    }
  }

  TradeSignal? _evaluateIctSignal(
    String symbol,
    List<Candle> candles,
    Map<String, dynamic>? ticker,
  ) {
    final Candle latest = candles.last;
    final Candle prev1 = candles[candles.length - 2];
    final Candle prev2 = candles[candles.length - 3];

    final double markPrice = double.tryParse(ticker?['mark_price']?.toString() ?? '') ?? latest.close;
    final double open24 = double.tryParse(ticker?['open']?.toString() ?? '') ?? candles.first.open;
    final double change24h = open24 > 0 ? ((markPrice - open24) / open24) * 100.0 : 0.0;

    final bool isSmtStrong = change24h > (_btcChange24h + 1.2);

    double recentHigh = candles.sublist(candles.length - 15, candles.length - 1).map((c) => c.high).reduce(math.max);
    double recentLow = candles.sublist(candles.length - 15, candles.length - 1).map((c) => c.low).reduce(math.min);

    final bool bullishFvg = latest.low > prev2.high && prev1.close > prev1.open;
    final bool bearishFvg = latest.high < prev2.low && prev1.close < prev1.open;

    final bool bullishSweep = prev1.low <= recentLow && latest.close > prev1.high;
    final bool bearishSweep = prev1.high >= recentHigh && latest.close < prev1.low;

    final bool bullishBos = latest.close > recentHigh;
    final bool bearishBos = latest.close < recentLow;

    String direction = 'NONE';
    int confidence = 70;
    String strategy = '';
    String pattern = '';
    bool isPullback = false;

    if (bullishFvg || bullishSweep || bullishBos) {
      direction = 'LONG';
      confidence = 76;
      if (bullishFvg && bullishBos) {
        confidence += 10;
        strategy = 'ICT Unicorn Long (OB + FVG)';
        pattern = 'Bullish FVG + BOS';
        isPullback = true;
      } else if (bullishSweep) {
        confidence += 8;
        strategy = 'Liquidity Sweep Reversal';
        pattern = 'SSL Sweep + CHoCH';
        isPullback = true;
      } else {
        strategy = 'Momentum Structure Break';
        pattern = 'HH + Bullish Displacement';
      }
      if (isSmtStrong) confidence += 5;
    } else if (bearishFvg || bearishSweep || bearishBos) {
      direction = 'SHORT';
      confidence = 76;
      if (bearishFvg && bearishBos) {
        confidence += 10;
        strategy = 'ICT Alt Bleed Short (FVG)';
        pattern = 'Bearish FVG + BOS';
        isPullback = true;
      } else if (bearishSweep) {
        confidence += 8;
        strategy = 'BSL Raid Short Setup';
        pattern = 'BSL Sweep + LH';
        isPullback = true;
      } else {
        strategy = 'Macro Breakdown Short';
        pattern = 'LL + Bearish OB';
      }
      if (!isSmtStrong) confidence += 4;
    } else {
      return null;
    }

    // Generate concise actionable brief based on Quadrant state
    String actionBrief = '';
    if (_currentQuad == 1) {
      actionBrief = direction == 'LONG'
          ? 'QUAD 1: Hold Long for full TP (Alt Season active)'
          : 'QUAD 1: Low short probability in Alt Season. Trim or Skip.';
    } else if (_currentQuad == 2) {
      actionBrief = isSmtStrong
          ? 'QUAD 2: SMT Strong. Hold Long, move SL to breakeven.'
          : 'QUAD 2: Lagging alt in Selective SMT. Trim 50% or tighten SL.';
    } else if (_currentQuad == 3) {
      actionBrief = direction == 'SHORT'
          ? 'QUAD 3: Alt Bleed Short active. Hold or scale down to TP.'
          : 'QUAD 3: Danger for Longs! Trim 75% or exit on bounce.';
    } else {
      actionBrief = 'QUAD 4: Defensive rotation. Secure profits and cash out.';
    }

    confidence = confidence.clamp(75, 98);

    final double atr = (recentHigh - recentLow).abs().clamp(markPrice * 0.005, markPrice * 0.05);
    final double sl = direction == 'LONG' ? markPrice - (atr * 0.6) : markPrice + (atr * 0.6);
    final double risk = (markPrice - sl).abs();
    final double tp1 = direction == 'LONG' ? markPrice + (risk * 2.0) : markPrice - (risk * 2.0);
    final double tp2 = direction == 'LONG' ? markPrice + (risk * 3.5) : markPrice - (risk * 3.5);

    final istTime = DateTime.fromMillisecondsSinceEpoch(latest.time * 1000, isUtc: true)
        .add(const Duration(hours: 5, minutes: 30));

    return TradeSignal(
      symbol: symbol,
      direction: direction,
      confidence: confidence,
      strategyName: strategy,
      patternTag: pattern,
      entry: markPrice,
      stopLoss: sl,
      tp1: tp1,
      tp2: tp2,
      markPrice: markPrice,
      change24h: change24h,
      isSmtStrong: isSmtStrong,
      isPullback: isPullback,
      quadrant: _currentQuad,
      actionBrief: actionBrief,
      signalTimeIst: istTime,
    );
  }

  Future<void> _loadLiveChart(String symbol, String resolution) async {
    setState(() {
      _selectedChartSymbol = symbol;
      _selectedResolution = resolution;
      _isLoadingChart = true;
    });

    final candles = await _fetchCandlesForSymbol(
      symbol: symbol,
      resolution: resolution,
      useMarkPrice: _useMarkPriceChart,
      candleCount: 120,
    );

    final htf1h = await _fetchCandlesForSymbol(
      symbol: symbol,
      resolution: '1h',
      useMarkPrice: _useMarkPriceChart,
      candleCount: 50,
    );

    final List<HtfZone> zones = _calculateHtfZones(htf1h);

    if (mounted) {
      setState(() {
        _chartCandles = candles;
        _htf1hCandles = htf1h;
        _htfZones = zones;
        if (candles.isNotEmpty) {
          _liveMarkPrice = candles.last.close;
        }
        _isLoadingChart = false;
      });
    }

    _connectDeltaWebSocket(symbol, resolution);
  }

  List<HtfZone> _calculateHtfZones(List<Candle> htfCandles) {
    final List<HtfZone> zones = [];
    if (htfCandles.length < 10) return zones;

    for (int i = 2; i < htfCandles.length; i++) {
      final prev = htfCandles[i - 1];
      final curr = htfCandles[i];

      if (curr.close > curr.open && (curr.close - curr.open) > (prev.high - prev.low) * 1.2 && prev.close < prev.open) {
        zones.add(HtfZone(top: prev.high, bottom: prev.low, label: '1H Bull OB', isBullish: true));
      }
      if (curr.close < curr.open && (curr.open - curr.close) > (prev.high - prev.low) * 1.2 && prev.close > prev.open) {
        zones.add(HtfZone(top: prev.high, bottom: prev.low, label: '1H Bear OB', isBullish: false));
      }
    }

    final double recent1hHigh = htfCandles.sublist(htfCandles.length - 12, htfCandles.length - 1).map((c) => c.high).reduce(math.max);
    zones.add(HtfZone(top: recent1hHigh, bottom: recent1hHigh, label: '1H BOS Level', isBullish: true));

    return zones;
  }

  void _connectDeltaWebSocket(String symbol, String resolution) {
    _wsChannel?.sink.close();
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      final String candleSymbol = _useMarkPriceChart ? 'MARK:$symbol' : symbol;

      final subPayload = {
        "type": "subscribe",
        "payload": {
          "channels": [
            {
              "name": "candlestick_$resolution",
              "symbols": [candleSymbol]
            },
            {
              "name": "v2/ticker",
              "symbols": [symbol]
            }
          ]
        }
      };

      _wsChannel!.sink.add(jsonEncode(subPayload));

      _wsChannel!.stream.listen((rawMsg) {
        try {
          final Map<String, dynamic> msg = jsonDecode(rawMsg.toString());
          final String type = msg['type']?.toString() ?? '';

          if (type == 'v2/ticker') {
            final mp = double.tryParse(msg['mark_price']?.toString() ?? '');
            final lp = double.tryParse(msg['close']?.toString() ?? '');
            if (mounted) {
              setState(() {
                if (mp != null) _liveMarkPrice = mp;
                if (lp != null) _liveLastPrice = lp;
              });
            }
          } else if (type.startsWith('candlestick_')) {
            final int? startTs = (msg['candle_start_time'] as num?) != null
                ? ((msg['candle_start_time'] as num).toInt() ~/ 1000000)
                : (msg['time'] as num?)?.toInt();
            final double? open = (msg['open'] as num?)?.toDouble();
            final double? high = (msg['high'] as num?)?.toDouble();
            final double? low = (msg['low'] as num?)?.toDouble();
            final double? close = (msg['close'] as num?)?.toDouble();

            if (startTs != null && open != null && high != null && low != null && close != null && mounted) {
              setState(() {
                _liveMarkPrice = close;
                if (_chartCandles.isEmpty) return;
                if (_chartCandles.last.time == startTs) {
                  _chartCandles.last.open = open;
                  _chartCandles.last.high = high;
                  _chartCandles.last.low = low;
                  _chartCandles.last.close = close;
                } else if (startTs > _chartCandles.last.time) {
                  _chartCandles.add(Candle(
                    time: startTs,
                    open: open,
                    high: high,
                    low: low,
                    close: close,
                    volume: (msg['volume'] as num?)?.toDouble() ?? 0.0,
                  ));
                }
              });
            }
          }
        } catch (_) {}
      }, onError: (_) {});
    } catch (_) {}
  }

  List<String> get _dropdownSymbolsList {
    final list = _allPerpSymbols.isNotEmpty ? _allPerpSymbols : _coreSymbols;
    if (_searchQuery.isEmpty) return list;
    return list.where((s) => s.toUpperCase().contains(_searchQuery.toUpperCase())).toList();
  }

  List<TradeSignal> get _filteredSignals {
    return _signals.where((s) {
      if (_searchQuery.isNotEmpty && !s.symbol.toUpperCase().contains(_searchQuery.toUpperCase())) {
        return false;
      }
      if (_selectedFilter == 'ELITE_85') return s.confidence >= 85;
      if (_selectedFilter == 'PULLBACKS') return s.isPullback;
      if (_selectedFilter == 'SHORTS') return s.direction == 'SHORT';
      return s.confidence >= 75;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopHeaderBar(),
            _buildKillzoneBanner(),
            _buildMacroRegimeBanner(),
            Expanded(
              child: _bottomNavIndex == 2 ? _buildLiveChartInspectorTab() : _buildScannerTab(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: (idx) {
          setState(() => _bottomNavIndex = idx);
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0E131A),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: 'Scanner'),
          BottomNavigationBarItem(icon: Icon(Icons.rocket_launch), label: 'Pumps/Dump'),
          BottomNavigationBarItem(icon: Icon(Icons.candlestick_chart), label: 'Live Chart'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'My Trades'),
          BottomNavigationBarItem(icon: Icon(Icons.psychology), label: 'Intel'),
        ],
      ),
    );
  }

  Widget _buildTopHeaderBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF11261F),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF00E676).withOpacity(0.5)),
            ),
            child: Text('\$${_capitalUsd.toInt()}', style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF282111),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withOpacity(0.5)),
            ),
            child: Text('⚡ ${_leverage}x', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _autoAlert = !_autoAlert),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF171C26),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications_active, size: 15, color: _autoAlert ? const Color(0xFF00E676) : Colors.white54),
                  const SizedBox(width: 4),
                  Text(_autoAlert ? 'ON' : 'OFF', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: _isScanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _runBatchScanner,
          ),
        ],
      ),
    );
  }

  Widget _buildKillzoneBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111823),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.circle, size: 10, color: Color(0xFF00E676)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF0D2E22), borderRadius: BorderRadius.circular(6)),
                child: Text('🔥 $_killzoneTitle', style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const Spacer(),
              Text(_istTimeStr, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text('🎯 $_killzoneSubtitle', style: const TextStyle(fontSize: 11, color: Colors.white70), overflow: TextOverflow.ellipsis),
              ),
              Text('⏳ $_killzoneCountdown', style: const TextStyle(fontSize: 11, color: Color(0xFF40C4FF), fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroRegimeBanner() {
    Color quadColor = const Color(0xFF00E676);
    if (_currentQuad == 2) quadColor = Colors.amber;
    if (_currentQuad == 3) quadColor = Colors.redAccent;
    if (_currentQuad == 4) quadColor = Colors.purpleAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0E131D),
        border: Border(top: BorderSide(color: Colors.white12), bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'BTC: \$${_btcPrice.toStringAsFixed(0)} (${_btcChange24h >= 0 ? '+' : ''}${_btcChange24h.toStringAsFixed(2)}%)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Text(
            'BTC.D: ${_btcDominance.toStringAsFixed(2)}%',
            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: quadColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: quadColor),
            ),
            child: Text('QUAD $_currentQuad', style: TextStyle(color: quadColor, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerTab() {
    final list = _filteredSignals;
    final all75Count = _signals.where((s) => s.confidence >= 75).length;
    final elite85Count = _signals.where((s) => s.confidence >= 85).length;
    final pullbackCount = _signals.where((s) => s.isPullback).length;
    final shortCount = _signals.where((s) => s.direction == 'SHORT').length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search across 150+ perp coins...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF141923),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white24)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() => _scanAll150Plus = !_scanAll150Plus);
                  _runBatchScanner();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: _scanAll150Plus ? const Color(0xFF0D2E22) : const Color(0xFF171C26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _scanAll150Plus ? const Color(0xFF00E676) : Colors.white24),
                  ),
                  child: Text(
                    '🌍 All 150+ ${_scanAll150Plus ? 'ON' : 'OFF'} (${_signals.length}/$_scannedCoinsCount)',
                    style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              _buildFilterChip('ALL_75', 'All (>=75%) ($all75Count)'),
              const SizedBox(width: 8),
              _buildFilterChip('ELITE_85', '💎 Elite (>=85%) ($elite85Count)'),
              const SizedBox(width: 8),
              _buildFilterChip('PULLBACKS', '🛡️ Pullbacks ($pullbackCount)'),
              const SizedBox(width: 8),
              _buildFilterChip('SHORTS', '🔻 Shorts ($shortCount)'),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: TextButton.icon(
                    onPressed: _runBatchScanner,
                    icon: const Icon(Icons.refresh, color: Color(0xFF00E676)),
                    label: Text(
                      _isScanning
                          ? 'Scanning Delta Exchange ($_scannedCoinsCount/$_totalCoinsToScan)...'
                          : 'No setups matching filter. Tap to rescan.',
                      style: const TextStyle(color: Color(0xFF00E676)),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) => _buildSignalCard(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final bool selected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      selectedColor: const Color(0xFF1E88E5),
      backgroundColor: const Color(0xFF141923),
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }

  Widget _buildSignalCard(TradeSignal sig) {
    final bool isLong = sig.direction == 'LONG';
    final Color dirColor = isLong ? const Color(0xFF00E676) : Colors.redAccent;
    final String timeStr = '${sig.signalTimeIst.hour.toString().padLeft(2, '0')}:${sig.signalTimeIst.minute.toString().padLeft(2, '0')} IST';

    return Card(
      color: const Color(0xFF131822),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dirColor.withOpacity(0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _bottomNavIndex = 2);
          _loadLiveChart(sig.symbol, _selectedResolution);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(sig.symbol, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: dirColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text('${sig.direction} • ${sig.confidence}%', style: TextStyle(color: dirColor, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                    child: Text('QUAD ${sig.quadrant}', style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                ],
              ),
              const SizedBox(height: 6),
              // Actionable Brief explaining what to do based on Quad shift
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2230),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  sig.actionBrief,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF40C4FF), fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 6),
              Text('${sig.strategyName}  •  Pattern: ${sig.patternTag}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
              const Divider(height: 14, color: Colors.white12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildPriceMetric('ENTRY', sig.entry, Colors.white),
                  _buildPriceMetric('SL', sig.stopLoss, Colors.redAccent),
                  _buildPriceMetric('TP1', sig.tp1, const Color(0xFF00E676)),
                  _buildPriceMetric('TP2', sig.tp2, Colors.cyanAccent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceMetric(String label, double val, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(
          val > 100 ? val.toStringAsFixed(2) : val.toStringAsFixed(4),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  // ==========================================================================
  // LIVE DELTA MARK PRICE CHART TAB
  // ==========================================================================
  Widget _buildLiveChartInspectorTab() {
    TradeSignal? activeSig;
    for (final s in _signals) {
      if (s.symbol == _selectedChartSymbol) {
        activeSig = s;
        break;
      }
    }

    final symbolDropdownOptions = _dropdownSymbolsList;
    final currentDropdownVal = symbolDropdownOptions.contains(_selectedChartSymbol)
        ? _selectedChartSymbol
        : (symbolDropdownOptions.isNotEmpty ? symbolDropdownOptions.first : 'BTCUSD');

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF131822),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: currentDropdownVal,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF171E2C),
                  underline: const SizedBox(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  items: symbolDropdownOptions.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (val) {
                    if (val != null) _loadLiveChart(val, _selectedResolution);
                  },
                ),
              ),
              const SizedBox(width: 8),
              for (final tf in ['15m', '1h', '4h'])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => _loadLiveChart(_selectedChartSymbol, tf),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _selectedResolution == tf ? const Color(0xFF2979FF) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(tf, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() => _useMarkPriceChart = !_useMarkPriceChart);
                  _loadLiveChart(_selectedChartSymbol, _selectedResolution);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _useMarkPriceChart ? Colors.amber.withOpacity(0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _useMarkPriceChart ? Colors.amber : Colors.white24),
                  ),
                  child: Text(
                    _useMarkPriceChart ? 'MARK' : 'LAST',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _useMarkPriceChart ? Colors.amber : Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF0E131A),
          child: Row(
            children: [
              Text(
                'Mark: \$${_liveMarkPrice > 100 ? _liveMarkPrice.toStringAsFixed(2) : _liveMarkPrice.toStringAsFixed(4)}',
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              const Text(
                '⚡ 1H OB & BOS Active',
                style: TextStyle(fontSize: 11, color: Color(0xFF40C4FF), fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingChart
              ? const Center(child: CircularProgressIndicator())
              : _chartCandles.isEmpty
                  ? const Center(child: Text('No candle data available for this pair'))
                  : InteractiveDeltaChart(
                      candles: _chartCandles,
                      htfZones: _htfZones,
                      liveMarkPrice: _liveMarkPrice,
                      activeSignal: activeSig,
                    ),
        ),
      ],
    );
  }
}

class InteractiveDeltaChart extends StatefulWidget {
  final List<Candle> candles;
  final List<HtfZone> htfZones;
  final double liveMarkPrice;
  final TradeSignal? activeSignal;

  const InteractiveDeltaChart({
    super.key,
    required this.candles,
    required this.htfZones,
    required this.liveMarkPrice,
    this.activeSignal,
  });

  @override
  State<InteractiveDeltaChart> createState() => _InteractiveDeltaChartState();
}

class _InteractiveDeltaChartState extends State<InteractiveDeltaChart> {
  int _visibleCount = 55;
  int _scrollOffset = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          final int delta = (details.primaryDelta! / 6).round();
          _scrollOffset = (_scrollOffset + delta).clamp(
            0,
            math.max(0, widget.candles.length - _visibleCount),
          );
        });
      },
      onScaleUpdate: (details) {
        if (details.scale != 1.0) {
          setState(() {
            _visibleCount = (_visibleCount / details.scale).round().clamp(25, 110);
          });
        }
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: DeltaLiveChartPainter(
          candles: widget.candles,
          htfZones: widget.htfZones,
          visibleCount: _visibleCount,
          scrollOffset: _scrollOffset,
          liveMarkPrice: widget.liveMarkPrice,
          activeSignal: widget.activeSignal,
        ),
      ),
    );
  }
}

class DeltaLiveChartPainter extends CustomPainter {
  final List<Candle> candles;
  final List<HtfZone> htfZones;
  final int visibleCount;
  final int scrollOffset;
  final double liveMarkPrice;
  final TradeSignal? activeSignal;

  DeltaLiveChartPainter({
    required this.candles,
    required this.htfZones,
    required this.visibleCount,
    required this.scrollOffset,
    required this.liveMarkPrice,
    this.activeSignal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    const double rightPriceAxisWidth = 66.0;
    final double chartWidth = size.width - rightPriceAxisWidth;
    final double chartHeight = size.height - 24.0;

    final int endIdx = (candles.length - scrollOffset).clamp(1, candles.length);
    final int startIdx = math.max(0, endIdx - visibleCount);
    final List<Candle> visible = candles.sublist(startIdx, endIdx);
    if (visible.isEmpty) return;

    double maxPrice = visible.map((c) => c.high).reduce(math.max);
    double minPrice = visible.map((c) => c.low).reduce(math.min);

    if (activeSignal != null) {
      maxPrice = math.max(maxPrice, math.max(activeSignal!.tp1, activeSignal!.stopLoss));
      minPrice = math.min(minPrice, math.min(activeSignal!.tp1, activeSignal!.stopLoss));
    }

    final double padding = (maxPrice - minPrice) * 0.12;
    maxPrice += padding;
    minPrice -= padding;
    final double priceRange = (maxPrice - minPrice).clamp(1e-8, double.infinity);

    double priceToY(double p) => chartHeight - ((p - minPrice) / priceRange) * chartHeight;

    final Paint gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;

    for (int i = 1; i <= 5; i++) {
      final double y = (chartHeight / 6) * i;
      canvas.drawLine(Offset(0, y), Offset(chartWidth, y), gridPaint);
      final double priceAtY = maxPrice - (i / 6) * priceRange;
      _drawText(
        canvas,
        priceAtY > 100 ? priceAtY.toStringAsFixed(1) : priceAtY.toStringAsFixed(4),
        Offset(chartWidth + 6, y - 6),
        Colors.white54,
        10,
      );
    }

    final double candleSlotWidth = chartWidth / visible.length;
    final double bodyWidth = (candleSlotWidth * 0.68).clamp(2.0, 14.0);

    for (final zone in htfZones) {
      final double topY = priceToY(zone.top);
      final double botY = priceToY(zone.bottom);

      if (zone.label.contains('BOS')) {
        final Paint bosPaint = Paint()
          ..color = Colors.cyanAccent.withOpacity(0.6)
          ..strokeWidth = 1.2;
        canvas.drawLine(Offset(0, topY), Offset(chartWidth, topY), bosPaint);
        _drawText(canvas, zone.label, Offset(10, topY - 14), Colors.cyanAccent, 9, bold: true);
      } else {
        final Rect zoneRect = Rect.fromLTRB(0, topY, chartWidth, botY);
        canvas.drawRect(
          zoneRect,
          Paint()..color = zone.isBullish ? const Color(0xFF00E676).withOpacity(0.06) : Colors.redAccent.withOpacity(0.06),
        );
        _drawText(
          canvas,
          zone.label,
          Offset(12, topY + 2),
          zone.isBullish ? const Color(0xFF00E676).withOpacity(0.8) : Colors.redAccent.withOpacity(0.8),
          9,
          bold: true,
        );
      }
    }

    for (int i = 0; i < visible.length; i++) {
      final c = visible[i];
      final bool isBull = c.close >= c.open;
      final Color color = isBull ? const Color(0xFF00E676) : const Color(0xFFFF5252);

      final double centerX = (i + 0.5) * candleSlotWidth;
      final double highY = priceToY(c.high);
      final double lowY = priceToY(c.low);
      final double openY = priceToY(c.open);
      final double closeY = priceToY(c.close);

      canvas.drawLine(
        Offset(centerX, highY),
        Offset(centerX, lowY),
        Paint()..color = color..strokeWidth = 1.2,
      );

      final double top = math.min(openY, closeY);
      final double bottom = math.max(openY, closeY);
      canvas.drawRect(
        Rect.fromLTRB(centerX - bodyWidth / 2, top, centerX + bodyWidth / 2, math.max(top + 1.5, bottom)),
        Paint()..color = color,
      );
    }

    double? prevSwingHigh;
    double? prevSwingLow;

    for (int i = 2; i < visible.length - 2; i++) {
      final c = visible[i];
      final bool isPivotHigh = c.high >= visible[i - 1].high &&
          c.high >= visible[i - 2].high &&
          c.high >= visible[i + 1].high &&
          c.high >= visible[i + 2].high;

      final bool isPivotLow = c.low <= visible[i - 1].low &&
          c.low <= visible[i - 2].low &&
          c.low <= visible[i + 1].low &&
          c.low <= visible[i + 2].low;

      final double centerX = (i + 0.5) * candleSlotWidth;

      if (isPivotHigh) {
        final String tag = (prevSwingHigh == null || c.high >= prevSwingHigh) ? 'HH' : 'LH';
        prevSwingHigh = c.high;
        final double y = priceToY(c.high) - 14;
        _drawTagBadge(canvas, tag, Offset(centerX - 10, y), tag == 'HH' ? const Color(0xFF00E676) : Colors.orangeAccent);
      } else if (isPivotLow) {
        final String tag = (prevSwingLow == null || c.low >= prevSwingLow) ? 'HL' : 'LL';
        prevSwingLow = c.low;
        final double y = priceToY(c.low) + 4;
        _drawTagBadge(canvas, tag, Offset(centerX - 10, y), tag == 'HL' ? Colors.cyanAccent : Colors.redAccent);
      }
    }

    if (activeSignal != null) {
      _drawHorizontalStrategyLine(canvas, chartWidth, priceToY(activeSignal!.entry), 'ENTRY ${activeSignal!.direction}', Colors.amber);
      _drawHorizontalStrategyLine(canvas, chartWidth, priceToY(activeSignal!.stopLoss), 'SL', Colors.redAccent);
      _drawHorizontalStrategyLine(canvas, chartWidth, priceToY(activeSignal!.tp1), 'TP1 (1:2)', const Color(0xFF00E676));
    }

    if (liveMarkPrice > 0) {
      final double markY = priceToY(liveMarkPrice).clamp(0.0, chartHeight);
      canvas.drawLine(
        Offset(0, markY),
        Offset(chartWidth, markY),
        Paint()..color = Colors.amber..strokeWidth = 1.2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(chartWidth + 2, markY - 9, rightPriceAxisWidth - 4, 18), const Radius.circular(4)),
        Paint()..color = Colors.amber,
      );
      _drawText(
        canvas,
        liveMarkPrice > 100 ? liveMarkPrice.toStringAsFixed(1) : liveMarkPrice.toStringAsFixed(4),
        Offset(chartWidth + 5, markY - 6),
        Colors.black,
        10,
        bold: true,
      );
    }
  }

  void _drawHorizontalStrategyLine(Canvas canvas, double chartWidth, double y, String label, Color color) {
    canvas.drawLine(Offset(0, y), Offset(chartWidth, y), Paint()..color = color.withOpacity(0.85)..strokeWidth = 1.2);
    _drawText(canvas, label, Offset(8, y - 13), color, 10, bold: true);
  }

  void _drawTagBadge(Canvas canvas, String text, Offset pos, Color color) {
    final Rect box = Rect.fromLTWH(pos.dx, pos.dy, 22, 13);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)), Paint()..color = color.withOpacity(0.18));
    _drawText(canvas, text, Offset(pos.dx + 4, pos.dy + 1), color, 9, bold: true);
  }

  void _drawText(Canvas canvas, String text, Offset pos, Color color, double fontSize, {bool bold = false}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant DeltaLiveChartPainter oldDelegate) => true;
}
