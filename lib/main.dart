
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const SmartAlertApp());

class SmartAlertApp extends StatelessWidget {
  const SmartAlertApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Smart Alert Hunter',
    theme: ThemeData(
      colorSchemeSeed: Colors.teal,
      useMaterial3: true,
    ),
    home: const ScannerPage(),
  );
}

class Coin {
  final String symbol;
  final double price;
  final double volume;

  Coin(this.symbol, this.price, this.volume);
}

class Candle {
  final double open;
  final double high;
  final double low;
  final double close;

  Candle(this.open, this.high, this.low, this.close);
}

class ObZone {
  final double low;
  final double high;
  final double distance;
  final bool breaker;

  ObZone(
    this.low,
    this.high,
    this.distance, {
    this.breaker = false,
  });
}

// ICT Bullish Order Block داخلي
class _IctOb {
  final double top;
  final double bottom;
  bool breaker;

  _IctOb(this.top, this.bottom)
      : breaker = false;
}

class CoinAnalysisResult {
  final String symbol;
  final ObZone? dailyZone;
  final ObZone? fourHourZone;

  CoinAnalysisResult(
    this.symbol,
    this.dailyZone,
    this.fourHourZone,
  );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool loading = false;
  bool analyzing = false;

  String status =
      'اضغط على تحديث لجلب أزواج Binance Spot';

  List<Coin> coins = [];

  final Map<String, ObZone?> obZones1D = {};
  final Map<String, ObZone?> obZones4H = {};

  final Set<String> analyzedSymbols = {};

  // إعدادات ICT الأصلية للـ OB
  static const int swingLookback = 10;
  static const int candleLimit = 1000;

  // فحص السوق - الشروط الأصلية دون تغيير
  Future<void> scan() async {
    setState(() {
      loading = true;
      obZones1D.clear();
      obZones4H.clear();
      analyzedSymbols.clear();
      status = 'جارٍ الاتصال بـ Binance...';
    });

    try {
      final response = await http.get(
        Uri.parse(
          'https://api.binance.com/api/v3/ticker/24hr',
        ),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception(
          'استجابة Binance: ${response.statusCode}',
        );
      }

      final data =
          jsonDecode(response.body) as List<dynamic>;

      final found = <Coin>[];

      for (final item in data) {
        final row = item as Map<String, dynamic>;
        final symbol = row['symbol']?.toString() ?? '';

        if (!symbol.endsWith('USDT')) continue;

        final price = double.tryParse(
          row['lastPrice']?.toString() ?? '',
        ) ?? 0;

        final volume = double.tryParse(
          row['quoteVolume']?.toString() ?? '',
        ) ?? 0;

        if (price > 0 &&
            price <= 1 &&
            volume >= 500000) {
          found.add(
            Coin(symbol, price, volume),
          );
        }
      }

      found.sort(
        (a, b) => b.volume.compareTo(a.volume),
      );

      if (!mounted) return;

      setState(() {
        coins = found;
        status =
            'تم الفحص: ${found.length} زوجاً يطابق شروط السعر والسيولة';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => status = 'تعذر الفحص: $e');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  // =====================================================
  // ICT CONCEPTS - LUXALGO
  // Bullish Order Block Algorithm
  // Swing Lookback = 10
  // Use Candle Body = true
  // Show Last Bullish OB = 1
  // =====================================================

  ObZone? findBullishOb(
    List<Candle> candles,
    double currentPrice,
  ) {
    if (candles.length < swingLookback + 5) {
      return null;
    }

    int os = 0;

    double? swingTop;
    int? swingTopIndex;
    bool swingTopCrossed = false;

    // ترتيب المناطق: الأحدث أولاً
    final bullishObs = <_IctOb>[];

    for (int i = 0; i < candles.length; i++) {

      // -----------------------------------------------
      // 1. Swing High / Swing Low
      // مطابق لمنطق swings(length) في ICT
      // -----------------------------------------------

      if (i >= swingLookback) {
        final pivotIndex = i - swingLookback;
        final windowStart = i - swingLookback + 1;

        double upper = candles[windowStart].high;
        double lower = candles[windowStart].low;

        for (int j = windowStart + 1; j <= i; j++) {
          upper = math.max(upper, candles[j].high);
          lower = math.min(lower, candles[j].low);
        }

        int newOs = os;

        if (candles[pivotIndex].high > upper) {
          newOs = 0;
        } else if (candles[pivotIndex].low < lower) {
          newOs = 1;
        }

        // تكوين Swing High جديد
        if (newOs == 0 && os != 0) {
          swingTop = candles[pivotIndex].high;
          swingTopIndex = pivotIndex;
          swingTopCrossed = false;
        }

        os = newOs;
      }

      final candle = candles[i];

      // -----------------------------------------------
      // 2. Bullish BOS
      // إغلاق السعر فوق Swing High
      // -----------------------------------------------

      if (swingTop != null &&
          swingTopIndex != null &&
          !swingTopCrossed &&
          candle.close > swingTop) {

        swingTopCrossed = true;

        // ---------------------------------------------
        // 3. تحديد شمعة Order Block
        // Use Candle Body = true
        //
        // البحث عن أدنى جسم شمعة من آخر شمعة
        // حتى شمعة Swing High، دون تضمينها
        // ---------------------------------------------

        final previousIndex = i - 1;

        double minimumBody = math.min(
          candles[previousIndex].open,
          candles[previousIndex].close,
        );

        double maximumBody = math.max(
          candles[previousIndex].open,
          candles[previousIndex].close,
        );

        for (int j = previousIndex;
            j > swingTopIndex;
            j--) {

          final bodyLow = math.min(
            candles[j].open,
            candles[j].close,
          );

          final bodyHigh = math.max(
            candles[j].open,
            candles[j].close,
          );

          if (bodyLow <= minimumBody) {
            minimumBody = bodyLow;
            maximumBody = bodyHigh;
          }
        }

        // إضافة أحدث OB في بداية القائمة
        bullishObs.insert(
          0,
          _IctOb(
            maximumBody,
            minimumBody,
          ),
        );
      }

      // -----------------------------------------------
      // 4. إبطال OB وتحويلها إلى Breaker
      // مطابق لمنطق LuxAlgo
      // -----------------------------------------------

      for (int j = bullishObs.length - 1;
          j >= 0;
          j--) {

        final element = bullishObs[j];

        if (!element.breaker) {

          // اختراق جسم الشمعة للحد السفلي
          final bodyLow = math.min(
            candle.close,
            candle.open,
          );

          if (bodyLow < element.bottom) {
            element.breaker = true;
          }

        } else {

          // إزالة Breaker عند الإغلاق فوق حدها العلوي
          if (candle.close > element.top) {
            bullishObs.removeAt(j);
          }
        }
      }
    }

    // -----------------------------------------------
    // 5. Show Last Bullish OB = 1
    // اعتماد أحدث منطقة فقط
    // -----------------------------------------------

    if (bullishObs.isEmpty) {
      return null;
    }

    final latest = bullishObs.first;

    // المحافظة على شرط التطبيق:
    // المنطقة يجب أن تكون أسفل السعر الحالي
    if (currentPrice <= latest.top) {
      return null;
    }

    final distance =
        ((currentPrice - latest.top) / currentPrice) * 100;

    return ObZone(
      latest.bottom,
      latest.top,
      distance,
      breaker: latest.breaker,
    );
  }

  // =====================================================
  // تحميل الشموع وتحليل الفريم
  // =====================================================

  Future<ObZone?> analyzeCoin(
    Coin coin,
    String interval,
  ) async {
    try {
      final uri = Uri.https(
        'api.binance.com',
        '/api/v3/klines',
        {
          'symbol': coin.symbol,
          'interval': interval,
          'limit': '$candleLimit',
        },
      );

      final response = await http.get(uri).timeout(
        const Duration(seconds: 20),
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as List;

      final candles = data.map((row) {
        return Candle(
          double.parse(row[1].toString()),
          double.parse(row[2].toString()),
          double.parse(row[3].toString()),
          double.parse(row[4].toString()),
        );
      }).toList();

      return findBullishOb(
        candles,
        coin.price,
      );

    } catch (_) {
      return null;
    }
  }

  // =====================================================
  // تحليل 1D و 4H
  // =====================================================

  Future<void> analyzeOrderBlocks() async {
    if (coins.isEmpty || analyzing) return;

    setState(() {
      analyzing = true;
      obZones1D.clear();
      obZones4H.clear();
      analyzedSymbols.clear();
      status = 'جارٍ تحليل ICT Order Blocks على 1D و4H...';
    });

    try {
      const batchSize = 3;

      for (int i = 0; i < coins.length; i += batchSize) {

        final end = (i + batchSize < coins.length)
            ? i + batchSize
            : coins.length;

        final batch = coins.sublist(i, end);

        final results =
            await Future.wait<CoinAnalysisResult>(
          batch.map((coin) async {

            final zones = await Future.wait<ObZone?>([
              analyzeCoin(coin, '1d'),
              analyzeCoin(coin, '4h'),
            ]);

            return CoinAnalysisResult(
              coin.symbol,
              zones[0],
              zones[1],
            );
          }),
        );

        if (!mounted) return;

        setState(() {
          for (final result in results) {
            obZones1D[result.symbol] =
                result.dailyZone;

            obZones4H[result.symbol] =
                result.fourHourZone;

            analyzedSymbols.add(result.symbol);
          }

          final valid1D = obZones1D.values
              .where(
                (zone) => zone != null && !zone.breaker,
              )
              .length;

          final valid4H = obZones4H.values
              .where(
                (zone) => zone != null && !zone.breaker,
              )
              .length;

          status =
              'تم تحليل ${analyzedSymbols.length} من ${coins.length} زوجاً'
              ' | ICT OB 1D: $valid1D'
              ' | ICT OB 4H: $valid4H';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => status = 'تعذر التحليل: $e');
    } finally {
      if (mounted) {
        setState(() => analyzing = false);
      }
    }
  }

  // =====================================================
  // عرض معلومات المنطقة
  // =====================================================

  Widget buildZoneInfo(
    String timeframe,
    ObZone? zone,
    Color color,
    bool wasAnalyzed,
  ) {
    if (zone == null) {
      if (!wasAnalyzed) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          'لا يوجد ICT OB صالح على $timeframe',
          style: const TextStyle(
            color: Colors.grey,
          ),
        ),
      );
    }

    final zoneColor =
        zone.breaker ? Colors.orange : color;

    final zoneTitle = zone.breaker
        ? 'ICT Breaker ($timeframe)'
        : 'ICT Bullish OB ($timeframe)';

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$zoneTitle: '
            '${zone.low} - ${zone.high}',
            style: TextStyle(
              color: zoneColor,
              fontWeight: FontWeight.bold,
            ),
          ),

          Text(
            zone.breaker
                ? 'المنطقة مكسورة - ليست OB صالحة للشراء'
                : 'منطقة طلب صالحة وفق شروط ICT',
            style: TextStyle(
              color: zoneColor,
              fontSize: 12,
            ),
          ),

          Text(
            'البعد عن المنطقة: '
            '${zone.distance.toStringAsFixed(2)}%',
            style: TextStyle(
              color: zoneColor,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // واجهة التطبيق
  // =====================================================

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Smart Alert Hunter V2'),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      'ماسح Binance Spot - ICT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    Text(
                      '• أزواج USDT فقط\n'
                      '• السعر لا يتجاوز 1 USDT\n'
                      '• حجم تداول 24 ساعة لا يقل عن 500,000 USDT\n'
                      '• اكتشاف ICT Bullish OB على 1D\n'
                      '• اكتشاف ICT Bullish OB على 4H\n'
                      '• Swing Lookback = 10\n'
                      '• Use Candle Body = true\n'
                      '• أحدث منطقة OB فقط\n'
                      '• لا يوجد فلتر EMA\n'
                      '• تمييز المناطق المكسورة Breaker\n'
                      'هذه قائمة تصفية وتحليل أولي وليست إشارة شراء.',

                      style: TextStyle(height: 1.6),
                    ),

                    SizedBox(height: 8),

                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          color: Colors.green,
                          size: 12,
                        ),
                        SizedBox(width: 5),
                        Text('1D - يومي'),

                        SizedBox(width: 18),

                        Icon(
                          Icons.circle,
                          color: Colors.blue,
                          size: 12,
                        ),
                        SizedBox(width: 5),
                        Text('4H - أربع ساعات'),
                      ],
                    ),

                    SizedBox(height: 5),

                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          color: Colors.orange,
                          size: 12,
                        ),
                        SizedBox(width: 5),
                        Text('Breaker - منطقة مكسورة'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            FilledButton.icon(
              onPressed: loading || analyzing ? null : scan,

              icon: const Icon(Icons.refresh),

              label: Text(
                loading
                    ? 'جارٍ الفحص...'
                    : 'فحص السوق الآن',
              ),
            ),

            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: coins.isEmpty ||
                      loading ||
                      analyzing
                  ? null
                  : analyzeOrderBlocks,

              icon: const Icon(Icons.analytics_outlined),

              label: Text(
                analyzing
                    ? 'جارٍ تحليل ICT OB...'
                    : 'تحليل مناطق ICT OB 1D + 4H',
              ),
            ),

            const SizedBox(height: 10),

            if (analyzing)
              const LinearProgressIndicator(),

            const SizedBox(height: 8),

            Text(
              status,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Expanded(
              child: coins.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد نتائج معروضة حالياً',
                      ),
                    )

                  : ListView.separated(
                      itemCount: coins.length,

                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),

                      itemBuilder: (context, index) {
                        final c = coins[index];

                        final zone1D =
                            obZones1D[c.symbol];

                        final zone4H =
                            obZones4H[c.symbol];

                        final wasAnalyzed =
                            analyzedSymbols.contains(c.symbol);

                        return ListTile(
                          title: Text(
                            c.symbol,
                            textDirection: TextDirection.ltr,

                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          subtitle: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,

                            children: [
                              Text(
                                'حجم 24 ساعة: '
                                '${c.volume.toStringAsFixed(0)} USDT',
                              ),

                              buildZoneInfo(
                                '1D',
                                zone1D,
                                Colors.green,
                                wasAnalyzed,
                              ),

                              buildZoneInfo(
                                '4H',
                                zone4H,
                                Colors.blue,
                                wasAnalyzed,
                              ),
                            ],
                          ),

                          trailing: Text(
                            c.price.toStringAsFixed(6),
                            textDirection: TextDirection.ltr,

                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const Text(
              'تنبيه: لا ينفذ التطبيق صفقات ولا يضمن الربح. '
              'تحقق من التحليل قبل اتخاذ أي قرار.',

              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
