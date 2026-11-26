
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

  final Map<String, ObZone?> obZones = {};
  final Set<String> analyzedSymbols = {};

  // الفحص الأساسي: نفس الشروط الأصلية
  Future<void> scan() async {
    setState(() {
      loading = true;
      obZones.clear();
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
            volume >= 1000000) {
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

  // اكتشاف منطقة Bullish OB اليومية
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

      // رفض المنطقة إذا كُسرت بإغلاق يومي أسفلها
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

      // عرض المناطق الواقعة أسفل السعر فقط
      if (currentPrice <= ob.high) continue;

      final distance =
          ((currentPrice - ob.high) / currentPrice) * 100;

      final zone = ObZone(
        ob.low,
        ob.high,
        distance,
      );

      // اختيار أقرب منطقة طلب صالحة أسفل السعر
      if (bestZone == null ||
          zone.high > bestZone.high) {
        bestZone = zone;
      }
    }

    return bestZone;
  }

  // تحميل الشموع اليومية وتحليل العملة
  Future<MapEntry<String, ObZone?>> analyzeCoin(
    Coin coin,
  ) async {
    try {
      final uri = Uri.https(
        'api.binance.com',
        '/api/v3/klines',
        {
          'symbol': coin.symbol,
          'interval': '1d',
          'limit': '100',
        },
      );

      final response = await http.get(uri).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        return MapEntry(coin.symbol, null);
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

      final zone = findBullishOb(
        candles,
        coin.price,
      );

      return MapEntry(coin.symbol, zone);
    } catch (_) {
      return MapEntry(coin.symbol, null);
    }
  }

  // تحليل العملات على دفعات لتقليل ضغط الطلبات
  Future<void> analyzeOrderBlocks() async {
    if (coins.isEmpty || analyzing) return;

    setState(() {
      analyzing = true;
      obZones.clear();
      analyzedSymbols.clear();
      status = 'جارٍ تحليل مناطق الطلب اليومية...';
    });

    try {
      const batchSize = 5;

      for (int i = 0; i < coins.length; i += batchSize) {
        final end = (i + batchSize < coins.length)
            ? i + batchSize
            : coins.length;

        final batch = coins.sublist(i, end);

        final results = await Future.wait(
          batch.map(analyzeCoin),
        );

        if (!mounted) return;

        setState(() {
          for (final result in results) {
            obZones[result.key] = result.value;
            analyzedSymbols.add(result.key);
          }

          final validCount = obZones.values
              .where((zone) => zone != null)
              .length;

          status =
              'تم تحليل ${analyzedSymbols.length} من ${coins.length} '
              'زوجاً | مناطق صالحة: $validCount';
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
                child: Text(
                  'ماسح Binance Spot\n'
                  '• أزواج USDT فقط\n'
                  '• السعر لا يتجاوز 1 USDT\n'
                  '• حجم تداول 24 ساعة لا يقل عن 1,000,000 USDT\n'
                  '• تحليل Bullish Order Block على 1D\n'
                  'هذه قائمة تصفية وتحليل أولي وليست إشارة شراء.',
                  style: TextStyle(height: 1.6),
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
                    : 'تحليل مناطق الطلب OB',
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
                        final zone = obZones[c.symbol];
                        final wasAnalyzed =
                            analyzedSymbols.contains(c.symbol);

                        return ListTile(
                          title: Text(
                            c.symbol,
                            textDirection: TextDirection.ltr,
                          ),
                          subtitle: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'حجم 24 ساعة: '
                                '${c.volume.toStringAsFixed(0)} USDT',
                              ),

                              if (zone != null) ...[
                                const SizedBox(height: 5),
                                Text(
                                  'Bullish OB: '
                                  '${zone.low} - ${zone.high}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'البعد عن المنطقة: '
                                  '${zone.distance.toStringAsFixed(2)}%',
                                ),
                              ] else if (wasAnalyzed) ...[
                                const SizedBox(height: 5),
                                const Text(
                                  'لا يوجد OB يومي صالح',
                                  style: TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
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
