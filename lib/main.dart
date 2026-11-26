
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
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const ScannerPage(),
  );
}

class Coin {
  final String symbol;
  final double price;
  final double volume;
  Coin(this.symbol, this.price, this.volume);
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool loading = false;
  String status = 'اضغط على تحديث لجلب أزواج Binance Spot';
  List<Coin> coins = [];

  Future<void> scan() async {
    setState(() {
      loading = true;
      status = 'جارٍ الاتصال بـ Binance...';
    });

    try {
      final response = await http.get(
        Uri.parse('https://data-api.binance.vision/api/v3/ticker/24hr'),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('استجابة Binance: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as List<dynamic>;
      final found = <Coin>[];

      for (final item in data) {
        final row = item as Map<String, dynamic>;
        final symbol = row['symbol']?.toString() ?? '';

        if (!symbol.endsWith('USDT')) continue;

        final price =
            double.tryParse(row['lastPrice']?.toString() ?? '') ?? 0;
        final volume =
            double.tryParse(row['quoteVolume']?.toString() ?? '') ?? 0;

        if (price > 0 && price <= 1 && volume >= 1000000) {
          found.add(Coin(symbol, price, volume));
        }
      }

      found.sort((a, b) => b.volume.compareTo(a.volume));

      if (!mounted) return;

      setState(() {
        coins = found;
        status = 'تم الفحص: ${found.length} زوجاً يطابق شروط السعر والسيولة';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => status = 'تعذر الفحص: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('Smart Alert Hunter V1')),
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
                  'هذه قائمة تصفية أولية وليست إشارة شراء.',
                  style: TextStyle(height: 1.6),
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: loading ? null : scan,
              icon: const Icon(Icons.refresh),
              label: Text(loading ? 'جارٍ الفحص...' : 'فحص السوق الآن'),
            ),
            const SizedBox(height: 10),
            Text(status, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Expanded(
              child: coins.isEmpty
                  ? const Center(
                      child: Text('لا توجد نتائج معروضة حالياً'),
                    )
                  : ListView.separated(
                      itemCount: coins.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = coins[index];
                        return ListTile(
                          title: Text(
                            c.symbol,
                            textDirection: TextDirection.ltr,
                          ),
                          subtitle: Text(
                            'حجم 24 ساعة: ${c.volume.toStringAsFixed(0)} USDT',
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
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    ),
  );
}
