import 'package:flutter/material.dart';
import 'delta_ict_service.dart';

class PaperTradeSlot {
  final String symbol;
  final String direction;
  final String timeframe;
  final double entryPrice;
  double livePrice;
  final double stopLoss;
  final double tp1;
  final double tp3;
  final double marginUsd;
  final double leverage;
  final DateTime openedAt;

  PaperTradeSlot({
    required this.symbol,
    required this.direction,
    required this.timeframe,
    required this.entryPrice,
    required this.livePrice,
    required this.stopLoss,
    required this.tp1,
    required this.tp3,
    this.marginUsd = 150.0,
    this.leverage = 10.0,
    required this.openedAt,
  });

  double get pnlUsd {
    if (entryPrice <= 0) return 0.0;
    final pct = direction == 'LONG'
        ? (livePrice - entryPrice) / entryPrice
        : (entryPrice - livePrice) / entryPrice;
    return marginUsd * leverage * pct;
  }
}

class PaperTradingService {
  static final List<PaperTradeSlot> activeSlots = [];

  static bool addDemoSlot(IctSignal sig, {String timeframe = '15m'}) {
    if (activeSlots.any((s) => s.symbol == sig.symbol)) return false;
    if (activeSlots.length >= 2) {
      activeSlots.removeLast();
    }
    activeSlots.insert(
      0,
      PaperTradeSlot(
        symbol: sig.symbol,
        direction: sig.direction,
        timeframe: timeframe,
        entryPrice: sig.entry,
        livePrice: sig.markPrice,
        stopLoss: sig.stopLoss,
        tp1: sig.tp1,
        tp3: sig.tp3,
        openedAt: DateTime.now(),
      ),
    );
    return true;
  }

  static double get netPnlUsd {
    double sum = 0.0;
    for (final s in activeSlots) {
      sum += s.pnlUsd;
    }
    return sum;
  }
}

class PaperTradingLabScreen extends StatefulWidget {
  const PaperTradingLabScreen({super.key});

  @override
  State<PaperTradingLabScreen> createState() => _PaperTradingLabScreenState();
}

class _PaperTradingLabScreenState extends State<PaperTradingLabScreen> {
  @override
  Widget build(BuildContext context) {
    final slots = PaperTradingService.activeSlots;
    final netPnl = PaperTradingService.netPnlUsd;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141E2C),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.science, color: Colors.cyanAccent, size: 18),
                    SizedBox(width: 8),
                    Text(
                      '2-Slot Demo Bot & Forward Audit (15m)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white54),
                  onPressed: () => setState(() => PaperTradingService.activeSlots.clear()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1420),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ACTIVE / TOTAL SLOTS: ${slots.length}/2 (\$150 Margin/Slot)',
                  style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                ),
                Text(
                  'NET PnL: ${netPnl >= 0 ? '+' : ''}\$${netPnl.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: netPnl >= 0 ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (slots.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF121926),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'No active Demo Slots running.\nTap "Trade LONG / SHORT" on any >85% Scanner card to deploy a forward-audit slot.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            )
          else
            ...slots.map((s) {
              final pnl = s.pnlUsd;
              final dec = s.entryPrice < 1 ? 4 : 2;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF121926),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s.symbol} (${s.direction} • ${s.timeframe})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Entry: \$${s.entryPrice.toStringAsFixed(dec)} | Live: \$${s.livePrice.toStringAsFixed(dec)} | TP1: \$${s.tp1.toStringAsFixed(dec)}',
                            style: const TextStyle(fontSize: 11, color: Colors.white60),
                          ),
                          Text(
                            'Wide TP3: \$${s.tp3.toStringAsFixed(dec)} | SL: \$${s.stopLoss.toStringAsFixed(dec)}',
                            style: const TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: pnl >= 0 ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
