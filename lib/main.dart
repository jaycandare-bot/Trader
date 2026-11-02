import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'delta_ict_service.dart';
import 'ict_chart_screen.dart';
import 'paper_trading_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PaperTradingService.init();
  await DeltaExchangeIctService.loadPersistentState();
  final prefs = await SharedPreferences.getInstance();
  runApp(DeltaIctTerminalV9App(prefs: prefs));
}

class DeltaIctTerminalV9App extends StatelessWidget {
  final SharedPreferences prefs;
  const DeltaIctTerminalV9App({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Delta ICT Terminal v22',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D14),
        cardColor: const Color(0xFF111724),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF2979FF),
          surface: Color(0xFF111724),
          error: Color(0xFFFF3D57),
        ),
      ),
      home: MainTerminalFrame(prefs: prefs),
    );
  }
}

class MainTerminalFrame extends StatefulWidget {
  final SharedPreferences prefs;
  const MainTerminalFrame({super.key, required this.prefs});

  @override
  State<MainTerminalFrame> createState() => _MainTerminalFrameState();
}

class _MainTerminalFrameState extends State<MainTerminalFrame> with WidgetsBindingObserver {
  // Static memory cache so even if Flutter recreates the widget tree on Android activity resume, state is 100% preserved without refreshing!
  static List<IctSignal> _cachedSignalsMemory = [];
  static List<Map<String, dynamic>> _cachedPerpsMemory = [];
  static MacroRegime? _cachedMacroMemory;

  int _selectedTabIndex = 0;
  final DeltaExchangeIctService _service = DeltaExchangeIctService();

  double _walletBalance = 190.0;
  double _leverage = 10.0;
  bool _autoTrade = false;
  bool _scanAllMarket = false;
  int _scannedProgressCount = 0;
  int _totalTargetScanCount = 0;
  String _selectedTf = '15m';

  List<IctSignal> _scannedSignals = [];
  List<Map<String, dynamic>> _allPerps = [];
  MacroRegime? _macro;
  bool _isScanning = false;

  late LiveSessionTelemetry _liveSession;
  Timer? _clockTimer;
  Timer? _autoScanTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _liveSession = DeltaExchangeIctService.getLiveSessionTelemetry();

    // Synchronous instant restore from SharedPreferences BEFORE first frame!
    _selectedTabIndex = widget.prefs.getInt('saved_tab_index_v22') ?? 0;
    _walletBalance = widget.prefs.getDouble('saved_wallet_balance_v22') ?? 190.0;
    _leverage = widget.prefs.getDouble('saved_leverage_v22') ?? 10.0;
    _autoTrade = widget.prefs.getBool('saved_autotrade_v22') ?? false;
    _scanAllMarket = widget.prefs.getBool('saved_scan_all_market_v22') ?? false;

    if (_cachedSignalsMemory.isNotEmpty) {
      _scannedSignals = List<IctSignal>.from(_cachedSignalsMemory);
      _allPerps = List<Map<String, dynamic>>.from(_cachedPerpsMemory);
      _macro = _cachedMacroMemory;
      _isScanning = false;
      // Refresh silently in background without wiping existing cards
      _runFullScan(silent: true);
    } else {
      _runFullScan(silent: false);
    }

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _liveSession = DeltaExchangeIctService.getLiveSessionTelemetry();
        });
      }
    });
    // Silent background update every 45s — never shows spinner or resets scroll position
    _autoScanTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted && !_isScanning) {
        _runFullScan(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveMainState();
    } else if (state == AppLifecycleState.resumed) {
      // When user reopens app from background, NEVER wipe the UI—just update silently in background!
      if (!_isScanning) {
        _runFullScan(silent: true);
      }
    }
  }

  Future<void> _saveMainState() async {
    try {
      await widget.prefs.setInt('saved_tab_index_v22', _selectedTabIndex);
      await widget.prefs.setDouble('saved_wallet_balance_v22', _walletBalance);
      await widget.prefs.setDouble('saved_leverage_v22', _leverage);
      await widget.prefs.setBool('saved_autotrade_v22', _autoTrade);
      await widget.prefs.setBool('saved_scan_all_market_v22', _scanAllMarket);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _autoScanTimer?.cancel();
    super.dispose();
  }

  Widget _buildGlobalLiveSessionBanner() {
    final s = _liveSession;
    final Color badgeColor = s.activeSessionColorHex == 'GREEN'
        ? const Color(0xFF00E676)
        : (s.activeSessionColorHex == 'AMBER' ? Colors.amberAccent : Colors.cyanAccent);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0D131F),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
          bottom: BorderSide(color: badgeColor.withOpacity(0.35), width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: badgeColor.withOpacity(0.8), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: badgeColor.withOpacity(0.5)),
                ),
                child: Text(
                  s.killzoneBadge,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: badgeColor),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.sessionName,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                s.istTimeStr,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amberAccent, fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '🎯 ${s.po3Expectation}',
                  style: const TextStyle(fontSize: 9.5, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '⏳ ${s.countdownLabel}',
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _toggleScanAllMarket() {
    setState(() {
      _scanAllMarket = !_scanAllMarket;
    });
    _saveMainState();
    _runFullScan(silent: true);
  }

  Future<IctSignal?> _scanSingleCoinOnDemand(String symbol) async {
    try {
      final upper = symbol.trim().toUpperCase();
      Map<String, dynamic>? match;
      for (final p in _allPerps) {
        if ((p['symbol'] as String).toUpperCase() == upper) {
          match = p;
          break;
        }
      }
      final candlesFuts = await Future.wait([
        _service.fetchCandles(upper, resolution: _selectedTf, count: 85),
        _service.fetchCandles(upper, resolution: '1h', count: 45),
        _service.fetchCandles(upper, resolution: '4h', count: 35),
        _service.fetchCandles('BTCUSD', resolution: _selectedTf, count: 60),
      ]);
      final candlesLtf = candlesFuts[0];
      if (candlesLtf.isEmpty) return null;
      final macro = _macro ??
          await _service.fetchMacroRegime(
            btcCandles: candlesFuts[3],
            resolution: _selectedTf,
            allPerps: _allPerps,
          );
      final sig = _service.evaluateIctConfluence(
        symbol: upper,
        productId: (match?['product_id'] as int?) ?? 1,
        markPrice: (match?['mark_price'] as double?) ?? candlesLtf.last.close,
        fundingRate: (match?['funding_rate'] as double?) ?? 0.01,
        openInterest: (match?['open_interest'] as double?) ?? 25000.0,
        candles: candlesLtf,
        htfCandles: candlesFuts[1],
        htf4hCandles: candlesFuts[2],
        btcCandles: candlesFuts[3],
        macro: macro,
        timeframe: _selectedTf,
      );
      if (sig != null && mounted) {
        setState(() {
          _scannedSignals.removeWhere((s) => s.symbol.toUpperCase() == upper);
          _scannedSignals.insert(0, sig);
          _cachedSignalsMemory = List<IctSignal>.from(_scannedSignals);
        });
      }
      return sig;
    } catch (_) {
      return null;
    }
  }

  Future<void> _runFullScan({bool silent = false}) async {
    // Only show full-screen loading indicator if we have zero signals loaded yet
    if (!silent && _scannedSignals.isEmpty) {
      setState(() {
        _isScanning = true;
        _scannedProgressCount = 0;
      });
    }
    try {
      await _service.ensureLocksLoaded();
      final perps = await _service.fetchAllPerpetuals();
      final btcCandles = await _service.fetchCandles('BTCUSD', resolution: _selectedTf, count: 85);
      final macro = await _service.fetchMacroRegime(
        btcCandles: btcCandles,
        resolution: _selectedTf,
        allPerps: perps,
      );

      final List<IctSignal> loaded = [];
      final candidates = _scanAllMarket ? perps : perps.take(64).toList();
      if (mounted) {
        setState(() {
          _allPerps = perps;
          _cachedPerpsMemory = perps;
          _totalTargetScanCount = candidates.length;
        });
      }

      const int batchSize = 10;
      for (int i = 0; i < candidates.length; i += batchSize) {
        final batch = candidates.sublist(
          i,
          (i + batchSize > candidates.length) ? candidates.length : i + batchSize,
        );
        final results = await Future.wait(batch.map((p) async {
          try {
            final sym = p['symbol'] as String;
            final candlesFuts = await Future.wait([
              _service.fetchCandles(sym, resolution: _selectedTf, count: 85),
              _service.fetchCandles(sym, resolution: '1h', count: 45),
              _service.fetchCandles(sym, resolution: '4h', count: 35),
            ]);
            return _service.evaluateIctConfluence(
              symbol: sym,
              productId: p['product_id'] as int,
              markPrice: p['mark_price'] as double,
              fundingRate: p['funding_rate'] as double,
              openInterest: p['open_interest'] as double,
              candles: candlesFuts[0],
              htfCandles: candlesFuts[1],
              htf4hCandles: candlesFuts[2],
              btcCandles: btcCandles,
              macro: macro,
              timeframe: _selectedTf,
            );
          } catch (_) {
            return null;
          }
        }));
        for (final sig in results) {
          if (sig != null) loaded.add(sig);
        }
        if (mounted) {
          loaded.sort((a, b) => b.confluenceScore.compareTo(a.confluenceScore));
          setState(() {
            _scannedProgressCount = (i + batch.length).clamp(0, candidates.length);
            _macro = macro;
            _cachedMacroMemory = macro;
            if (!silent || _scannedSignals.isEmpty) {
              _scannedSignals = List<IctSignal>.from(loaded);
              _cachedSignalsMemory = List<IctSignal>.from(loaded);
            }
            if (loaded.length >= 8) _isScanning = false;
          });
        }
      }

      loaded.sort((a, b) => b.confluenceScore.compareTo(a.confluenceScore));

      if (!mounted) return;
      setState(() {
        _allPerps = perps;
        _macro = macro;
        _scannedSignals = loaded;
        _cachedSignalsMemory = List<IctSignal>.from(loaded);
        _scannedProgressCount = candidates.length;
        _isScanning = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isScanning = false);
    }
  }

  void _openSettingsModal() {
    final keyCtrl = TextEditingController(text: _service.apiKey ?? '');
    final secCtrl = TextEditingController(text: _service.apiSecret ?? '');
    final balCtrl = TextEditingController(text: _walletBalance.toStringAsFixed(0));

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101622),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 18,
            right: 18,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.settings, color: Colors.cyanAccent),
                      SizedBox(width: 8),
                      Text('Terminal Settings & API Config', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              const Text('Delta Exchange India API Credentials', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
              const SizedBox(height: 8),
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'Delta API Key', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: secCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Delta API Secret', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: balCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Capital (\$USD)', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      value: _leverage,
                      dropdownColor: const Color(0xFF101622),
                      decoration: const InputDecoration(labelText: 'Leverage', border: OutlineInputBorder()),
                      items: [5.0, 10.0, 15.0, 20.0, 25.0, 50.0]
                          .map((l) => DropdownMenuItem(value: l, child: Text('${l.toInt()}x')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _leverage = v);
                          _saveMainState();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amberAccent),
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.history_toggle_off, color: Colors.amberAccent),
                label: const Text('Launch 6-Month Multi-Coin Backtest', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openSixMonthBacktestModal();
                },
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.save, color: Colors.black),
                label: const Text('Save & Apply Settings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  await _service.saveCredentials(keyCtrl.text, secCtrl.text);
                  setState(() {
                    _walletBalance = double.tryParse(balCtrl.text) ?? _walletBalance;
                  });
                  await _saveMainState();
                  if (mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSixMonthBacktestModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0E14),
      builder: (ctx) => _SixMonthBacktestSheet(service: _service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      Tab1Scanner(
        signals: _scannedSignals,
        allPerps: _allPerps,
        macro: _macro,
        isLoading: _isScanning,
        scanAllMarket: _scanAllMarket,
        scannedCount: _scannedProgressCount,
        totalTargetCount: _totalTargetScanCount,
        service: _service,
        onRefresh: () => _runFullScan(silent: true),
        onToggleScanAllMarket: _toggleScanAllMarket,
        onScanSingleCoin: _scanSingleCoinOnDemand,
        onStateChanged: () => setState(() {}),
      ),
      Tab2PumpsAndDumps(
        signals: _scannedSignals,
        isLoading: _isScanning,
        service: _service,
        onRefresh: () => _runFullScan(silent: true),
        onStateChanged: () => setState(() {}),
      ),
      Tab3ManualMultiCoinInspector(
        prefs: widget.prefs,
        allPerps: _allPerps,
        service: _service,
        macro: _macro,
        onStateChanged: () => setState(() {}),
      ),
      Tab4MyTrades(service: _service, onOpenSettings: _openSettingsModal),
      Tab5IntelAndUnlocks(service: _service),
    ];

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 4,
            left: 12,
            right: 12,
            bottom: 6,
          ),
          color: const Color(0xFF090D14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF141C2B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet, size: 12, color: Color(0xFF00E676)),
                    const SizedBox(width: 4),
                    Text('\$${_walletBalance.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF00E676))),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF141C2B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, size: 12, color: Colors.amber),
                    Text('${_leverage.toInt()}x', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF141C2B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.smart_toy, size: 12, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(_autoTrade ? 'ON' : 'OFF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _autoTrade ? const Color(0xFF00E676) : Colors.white54)),
                    SizedBox(
                      height: 24,
                      width: 34,
                      child: Transform.scale(
                        scale: 0.62,
                        child: Switch(
                          value: _autoTrade,
                          activeColor: const Color(0xFF00E676),
                          onChanged: (v) {
                            setState(() => _autoTrade = v);
                            _saveMainState();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Settings & Backtest',
                icon: const Icon(Icons.settings, color: Colors.cyanAccent, size: 21),
                onPressed: _openSettingsModal,
              ),
              IconButton(
                tooltip: 'Silent Refresh Market',
                icon: const Icon(Icons.refresh, color: Colors.white70, size: 21),
                onPressed: () => _runFullScan(silent: true),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _buildGlobalLiveSessionBanner(),
          Expanded(
            child: IndexedStack(index: _selectedTabIndex, children: tabs),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        backgroundColor: const Color(0xFF0B101A),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        onTap: (idx) {
          setState(() => _selectedTabIndex = idx);
          _saveMainState();
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: 'Scanner'),
          BottomNavigationBarItem(icon: Icon(Icons.rocket_launch), label: 'Pumps/Dumps'),
          BottomNavigationBarItem(icon: Icon(Icons.compare_arrows), label: 'Inspector'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'My Trades'),
          BottomNavigationBarItem(icon: Icon(Icons.newspaper), label: 'Intel'),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 1: ALL COINS SCANNER (Live Search Bar + Scan All 150+ Toggle + Sub-Tabs)
// ============================================================================
class Tab1Scanner extends StatefulWidget {
  final List<IctSignal> signals;
  final List<Map<String, dynamic>> allPerps;
  final MacroRegime? macro;
  final bool isLoading;
  final bool scanAllMarket;
  final int scannedCount;
  final int totalTargetCount;
  final DeltaExchangeIctService service;
  final VoidCallback onRefresh;
  final VoidCallback onToggleScanAllMarket;
  final Future<IctSignal?> Function(String symbol) onScanSingleCoin;
  final VoidCallback onStateChanged;

  const Tab1Scanner({
    super.key,
    required this.signals,
    required this.allPerps,
    required this.macro,
    required this.isLoading,
    required this.scanAllMarket,
    required this.scannedCount,
    required this.totalTargetCount,
    required this.service,
    required this.onRefresh,
    required this.onToggleScanAllMarket,
    required this.onScanSingleCoin,
    required this.onStateChanged,
  });

  @override
  State<Tab1Scanner> createState() => _Tab1ScannerState();
}

class _Tab1ScannerState extends State<Tab1Scanner> {
  String _filter = 'Elite';
  String _searchQuery = '';
  bool _scanningOnDemand = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchQuery.trim().toUpperCase();

    final filtered = widget.signals.where((s) {
      if (q.isNotEmpty) {
        return s.symbol.toUpperCase().contains(q);
      }
      if (_filter == 'All') return s.confluenceScore >= 75;
      if (_filter == 'Elite') return s.confluenceScore >= 85;
      if (_filter == 'Pullback') {
        return s.structureHealth.contains('PULLBACK') || s.avwapState.stage.contains('PULLBACK');
      }
      return true;
    }).toList();

    final unscannedMatches = q.isEmpty
        ? <Map<String, dynamic>>[]
        : widget.allPerps
            .where((p) {
              final sym = (p['symbol'] as String).toUpperCase();
              final alreadyInList = widget.signals.any((s) => s.symbol.toUpperCase() == sym);
              return sym.contains(q) && !alreadyInList;
            })
            .take(5)
            .toList();

    final m = widget.macro;

    return Column(
      children: [
        if (m != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: const Color(0xFF101724),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'BTC: \$${m.btcPrice.toStringAsFixed(0)} (${m.btcChangePct >= 0 ? '+' : ''}${m.btcChangePct.toStringAsFixed(2)}%)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
                Text(
                  'BTC.D: ${m.btcDominance.toStringAsFixed(2)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.amberAccent),
                ),
                Text(
                  m.altcoinRegime.split(':').first,
                  style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

        // Live Search Bar + "Scan All 150+ Delta Coins" Toggle Button
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      prefixIcon: const Icon(Icons.search, size: 17, color: Colors.cyanAccent),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 15, color: Colors.white54),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      hintText: 'Search coin (e.g. ARIAUSD, SOLUSD)...',
                      hintStyle: const TextStyle(fontSize: 11, color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF131B2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: widget.onToggleScanAllMarket,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: widget.scanAllMarket
                        ? const Color(0xFF00E676).withOpacity(0.2)
                        : const Color(0xFF141C2B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.scanAllMarket ? const Color(0xFF00E676) : Colors.amberAccent.withOpacity(0.6),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.scanAllMarket ? Icons.public : Icons.bolt,
                        size: 15,
                        color: widget.scanAllMarket ? const Color(0xFF00E676) : Colors.amberAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.scanAllMarket
                            ? 'All 150+ ON (${widget.scannedCount}/${widget.totalTargetCount})'
                            : 'Scan All 150+ Coins',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: widget.scanAllMarket ? const Color(0xFF00E676) : Colors.amberAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Sub-Tabs Header + Live Scanned Counter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _subTab('All (>75%)', 'All', widget.signals.where((s) => s.confluenceScore >= 75).length),
                const SizedBox(width: 6),
                _subTab('💎 Elite (>85%)', 'Elite', widget.signals.where((s) => s.confluenceScore >= 85).length),
                const SizedBox(width: 6),
                _subTab(
                  '🛡️ Pullbacks',
                  'Pullback',
                  widget.signals
                      .where((s) => s.structureHealth.contains('PULLBACK') || s.avwapState.stage.contains('PULLBACK'))
                      .length,
                ),
                const SizedBox(width: 10),
                Text(
                  'Scanned: ${widget.scannedCount}/${widget.totalTargetCount > 0 ? widget.totalTargetCount : widget.signals.length}',
                  style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),

        if (unscannedMatches.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF141E30),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚡ Matching Delta Coins Not Yet in Batch (Tap to Instant Scan):',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: unscannedMatches.map((p) {
                    final sym = p['symbol'] as String;
                    final chg = (p['change_24h_pct'] as double?) ?? 0.0;
                    return ActionChip(
                      backgroundColor: const Color(0xFF1B2840),
                      avatar: _scanningOnDemand
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.radar, size: 14, color: Color(0xFF00E676)),
                      label: Text(
                        '$sym (${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(1)}%)',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      onPressed: _scanningOnDemand
                          ? null
                          : () async {
                              setState(() => _scanningOnDemand = true);
                              await widget.onScanSingleCoin(sym);
                              if (mounted) setState(() => _scanningOnDemand = false);
                            },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

        Expanded(
          child: widget.isLoading && widget.signals.isEmpty
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
              : filtered.isEmpty
                  ? Center(
                      child: TextButton.icon(
                        onPressed: widget.onRefresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          q.isNotEmpty
                              ? 'No scanned signal for "$q" yet. Tap a chip above or tap to rescan.'
                              : 'No setups matching filter. Tap to rescan.',
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => _buildSignalCard(filtered[i]),
                    ),
        ),
      ],
    );
  }

  Widget _subTab(String label, String key, int count) {
    final active = _filter == key;
    return InkWell(
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2979FF) : const Color(0xFF141C2B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? Colors.cyanAccent : Colors.white24),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.white70),
        ),
      ),
    );
  }

  Widget _buildSignalCard(IctSignal sig) {
    final isLong = sig.direction == 'LONG';
    final dec = sig.markPrice < 1 ? 5 : (sig.markPrice < 100 ? 3 : 1);

    return Card(
      color: const Color(0xFF111724),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isLong ? const Color(0xFF00E676).withOpacity(0.35) : const Color(0xFFFF3D57).withOpacity(0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(sig.symbol, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isLong
                            ? const Color(0xFF00E676).withOpacity(0.18)
                            : const Color(0xFFFF3D57).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        sig.direction,
                        style: TextStyle(
                          color: isLong ? const Color(0xFF00E676) : const Color(0xFFFF3D57),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '💎 ${sig.confluenceScore}% ICT',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00E676)),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(Icons.schedule, size: 12, color: Colors.amberAccent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '🕒 Signal: ${sig.launchedAgo}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              sig.pumpDumpHeadline,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
            ),
            const SizedBox(height: 3),
            Text(
              sig.reversalFlipBrief,
              style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(sig.entryAdvice, style: const TextStyle(fontSize: 10, color: Colors.white70)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _copyPill('ENTRY', sig.entry, dec, Colors.white),
                _copyPill('SL', sig.stopLoss, dec, const Color(0xFFFF3D57)),
                _copyPill('TP1', sig.tp1, dec, Colors.cyanAccent),
                _copyPill('TP2', sig.tp2, dec, const Color(0xFF00E676)),
                _copyPill('TP3', sig.tp3, dec, const Color(0xFF00E676)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00E676)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.candlestick_chart, size: 14, color: Color(0xFF00E676)),
                    label: const Text('Chart', style: TextStyle(fontSize: 11, color: Color(0xFF00E676))),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => IctChartScreen(signal: sig, service: widget.service)),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLong ? const Color(0xFF00E676) : const Color(0xFFFF3D57),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.bolt, size: 14, color: Colors.black),
                    label: Text(
                      'Trade ${sig.direction}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    onPressed: () {
                      PaperTradingService.addDemoSlot(sig);
                      widget.onStateChanged();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Executed ${sig.symbol} in My Trades & Demo Lab!'),
                          duration: const Duration(milliseconds: 900),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _copyPill(String label, double val, int dec, Color color) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: val.toStringAsFixed(dec)));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied $label: $val'), duration: const Duration(milliseconds: 500)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFF172030), borderRadius: BorderRadius.circular(4)),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 8.5, color: Colors.white54)),
            Text(val.toStringAsFixed(dec), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 2: PERFECT PUMPS & DUMPS (Scans 6-14+% Ready Moves)
// ============================================================================
class Tab2PumpsAndDumps extends StatelessWidget {
  final List<IctSignal> signals;
  final bool isLoading;
  final DeltaExchangeIctService service;
  final VoidCallback onRefresh;
  final VoidCallback onStateChanged;

  const Tab2PumpsAndDumps({
    super.key,
    required this.signals,
    required this.isLoading,
    required this.service,
    required this.onRefresh,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pumpDumps = signals.where((s) => s.isBigPumpOrDump).toList();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withOpacity(0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.bolt, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Live High-Velocity Pump / Dump Scanner (Ready for 6-14+% Move)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading && signals.isEmpty
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: pumpDumps.length,
                  itemBuilder: (ctx, i) {
                    final sig = pumpDumps[i];
                    final isLong = sig.direction == 'LONG';
                    final dec = sig.markPrice < 1 ? 5 : (sig.markPrice < 100 ? 3 : 2);
                    return Card(
                      color: const Color(0xFF111724),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: isLong ? const Color(0xFF00E676) : const Color(0xFFFF3D57), width: 1.2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${sig.symbol} • ${sig.direction} (${sig.confluenceScore}%)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: Colors.purple.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                                  child: Text('TARGET +${sig.expectedMovePct.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.purpleAccent)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('🕒 Signal: ${sig.launchedAgo}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                            const SizedBox(height: 5),
                            Text(sig.pumpDumpHeadline, style: const TextStyle(fontSize: 11.5, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 3),
                            Text(sig.reversalFlipBrief, style: const TextStyle(fontSize: 10.5, color: Colors.white)),
                            const SizedBox(height: 6),
                            Text(
                              'Mark: \$${sig.markPrice.toStringAsFixed(dec)} | Entry: \$${sig.entry.toStringAsFixed(dec)} | SL: \$${sig.stopLoss.toStringAsFixed(dec)} | TP3: \$${sig.tp3.toStringAsFixed(dec)}',
                              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => IctChartScreen(signal: sig, service: service)));
                                    },
                                    child: const Text('Open Delta Chart'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: isLong ? const Color(0xFF00E676) : const Color(0xFFFF3D57)),
                                    onPressed: () {
                                      PaperTradingService.addDemoSlot(sig);
                                      onStateChanged();
                                    },
                                    child: Text('Execute ${sig.direction}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ============================================================================
// TAB 3: MANUAL MULTI-COIN INSPECTOR (Side-by-Side Comparison with + Add Button)
// ============================================================================
class Tab3ManualMultiCoinInspector extends StatefulWidget {
  final SharedPreferences prefs;
  final List<Map<String, dynamic>> allPerps;
  final DeltaExchangeIctService service;
  final MacroRegime? macro;
  final VoidCallback onStateChanged;

  const Tab3ManualMultiCoinInspector({
    super.key,
    required this.prefs,
    required this.allPerps,
    required this.service,
    required this.macro,
    required this.onStateChanged,
  });

  @override
  State<Tab3ManualMultiCoinInspector> createState() => _Tab3ManualMultiCoinInspectorState();
}

class _Tab3ManualMultiCoinInspectorState extends State<Tab3ManualMultiCoinInspector> {
  static const List<String> _allTimeframes = ['5m', '15m', '1h', '4h', '1d'];
  static final Map<String, Map<String, IctSignal>> _cachedMultiTfMemory = {};
  static final Map<String, BacktestReport> _cachedBtMemory = {};

  final List<String> _inspectedSymbols = ['BTCUSD', 'ETHUSD'];

  // symbol -> timeframe -> IctSignal
  final Map<String, Map<String, IctSignal>> _multiTfSignals = {};
  // symbol -> currently selected timeframe on that coin's card
  final Map<String, String> _coinSelectedTf = {};
  // symbol -> latest inline backtest report for that coin
  final Map<String, BacktestReport> _coinBacktests = {};
  final Map<String, String> _coinStrategyFilter = {};
  final Map<String, bool> _coinBtRunning = {};

  bool _loading = false;
  String _globalTf = '15m';

  @override
  void initState() {
    super.initState();
    _restorePersistedInspectorState();
    _multiTfSignals.addAll(_cachedMultiTfMemory);
    _coinBacktests.addAll(_cachedBtMemory);
    _loadAllSymbols(silent: _multiTfSignals.isNotEmpty);
  }

  void _restorePersistedInspectorState() {
    try {
      final savedCoins = widget.prefs.getStringList('inspector_saved_symbols_v22');
      if (savedCoins != null && savedCoins.isNotEmpty) {
        _inspectedSymbols
          ..clear()
          ..addAll(savedCoins);
      }
      final savedGlobalTf = widget.prefs.getString('inspector_global_tf_v22');
      if (savedGlobalTf != null && _allTimeframes.contains(savedGlobalTf)) {
        _globalTf = savedGlobalTf;
      }
      final tfMapRaw = widget.prefs.getString('inspector_coin_tf_map_v22');
      if (tfMapRaw != null && tfMapRaw.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(tfMapRaw);
        decoded.forEach((k, v) => _coinSelectedTf[k] = v.toString());
      }
      final stratMapRaw = widget.prefs.getString('inspector_coin_strat_map_v22');
      if (stratMapRaw != null && stratMapRaw.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(stratMapRaw);
        decoded.forEach((k, v) => _coinStrategyFilter[k] = v.toString());
      }
    } catch (_) {}
  }

  Future<void> _saveInspectorState() async {
    try {
      await widget.prefs.setStringList('inspector_saved_symbols_v22', _inspectedSymbols);
      await widget.prefs.setString('inspector_global_tf_v22', _globalTf);
      await widget.prefs.setString('inspector_coin_tf_map_v22', jsonEncode(_coinSelectedTf));
      await widget.prefs.setString('inspector_coin_strat_map_v22', jsonEncode(_coinStrategyFilter));
    } catch (_) {}
  }

  Future<void> _loadAllSymbols({bool silent = false}) async {
    if (!silent && _multiTfSignals.isEmpty) {
      setState(() => _loading = true);
    }
    for (final sym in List<String>.from(_inspectedSymbols)) {
      _coinSelectedTf.putIfAbsent(sym, () => _globalTf);
      _coinStrategyFilter.putIfAbsent(sym, () => 'ALL');
      await _loadAllTimeframesForSymbol(sym);
      await _runSingleCoinBacktest(sym, silent: silent);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAllTimeframesForSymbol(String sym) async {
    try {
      final candles1h = await widget.service.fetchCandles(sym, resolution: '1h', count: 55);
      final candles4h = await widget.service.fetchCandles(sym, resolution: '4h', count: 45);
      final btcCandles = await widget.service.fetchCandles('BTCUSD', resolution: '15m', count: 60);
      final macro = widget.macro ?? await widget.service.fetchMacroRegime(btcCandles: btcCandles, resolution: '15m');

      final Map<String, IctSignal> tfMap = {};
      for (final tf in _allTimeframes) {
        final candlesTf = (tf == '1h' && candles1h.isNotEmpty)
            ? candles1h
            : ((tf == '4h' && candles4h.isNotEmpty)
                ? candles4h
                : await widget.service.fetchCandles(sym, resolution: tf, count: 85));

        if (candlesTf.isEmpty) continue;
        final mark = candlesTf.last.close;
        final sig = widget.service.evaluateIctConfluence(
          symbol: sym,
          productId: 1,
          markPrice: mark,
          fundingRate: 0.008,
          openInterest: 25000,
          candles: candlesTf,
          htfCandles: candles1h,
          htf4hCandles: candles4h,
          btcCandles: btcCandles,
          macro: macro,
          timeframe: tf,
        );
        if (sig != null) {
          tfMap[tf] = sig;
        }
      }
      if (tfMap.isNotEmpty) {
        _multiTfSignals[sym] = tfMap;
        _cachedMultiTfMemory[sym] = tfMap;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _runSingleCoinBacktest(String sym, {bool silent = false}) async {
    final tf = _coinSelectedTf[sym] ?? _globalTf;
    final strat = _coinStrategyFilter[sym] ?? 'ALL';
    if (mounted && (!silent || !_coinBacktests.containsKey(sym))) {
      setState(() => _coinBtRunning[sym] = true);
    }
    try {
      final rep = await widget.service.runSixMonthDeepBacktest(
        symbols: [sym],
        timeframe: tf,
        minScore: 78,
        strategyFilter: strat,
      );
      _cachedBtMemory[sym] = rep;
      if (mounted) {
        setState(() {
          _coinBacktests[sym] = rep;
          _coinBtRunning[sym] = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _coinBtRunning[sym] = false);
      }
    }
  }

  void _openAddCoinModal() {
    String query = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1522),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final matches = widget.allPerps
              .where((p) => (p['symbol'] as String).toUpperCase().contains(query.toUpperCase()))
              .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.78,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add Coin to Manual Inspector & All-TF Scanner', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search coin (e.g. SOLUSD, XRPUSD, SUIUSD, AKEUSD)...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setModalState(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (c, i) {
                        final p = matches[i];
                        final sym = p['symbol'] as String;
                        final price = p['mark_price'] as double;
                        return ListTile(
                          title: Text('$sym • \$${price.toStringAsFixed(price < 1 ? 4 : 2)}'),
                          subtitle: const Text('Loads 5m, 15m, 1h, 4h, 1d Entry/SL/TPs + 6M Backtest', style: TextStyle(fontSize: 10, color: Colors.white54)),
                          trailing: const Icon(Icons.add_circle_outline, color: Color(0xFF00E676)),
                          onTap: () async {
                            Navigator.pop(ctx);
                            if (!_inspectedSymbols.contains(sym)) {
                              setState(() {
                                _inspectedSymbols.insert(0, sym);
                                _coinSelectedTf[sym] = _globalTf;
                                _coinStrategyFilter[sym] = 'ALL';
                              });
                              await _saveInspectorState();
                              await _loadAllTimeframesForSymbol(sym);
                              await _runSingleCoinBacktest(sym);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openCoinBacktestFullModal(String sym, String initialTf, String initialStrat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0E14),
      builder: (ctx) => _SixMonthBacktestSheet(
        service: widget.service,
        singleSymbol: sym,
        initialTimeframe: initialTf,
        initialStrategy: initialStrat,
      ),
    );
  }

  Widget _copyPricePill(String label, double val, int dec, Color color) {
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
          color: const Color(0xFF172030),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 8.5, color: Colors.white54, fontWeight: FontWeight.bold)),
            const SizedBox(height: 1),
            Text(val.toStringAsFixed(dec), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // Top Header + Add Coin Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Manual Coin Inspector (${_inspectedSymbols.length} Coins)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const Text('All-Timeframe Entry/SL/TPs + Per-Coin Strategy Backtest', style: TextStyle(fontSize: 10, color: Colors.white60)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Rescan All Coins',
              icon: const Icon(Icons.refresh, color: Colors.cyanAccent, size: 20),
              onPressed: () => _loadAllSymbols(silent: true),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Coin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              onPressed: _openAddCoinModal,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Global Timeframe Switcher Bar (Applies to all inspected coins at once)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF111826),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Text('GLOBAL TF: ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
              const SizedBox(width: 4),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _allTimeframes.map((tf) {
                      final active = _globalTf == tf;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _globalTf = tf;
                              for (final sym in _inspectedSymbols) {
                                _coinSelectedTf[sym] = tf;
                              }
                            });
                            _saveInspectorState();
                            for (final sym in _inspectedSymbols) {
                              _runSingleCoinBacktest(sym);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: active ? const Color(0xFF2979FF) : const Color(0xFF172235),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: active ? Colors.cyanAccent : Colors.white24),
                            ),
                            child: Text(
                              tf.toUpperCase(),
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.white70),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (_loading && _multiTfSignals.isEmpty)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))))
        else
          ..._inspectedSymbols.map((sym) {
            final tfMap = _multiTfSignals[sym] ?? {};
            if (tfMap.isEmpty) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF101724), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Loading $sym across 5m, 15m, 1h, 4h, 1d...', style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              );
            }

            final activeTf = _coinSelectedTf[sym] ?? _globalTf;
            final sig = tfMap[activeTf] ?? tfMap.values.first;
            final isLong = sig.direction == 'LONG';
            final dec = sig.markPrice < 1 ? 5 : (sig.markPrice < 100 ? 3 : 1);
            final btReport = _coinBacktests[sym];
            final btRunning = _coinBtRunning[sym] ?? false;
            final activeStrat = _coinStrategyFilter[sym] ?? 'ALL';

            return Container(
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF101724),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isLong ? const Color(0xFF00E676).withOpacity(0.45) : const Color(0xFFFF3D57).withOpacity(0.45),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Coin Title & Remove Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF141E2F),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                    ),
                    child: Row(
                      children: [
                        Text(sym, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isLong ? const Color(0xFF00E676).withOpacity(0.2) : const Color(0xFFFF3D57).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${sig.direction} (${activeTf.toUpperCase()})',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isLong ? const Color(0xFF00E676) : const Color(0xFFFF3D57),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('💎 ${sig.confluenceScore}% ICT', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00E676))),
                        const Spacer(),
                        Text('\$${sig.markPrice.toStringAsFixed(dec)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                        IconButton(
                          icon: const Icon(Icons.close, size: 17, color: Colors.white54),
                          onPressed: () {
                            setState(() {
                              _inspectedSymbols.remove(sym);
                              _multiTfSignals.remove(sym);
                              _cachedMultiTfMemory.remove(sym);
                            });
                            _saveInspectorState();
                          },
                        ),
                      ],
                    ),
                  ),

                  // 2. Per-Coin Timeframe Selector Bar (5m, 15m, 1h, 4h, 1d)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    color: const Color(0xFF0D131F),
                    child: Row(
                      children: [
                        const Text('TIMEFRAME: ', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white54)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _allTimeframes.map((tf) {
                                final tfSig = tfMap[tf];
                                final isSelected = activeTf == tf;
                                final tfLong = tfSig?.direction == 'LONG';
                                return Padding(
                                  padding: const EdgeInsets.only(right: 5),
                                  child: InkWell(
                                    onTap: () {
                                      setState(() => _coinSelectedTf[sym] = tf);
                                      _saveInspectorState();
                                      _runSingleCoinBacktest(sym);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF2979FF) : const Color(0xFF161F30),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.cyanAccent
                                              : (tfSig != null
                                                  ? (tfLong ? const Color(0xFF00E676).withOpacity(0.4) : const Color(0xFFFF3D57).withOpacity(0.4))
                                                  : Colors.white12),
                                        ),
                                      ),
                                      child: Text(
                                        tfSig != null ? '${tf.toUpperCase()} (${tfSig.direction[0]}•${tfSig.confluenceScore}%)' : tf.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? Colors.white : Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Selected Timeframe ENTRY, SL, TP1, TP2, TP3 Matrix + Advice
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '🎯 ${activeTf.toUpperCase()} SNIPER LEVELS (${sig.chartPattern})',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                            ),
                            Text(
                              'R:R 1:${sig.liveRR.toStringAsFixed(1)} • RVOL ${sig.rvol.toStringAsFixed(1)}x',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _copyPricePill('ENTRY', sig.entry, dec, Colors.white),
                            _copyPricePill('STOP LOSS', sig.stopLoss, dec, const Color(0xFFFF3D57)),
                            _copyPricePill('TP1 (1.1R)', sig.tp1, dec, Colors.cyanAccent),
                            _copyPricePill('TP2 (2.2R)', sig.tp2, dec, const Color(0xFF00E676)),
                            _copyPricePill('TP3 (WIDE)', sig.tp3, dec, const Color(0xFF00E676)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('🕒 Signal: ${sig.launchedAgo}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                        const SizedBox(height: 3),
                        Text(sig.reversalFlipBrief, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(sig.entryAdvice, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: sig.activeConfluences.map((c) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF172234),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Text('✓ $c', style: const TextStyle(fontSize: 9, color: Colors.white70)),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),

                  // 4. All-Timeframe Entry, SL & TP Matrix Table for this Coin (5m, 15m, 1h, 4h, 1d)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C121D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📊 ALL-TIMEFRAME ENTRY / SL / TP MATRIX FOR $sym',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowHeight: 24,
                            dataRowMinHeight: 26,
                            dataRowMaxHeight: 28,
                            columnSpacing: 12,
                            horizontalMargin: 4,
                            columns: const [
                              DataColumn(label: Text('TF', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white54))),
                              DataColumn(label: Text('BIAS', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white54))),
                              DataColumn(label: Text('ENTRY', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white))),
                              DataColumn(label: Text('SL', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFFF3D57)))),
                              DataColumn(label: Text('TP1', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.cyanAccent))),
                              DataColumn(label: Text('TP2', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF00E676)))),
                              DataColumn(label: Text('TP3', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF00E676)))),
                            ],
                            rows: _allTimeframes.where((tf) => tfMap.containsKey(tf)).map((tf) {
                              final s = tfMap[tf]!;
                              final d = s.markPrice < 1 ? 5 : (s.markPrice < 100 ? 3 : 1);
                              final l = s.direction == 'LONG';
                              return DataRow(
                                selected: tf == activeTf,
                                onSelectChanged: (_) {
                                  setState(() => _coinSelectedTf[sym] = tf);
                                  _runSingleCoinBacktest(sym);
                                },
                                cells: [
                                  DataCell(Text(tf.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                  DataCell(Text('${s.direction} (${s.confluenceScore}%)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: l ? const Color(0xFF00E676) : const Color(0xFFFF3D57)))),
                                  DataCell(Text(s.entry.toStringAsFixed(d), style: const TextStyle(fontSize: 10))),
                                  DataCell(Text(s.stopLoss.toStringAsFixed(d), style: const TextStyle(fontSize: 10, color: Color(0xFFFF3D57)))),
                                  DataCell(Text(s.tp1.toStringAsFixed(d), style: const TextStyle(fontSize: 10, color: Colors.cyanAccent))),
                                  DataCell(Text(s.tp2.toStringAsFixed(d), style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)))),
                                  DataCell(Text(s.tp3.toStringAsFixed(d), style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)))),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 5. Interactive Delta Exchange Chart for Selected Timeframe
                  DeltaProInteractiveChart(
                    signal: sig,
                    height: 340,
                    onOpenFullScreen: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => IctChartScreen(signal: sig, service: widget.service)));
                    },
                  ),

                  // 6. Embedded Per-Coin Strategy Backtest Lab (6 Months Back to Till Date)
                  Container(
                    margin: const EdgeInsets.all(10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C121D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amberAccent.withOpacity(0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '🧪 6-MONTH STRATEGY BACKTEST: $sym (${activeTf.toUpperCase()})',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), minimumSize: Size.zero),
                              icon: const Icon(Icons.open_in_full, size: 13, color: Colors.cyanAccent),
                              label: const Text('Full Audit Log', style: TextStyle(fontSize: 10, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                              onPressed: () => _openCoinBacktestFullModal(sym, activeTf, activeStrat),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Strategy Filter Pills for this coin
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              {'key': 'ALL', 'label': 'All Pro ICT'},
                              {'key': 'UNICORN', 'label': 'Unicorn (BB+FVG)'},
                              {'key': 'AVWAP', 'label': 'PhenLabs AVWAP'},
                              {'key': 'PO3', 'label': 'PO3 Asian Sweep'},
                              {'key': 'CVD', 'label': 'CVD Absorption'},
                            ].map((st) {
                              final isSt = activeStrat == st['key'];
                              return Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: InkWell(
                                  onTap: () {
                                    setState(() => _coinStrategyFilter[sym] = st['key']!);
                                    _saveInspectorState();
                                    _runSingleCoinBacktest(sym);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSt ? Colors.amber.withOpacity(0.22) : const Color(0xFF151E2E),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: isSt ? Colors.amberAccent : Colors.white12),
                                    ),
                                    child: Text(
                                      st['label']!,
                                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: isSt ? Colors.amberAccent : Colors.white70),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (btRunning)
                          const Padding(
                            padding: EdgeInsets.all(10),
                            child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent))),
                          )
                        else if (btReport != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _btMiniStat('WIN RATE', '${btReport.winRatePct.toStringAsFixed(1)}%', const Color(0xFF00E676)),
                              _btMiniStat('NET R', '+${btReport.netR.toStringAsFixed(1)}R', const Color(0xFF00E676)),
                              _btMiniStat('PROFIT FACTOR', btReport.profitFactor.toStringAsFixed(2), Colors.cyanAccent),
                              _btMiniStat('TRADES', '${btReport.totalTrades} (${btReport.wins}W/${btReport.losses}L)', Colors.white),
                            ],
                          ),
                          if (btReport.trades.isNotEmpty) ...[
                            const Divider(color: Colors.white12, height: 14),
                            const Text('Recent Backtest Executions:', style: TextStyle(fontSize: 9.5, color: Colors.white54, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            ...btReport.trades.take(3).map((t) {
                              final win = t.rMultiple > 0;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${t.direction} • ${t.confluences.first} (\$${t.entryPrice.toStringAsFixed(dec)} -> \$${t.exitPrice.toStringAsFixed(dec)})',
                                        style: const TextStyle(fontSize: 9.5, color: Colors.white70),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      t.outcome,
                                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: win ? const Color(0xFF00E676) : const Color(0xFFFF3D57)),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ],
                    ),
                  ),

                  // 7. Quick Action Buttons (Execute Trade / Open Full Backtest / Full Chart)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amberAccent)),
                            icon: const Icon(Icons.history_toggle_off, size: 15, color: Colors.amberAccent),
                            label: Text('Backtest $sym', style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                            onPressed: () => _openCoinBacktestFullModal(sym, activeTf, activeStrat),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: isLong ? const Color(0xFF00E676) : const Color(0xFFFF3D57)),
                            icon: const Icon(Icons.bolt, size: 15, color: Colors.black),
                            label: Text('Trade ${sig.direction}', style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              PaperTradingService.addDemoSlot(sig);
                              widget.onStateChanged();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Executed $sym (${activeTf.toUpperCase()}) in My Trades!'), duration: const Duration(milliseconds: 900)),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _btMiniStat(String label, String val, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 8.5, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}


// ============================================================================
// TAB 4: MY TRADES (Live Positions from Delta API + Paper Trading Forward Audit)
// ============================================================================
class Tab4MyTrades extends StatefulWidget {
  final DeltaExchangeIctService service;
  final VoidCallback onOpenSettings;

  const Tab4MyTrades({super.key, required this.service, required this.onOpenSettings});

  @override
  State<Tab4MyTrades> createState() => _Tab4MyTradesState();
}

class _Tab4MyTradesState extends State<Tab4MyTrades> {
  List<Map<String, dynamic>> _livePositions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchPositions();
  }

  Future<void> _fetchPositions() async {
    setState(() => _loading = true);
    final pos = await widget.service.fetchOpenPositions();
    if (!mounted) return;
    setState(() {
      _livePositions = pos;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final demoSlots = PaperTradingService.activeSlots;
    final demoPnl = PaperTradingService.netPnlUsd;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('My Trades • Live Delta & Demo Bot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Row(
              children: [
                IconButton(icon: const Icon(Icons.settings, color: Colors.cyanAccent), onPressed: widget.onOpenSettings),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchPositions),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF111724), borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metric('Open Live', '${_livePositions.length}', Colors.white),
              _metric('Demo Slots', '${demoSlots.length}/2', Colors.cyanAccent),
              _metric('Demo PnL', '${demoPnl >= 0 ? '+' : ''}\$${demoPnl.toStringAsFixed(2)}', demoPnl >= 0 ? const Color(0xFF00E676) : const Color(0xFFFF3D57)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text('🟢 LIVE MARGINED POSITIONS (DELTA EXCHANGE API)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF00E676))),
        const SizedBox(height: 8),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        else if (_livePositions.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF111724), borderRadius: BorderRadius.circular(8)),
            child: const Center(
              child: Text(
                'No open margined positions detected on Delta Exchange.\n(Verify API Key & Secret in Settings icon if you have active positions)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          )
        else
          ..._livePositions.map((p) {
            final isLong = (p['is_long'] as bool?) ?? true;
            final pnl = (p['unrealized_pnl'] as double?) ?? 0.0;
            return Card(
              color: const Color(0xFF111724),
              child: ListTile(
                title: Text('${p['symbol']} • ${isLong ? 'LONG' : 'SHORT'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Entry: \$${p['entry_price']} | Mark: \$${p['mark_price']}'),
                trailing: Text('${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: pnl >= 0 ? const Color(0xFF00E676) : const Color(0xFFFF3D57))),
              ),
            );
          }),
        const SizedBox(height: 14),
        const Text('🧪 2-SLOT FORWARD DEMO AUDIT', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
        const SizedBox(height: 8),
        if (demoSlots.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF111724), borderRadius: BorderRadius.circular(8)),
            child: const Center(child: Text('No demo slots running. Tap "Trade" on Tab 1 or Tab 2 to execute.', style: TextStyle(color: Colors.white54, fontSize: 11))),
          )
        else
          ...demoSlots.map((s) => Card(
                color: const Color(0xFF111724),
                child: ListTile(
                  title: Text('${s.symbol} • ${s.direction}'),
                  subtitle: Text('Entry: \$${s.entryPrice.toStringAsFixed(4)} | Live: \$${s.livePrice.toStringAsFixed(4)}'),
                  trailing: Text('${s.pnlUsd >= 0 ? '+' : ''}\$${s.pnlUsd.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: s.pnlUsd >= 0 ? const Color(0xFF00E676) : const Color(0xFFFF3D57))),
                ),
              )),
      ],
    );
  }

  Widget _metric(String label, String val, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

// ============================================================================
// TAB 5: INTEL, TOKEN UNLOCKS & LIVE CATALYSTS
// ============================================================================
class Tab5IntelAndUnlocks extends StatelessWidget {
  final DeltaExchangeIctService service;
  const Tab5IntelAndUnlocks({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final unlocks = service.getLiveTokenUnlocks();
    final news = service.getLiveMarketNews();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Crypto Intelligence, Unlocks & News', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('🔓 UPCOMING TOKEN UNLOCKS (DUMP IMPACT SCHEDULE)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
        const SizedBox(height: 8),
        ...unlocks.map((u) => Card(
              color: const Color(0xFF111724),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: Colors.amber.withOpacity(0.2), child: const Icon(Icons.lock_open, color: Colors.amber, size: 18)),
                title: Text('${u.symbol} • ${u.date}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('Unlock: \$${(u.unlockAmountUsd / 1000000).toStringAsFixed(1)}M (${u.pctOfCirculating}% of Supply)\n${u.dumpImpact}', style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
              ),
            )),
        const SizedBox(height: 16),
        const Text('📰 LIVE DERIVATIVES & MACRO NEWS FEED', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
        const SizedBox(height: 8),
        ...news.map((n) => Card(
              color: const Color(0xFF111724),
              child: ListTile(
                title: Text(n.title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                subtitle: Text('${n.source} • ${n.timeAgo}', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: n.sentiment == 'BULLISH' ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                  child: Text(n.sentiment, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: n.sentiment == 'BULLISH' ? const Color(0xFF00E676) : Colors.orangeAccent)),
                ),
              ),
            )),
      ],
    );
  }
}

// ============================================================================
// 6-MONTH MULTI-COIN COMPREHENSIVE BACKTEST SHEET
// ============================================================================
class _SixMonthBacktestSheet extends StatefulWidget {
  final DeltaExchangeIctService service;
  final String? singleSymbol;
  final String initialTimeframe;
  final String initialStrategy;

  const _SixMonthBacktestSheet({
    required this.service,
    this.singleSymbol,
    this.initialTimeframe = '15m',
    this.initialStrategy = 'ALL',
  });

  @override
  State<_SixMonthBacktestSheet> createState() => _SixMonthBacktestSheetState();
}

class _SixMonthBacktestSheetState extends State<_SixMonthBacktestSheet> {
  BacktestReport? _report;
  bool _running = true;
  late String _timeframe;
  late String _strategy;

  @override
  void initState() {
    super.initState();
    _timeframe = widget.initialTimeframe;
    _strategy = widget.initialStrategy;
    _startBacktest();
  }

  Future<void> _startBacktest() async {
    setState(() => _running = true);
    List<String> symbols;
    if (widget.singleSymbol != null && widget.singleSymbol!.isNotEmpty) {
      symbols = [widget.singleSymbol!];
    } else {
      final perps = await widget.service.fetchAllPerpetuals();
      symbols = perps.map((p) => p['symbol'] as String).toList();
      if (symbols.isEmpty) symbols = ['BTCUSD', 'ETHUSD', 'SOLUSD', 'XRPUSD'];
    }

    final rep = await widget.service.runSixMonthDeepBacktest(
      symbols: symbols,
      timeframe: _timeframe,
      strategyFilter: _strategy,
    );
    if (!mounted) return;
    setState(() {
      _report = rep;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSingle = widget.singleSymbol != null;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    isSingle
                        ? '6-Month Strategy Backtest: ${widget.singleSymbol}'
                        : '6-Month Historical Backtest Audit (All Coins)',
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Text(
              isSingle
                  ? 'Testing ${widget.singleSymbol} from 6 months back to till date across all timeframes & ICT strategies'
                  : 'Simulating 12 Major Delta Perps over last 6 months',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(height: 10),
            // Timeframe Selector (5m, 15m, 1h, 4h, 1d)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['5m', '15m', '1h', '4h', '1d'].map((tf) {
                  final active = _timeframe == tf;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(tf.toUpperCase()),
                      selected: active,
                      onSelected: (_) {
                        setState(() => _timeframe = tf);
                        _startBacktest();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),
            // Strategy Filter Selector
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  {'k': 'ALL', 'n': 'All Strategies'},
                  {'k': 'UNICORN', 'n': 'Unicorn (BB+FVG)'},
                  {'k': 'AVWAP', 'n': 'PhenLabs AVWAP'},
                  {'k': 'PO3', 'n': 'PO3 Asian Sweep'},
                  {'k': 'CVD', 'n': 'CVD Absorption'},
                ].map((s) {
                  final active = _strategy == s['k'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s['n']!, style: const TextStyle(fontSize: 10.5)),
                      selected: active,
                      onSelected: (_) {
                        setState(() => _strategy = s['k']!);
                        _startBacktest();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            if (_running)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF00E676)),
                      const SizedBox(height: 12),
                      Text(
                        isSingle
                            ? 'Backtesting ${widget.singleSymbol} ($_timeframe • $_strategy) over last 6 months...'
                            : 'Running 6-Month Deep Backtest across multiple Delta coins...',
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              )
            else if (_report != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF111724), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('WIN RATE', '${_report!.winRatePct.toStringAsFixed(1)}%', const Color(0xFF00E676)),
                    _stat('NET RETURN', '+${_report!.netR.toStringAsFixed(1)}R', const Color(0xFF00E676)),
                    _stat('PROFIT FACTOR', _report!.profitFactor.toStringAsFixed(2), Colors.cyanAccent),
                    _stat('TOTAL TRADES', '${_report!.totalTrades} (${_report!.wins}W/${_report!.losses}L)', Colors.white),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'TRADE AUDIT LOG (${_report!.periodDescription})',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amberAccent),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  itemCount: _report!.trades.length,
                  itemBuilder: (ctx, i) {
                    final t = _report!.trades[i];
                    final isWin = t.rMultiple > 0;
                    final dec = t.entryPrice < 1 ? 5 : (t.entryPrice < 100 ? 3 : 2);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF111724), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${t.symbol} • ${t.direction} (${t.confluences.first})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                                const SizedBox(height: 2),
                                Text('Entry: \$${t.entryPrice.toStringAsFixed(dec)} -> Exit: \$${t.exitPrice.toStringAsFixed(dec)}', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                                if (t.confluences.length > 1)
                                  Text(t.confluences[1], style: const TextStyle(fontSize: 9.5, color: Colors.white54)),
                              ],
                            ),
                          ),
                          Text(t.outcome, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isWin ? const Color(0xFF00E676) : const Color(0xFFFF3D57))),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String val, Color c) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: c)),
      ],
    );
  }
}
