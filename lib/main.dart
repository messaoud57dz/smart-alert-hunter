
import 'dart:convert';
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

  ObZone(this.low, this.high, this.distance);
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

  // مناطق الطلب اليومية 1D
  final Map<String, ObZone?> obZones1D = {};

  // مناطق الطلب لأربع ساعات 4H
  final Map<String, ObZone?> obZones4H = {};

  final Set<String> analyzedSymbols = {};

  // فحص السوق: الشروط الأصلية دون تغيير
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
          found.add(Coin(symbol, price, volume));
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

  // حساب المتوسط الأسي EMA
  double calculateEma(List<double> values, int period) {
    if (values.length < period) return 0;

    double ema = values
        .take(period)
        .reduce((a, b) => a + b) / period;

    final multiplier = 2 / (period + 1);

    for (int i = period; i < values.length; i++) {
      ema = (values[i] - ema) * multiplier + ema;
    }

    return ema;
  }

  // اكتشاف Bullish Order Block
  // تستخدم نفس الخوارزمية على 1D و 4H
  ObZone? findBullishOb(
    List<Candle> candles,
    double currentPrice,
  ) {
    if (candles.length < 60) return null;

    final closes = candles.map((c) => c.close).toList();

    final ema20 = calculateEma(closes, 20);
    final ema50 = calculateEma(closes, 50);

    // فلتر الاتجاه الصاعد
    if (ema20 <= ema50 || closes.last <= ema20) {
      return null;
    }

    ObZone? bestZone;

    for (int i = 10; i < candles.length - 3; i++) {
      final ob = candles[i];

      // شمعة هابطة قبل الحركة الصاعدة
      if (ob.close >= ob.open) continue;

      double previousHigh = 0;
      double averageBody = 0;

      for (int j = i - 10; j < i; j++) {
        if (candles[j].high > previousHigh) {
          previousHigh = candles[j].high;
        }

        averageBody +=
            (candles[j].close - candles[j].open).abs();
      }

      averageBody /= 10;

      int? impulseIndex;

      // البحث عن حركة صاعدة قوية خلال 3 شموع
      for (int j = i + 1;
          j <= i + 3 && j < candles.length;
          j++) {
        final candle = candles[j];
        final body = candle.close - candle.open;

        if (body > 0 &&
            candle.close > previousHigh &&
            body >= averageBody * 1.5) {
          impulseIndex = j;
          break;
        }
      }

      if (impulseIndex == null) continue;

      // إبطال المنطقة عند الإغلاق أسفل حدها السفلي
      bool broken = false;

      for (int j = impulseIndex + 1;
          j < candles.length;
          j++) {
        if (candles[j].close < ob.low) {
          broken = true;
          break;
        }
      }

      if (broken) continue;

      // المناطق أسفل السعر الحالي فقط
      if (currentPrice <= ob.high) continue;

      final distance =
          ((currentPrice - ob.high) / currentPrice) * 100;

      final zone = ObZone(
        ob.low,
        ob.high,
        distance,
      );

      // اختيار أقرب منطقة صالحة أسفل السعر
      if (bestZone == null ||
          zone.high > bestZone.high) {
        bestZone = zone;
      }
    }

    return bestZone;
  }

  // تحميل الشموع وتحليل الفريم المطلوب
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
          'limit': '100',
        },
      );

      final response = await http.get(uri).timeout(
        const Duration(seconds: 15),
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

  // تحليل 1D و 4H لكل عملة
  Future<void> analyzeOrderBlocks() async {
    if (coins.isEmpty || analyzing) return;

    setState(() {
      analyzing = true;
      obZones1D.clear();
      obZones4H.clear();
      analyzedSymbols.clear();
      status = 'جارٍ تحليل مناطق الطلب 1D و 4H...';
    });

    try {
      // 3 عملات في كل دفعة
      // كل عملة ترسل طلبين: 1D و 4H
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
              .where((zone) => zone != null)
              .length;

          final valid4H = obZones4H.values
              .where((zone) => zone != null)
              .length;

          status =
              'تم تحليل ${analyzedSymbols.length} من ${coins.length} زوجاً'
              ' | مناطق 1D: $valid1D'
              ' | مناطق 4H: $valid4H';
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

  // عرض تفاصيل منطقة الطلب
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
          timeframe == '1D'
              ? 'لا يوجد OB يومي صالح'
              : 'لا يوجد OB صالح على 4H',
          style: const TextStyle(
            color: Colors.grey,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bullish OB ($timeframe): '
            '${zone.low} - ${zone.high}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'البعد عن منطقة $timeframe: '
            '${zone.distance.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
            ),
          ),
        ],
      ),
    );
  }

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
                      'ماسح Binance Spot',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '• أزواج USDT فقط\n'
                      '• السعر لا يتجاوز 1 USDT\n'
                      '• حجم تداول 24 ساعة لا يقل عن 500,000 USDT\n'
                      '• تحليل Bullish Order Block على 1D\n'
                      '• تحليل Bullish Order Block على 4H\n'
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
                  ],
                ),
              ),
            ),

            FilledButton.icon(
              onPressed: loading || analyzing ? null : scan,
              icon: const Icon(Icons.refresh),
              label: Text(
                loading ? 'جارٍ الفحص...' : 'فحص السوق الآن',
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
                    ? 'جارٍ تحليل OB...'
                    : 'تحليل مناطق الطلب 1D + 4H',
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

                              // منطقة الطلب اليومية باللون الأخضر
                              buildZoneInfo(
                                '1D',
                                zone1D,
                                Colors.green,
                                wasAnalyzed,
                              ),

                              // منطقة الطلب لأربع ساعات باللون الأزرق
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
