import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'delta_ict_service.dart';
import 'ict_chart_screen.dart';
import 'paper_trading_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeltaIctTerminalV9App());
}

class DeltaIctTerminalV9App extends StatelessWidget {
  const DeltaIctTerminalV9App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Delta ICT Terminal v16',
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
      home: const MainTerminalFrame(),
    );
  }
}

class MainTerminalFrame extends StatefulWidget {
  const MainTerminalFrame({super.key});

  @override
  State<MainTerminalFrame> createState() => _MainTerminalFrameState();
}

class _MainTerminalFrameState extends State<MainTerminalFrame> {
  int _selectedTabIndex = 0;
  final DeltaExchangeIctService _service = DeltaExchangeIctService();

  double _walletBalance = 190.0;
  double _leverage = 10.0;
  bool _autoTrade = false;
  String _selectedTf = '15m';

  List<IctSignal> _scannedSignals = [];
  List<Map<String, dynamic>> _allPerps = [];
  MacroRegime? _macro;
  bool _isScanning = true;

  late LiveSessionTelemetry _liveSession;
  Timer? _clockTimer;
  Timer? _autoScanTimer;

  @override
  void initState() {
    super.initState();
    _liveSession = DeltaExchangeIctService.getLiveSessionTelemetry();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _liveSession = DeltaExchangeIctService.getLiveSessionTelemetry();
        });
      }
    });
    _autoScanTimer = Timer.periodic(const Duration(seconds: 35), (_) {
      if (mounted && !_isScanning) {
        _runFullScan(silent: true);
      }
    });
    _runFullScan();
  }

  @override
  void dispose() {
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


  Future<void> _runFullScan({bool silent = false}) async {
    if (!silent) setState(() => _isScanning = true);
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
      for (final p in perps.take(24)) {
        final sym = p['symbol'] as String;
        final candlesLtf = await _service.fetchCandles(sym, resolution: _selectedTf, count: 85);
        final candles1h = await _service.fetchCandles(sym, resolution: '1h', count: 45);
        final candles4h = await _service.fetchCandles(sym, resolution: '4h', count: 35);

        final sig = _service.evaluateIctConfluence(
          symbol: sym,
          productId: p['product_id'] as int,
          markPrice: p['mark_price'] as double,
          fundingRate: p['funding_rate'] as double,
          openInterest: p['open_interest'] as double,
          candles: candlesLtf,
          htfCandles: candles1h,
          htf4hCandles: candles4h,
          btcCandles: btcCandles,
          macro: macro,
          timeframe: _selectedTf,
        );
        if (sig != null) loaded.add(sig);
      }

      loaded.sort((a, b) => b.confluenceScore.compareTo(a.confluenceScore));

      if (!mounted) return;
      setState(() {
        _allPerps = perps;
        _macro = macro;
        _scannedSignals = loaded;
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
                        if (v != null) setState(() => _leverage = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 6-Month Backtest Launcher Button
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
        macro: _macro,
        isLoading: _isScanning,
        service: _service,
        onRefresh: _runFullScan,
        onStateChanged: () => setState(() {}),
      ),
      Tab2PumpsAndDumps(
        signals: _scannedSignals,
        isLoading: _isScanning,
        service: _service,
        onRefresh: _runFullScan,
        onStateChanged: () => setState(() {}),
      ),
      Tab3ManualMultiCoinInspector(
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
                          onChanged: (v) => setState(() => _autoTrade = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Settings Icon Button
              IconButton(
                tooltip: 'Settings & Backtest',
                icon: const Icon(Icons.settings, color: Colors.cyanAccent, size: 21),
                onPressed: _openSettingsModal,
              ),
              IconButton(
                tooltip: 'Refresh Market',
                icon: const Icon(Icons.refresh, color: Colors.white70, size: 21),
                onPressed: _runFullScan,
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
        onTap: (idx) => setState(() => _selectedTabIndex = idx),
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
// TAB 1: ALL COINS SCANNER (Sub-Tabs: All >75%, Elite >85%, Pullback Long/Short)
// ============================================================================
class Tab1Scanner extends StatefulWidget {
  final List<IctSignal> signals;
  final MacroRegime? macro;
  final bool isLoading;
  final DeltaExchangeIctService service;
  final VoidCallback onRefresh;
  final VoidCallback onStateChanged;

  const Tab1Scanner({
    super.key,
    required this.signals,
    required this.macro,
    required this.isLoading,
    required this.service,
    required this.onRefresh,
    required this.onStateChanged,
  });

  @override
  State<Tab1Scanner> createState() => _Tab1ScannerState();
}

class _Tab1ScannerState extends State<Tab1Scanner> {
  String _filter = 'Elite'; // 'All', 'Elite', 'Pullback'

  @override
  Widget build(BuildContext context) {
    final filtered = widget.signals.where((s) {
      if (_filter == 'All') return s.confluenceScore >= 75;
      if (_filter == 'Elite') return s.confluenceScore >= 85;
      if (_filter == 'Pullback') return s.structureHealth.contains('PULLBACK') || s.avwapState.stage.contains('PULLBACK');
      return true;
    }).toList();

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
                Text('BTC: \$${m.btcPrice.toStringAsFixed(0)} (${m.btcChangePct >= 0 ? '+' : ''}${m.btcChangePct.toStringAsFixed(2)}%)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                Text('BTC.D: ${m.btcDominance.toStringAsFixed(2)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.amberAccent)),
                Text(m.altcoinRegime.split(':').first,
                    style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        // Sub-Tabs Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _subTab('All (>75%)', 'All', widget.signals.where((s) => s.confluenceScore >= 75).length),
              const SizedBox(width: 6),
              _subTab('💎 Elite (>85%)', 'Elite', widget.signals.where((s) => s.confluenceScore >= 85).length),
              const SizedBox(width: 6),
              _subTab('🛡️ Pullbacks', 'Pullback', widget.signals.where((s) => s.structureHealth.contains('PULLBACK') || s.avwapState.stage.contains('PULLBACK')).length),
            ],
          ),
        ),
        Expanded(
          child: widget.isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
              : filtered.isEmpty
                  ? Center(
                      child: TextButton.icon(
                        onPressed: widget.onRefresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('No setups matching filter. Tap to rescan.'),
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
        child: Text('$label ($count)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.white70)),
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
                        color: isLong ? const Color(0xFF00E676).withOpacity(0.18) : const Color(0xFFFF3D57).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(sig.direction, style: TextStyle(color: isLong ? const Color(0xFF00E676) : const Color(0xFFFF3D57), fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
                Text('💎 ${sig.confluenceScore}% ICT', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00E676))),
              ],
            ),
            const SizedBox(height: 6),
            Text(sig.pumpDumpHeadline, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
            const SizedBox(height: 4),
            Text(sig.entryAdvice, style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
            const SizedBox(height: 8),
            // Prices Matrix
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
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF00E676)), padding: const EdgeInsets.symmetric(vertical: 8)),
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
                    style: ElevatedButton.styleFrom(backgroundColor: isLong ? const Color(0xFF00E676) : const Color(0xFFFF3D57), padding: const EdgeInsets.symmetric(vertical: 8)),
                    icon: const Icon(Icons.bolt, size: 14, color: Colors.black),
                    label: Text('Trade ${sig.direction}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                    onPressed: () {
                      PaperTradingService.addDemoSlot(sig);
                      widget.onStateChanged();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Executed ${sig.symbol} in My Trades & Demo Lab!'), duration: const Duration(milliseconds: 900)),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $label: $val'), duration: const Duration(milliseconds: 500)));
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
// TAB 2: PERFECT PUMPS & DUMPS (Scans 6-10+% Ready Moves)
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
                  'Live High-Velocity Pump / Dump Scanner (Ready for 6-10+% Move)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: pumpDumps.length,
                  itemBuilder: (ctx, i) {
                    final sig = pumpDumps[i];
                    final isLong = sig.direction == 'LONG';
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
                                Text('${sig.symbol} • ${sig.direction}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: Colors.purple.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                                  child: Text('TARGET +${sig.expectedMovePct.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.purpleAccent)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(sig.pumpDumpHeadline, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
                            const SizedBox(height: 6),
                            Text('Mark Price: \$${sig.markPrice.toStringAsFixed(4)} | Entry Zone: \$${sig.entry.toStringAsFixed(4)}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
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
  final List<Map<String, dynamic>> allPerps;
  final DeltaExchangeIctService service;
  final MacroRegime? macro;
  final VoidCallback onStateChanged;

  const Tab3ManualMultiCoinInspector({
    super.key,
    required this.allPerps,
    required this.service,
    required this.macro,
    required this.onStateChanged,
  });

  @override
  State<Tab3ManualMultiCoinInspector> createState() => _Tab3ManualMultiCoinInspectorState();
}

class _Tab3ManualMultiCoinInspectorState extends State<Tab3ManualMultiCoinInspector> {
  final List<String> _inspectedSymbols = ['BTCUSD', 'ETHUSD'];
  final Map<String, IctSignal> _loadedSignals = {};
  bool _loading = false;
  String _selectedTf = '15m';

  @override
  void initState() {
    super.initState();
    _loadAllSymbols();
  }

  Future<void> _loadAllSymbols() async {
    setState(() => _loading = true);
    for (final sym in _inspectedSymbols) {
      await _loadSingleSymbol(sym);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSingleSymbol(String sym) async {
    try {
      final candlesLtf = await widget.service.fetchCandles(sym, resolution: _selectedTf, count: 90);
      final candles1h = await widget.service.fetchCandles(sym, resolution: '1h', count: 45);
      final candles4h = await widget.service.fetchCandles(sym, resolution: '4h', count: 35);
      final btcCandles = await widget.service.fetchCandles('BTCUSD', resolution: _selectedTf, count: 60);
      final macro = widget.macro ?? await widget.service.fetchMacroRegime(btcCandles: btcCandles, resolution: _selectedTf);

      final mark = candlesLtf.isNotEmpty ? candlesLtf.last.close : 0.0;
      final sig = widget.service.evaluateIctConfluence(
        symbol: sym,
        productId: 1,
        markPrice: mark,
        fundingRate: 0.01,
        openInterest: 25000,
        candles: candlesLtf,
        htfCandles: candles1h,
        htf4hCandles: candles4h,
        btcCandles: btcCandles,
        macro: macro,
        timeframe: _selectedTf,
      );
      if (sig != null) {
        _loadedSignals[sym] = sig;
      }
    } catch (_) {}
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
                  const Text('Add Coin to Inspector Comparison', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search coin (e.g. SOLUSD, XRPUSD, AKEUSD)...',
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
                          trailing: const Icon(Icons.add_circle_outline, color: Color(0xFF00E676)),
                          onTap: () async {
                            Navigator.pop(ctx);
                            if (!_inspectedSymbols.contains(sym)) {
                              setState(() {
                                _inspectedSymbols.add(sym);
                                _loading = true;
                              });
                              await _loadSingleSymbol(sym);
                              setState(() => _loading = false);
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Manual Multi-Coin Inspector (${_inspectedSymbols.length} Active)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Coin', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _openAddCoinModal,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else
          ..._inspectedSymbols.map((sym) {
            final sig = _loadedSignals[sym];
            if (sig == null) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF101724),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF141E2F),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$sym (${sig.direction}) • ${sig.confluenceScore}% ICT', style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                          onPressed: () {
                            setState(() {
                              _inspectedSymbols.remove(sym);
                              _loadedSignals.remove(sym);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  DeltaProInteractiveChart(
                    signal: sig,
                    height: 340,
                    onOpenFullScreen: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => IctChartScreen(signal: sig, service: widget.service)));
                    },
                  ),
                ],
              ),
            );
          }),
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
  const _SixMonthBacktestSheet({required this.service});

  @override
  State<_SixMonthBacktestSheet> createState() => _SixMonthBacktestSheetState();
}

class _SixMonthBacktestSheetState extends State<_SixMonthBacktestSheet> {
  BacktestReport? _report;
  bool _running = true;
  String _timeframe = '15m';

  @override
  void initState() {
    super.initState();
    _startBacktest();
  }

  Future<void> _startBacktest() async {
    setState(() => _running = true);
    final perps = await widget.service.fetchAllPerpetuals();
    final symbols = perps.map((p) => p['symbol'] as String).toList();
    final rep = await widget.service.runSixMonthDeepBacktest(
      symbols: symbols.isNotEmpty ? symbols : ['BTCUSD', 'ETHUSD', 'SOLUSD', 'XRPUSD'],
      timeframe: _timeframe,
    );
    if (!mounted) return;
    setState(() {
      _report = rep;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                const Text('6-Month Historical Backtest Audit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Text('Simulating 12 Major Delta Perps over last 6 months', style: TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 10),
            Row(
              children: ['15m', '1h', '4h'].map((tf) {
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
            const SizedBox(height: 12),
            if (_running)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF00E676)),
                      SizedBox(height: 12),
                      Text('Running 6-Month Deep Backtest across multiple Delta coins...', style: TextStyle(fontSize: 11, color: Colors.white70)),
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
              const Text('TRADE AUDIT LOG (6 MONTHS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54)),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  itemCount: _report!.trades.length,
                  itemBuilder: (ctx, i) {
                    final t = _report!.trades[i];
                    final isWin = t.rMultiple > 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF111724), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${t.symbol} • ${t.direction}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              Text('Entry: \$${t.entryPrice.toStringAsFixed(2)} -> Exit: \$${t.exitPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
                            ],
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
