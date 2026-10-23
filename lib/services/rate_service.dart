import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RateSnapshot {
  const RateSnapshot({
    required this.base,
    required this.rates,
    required this.updatedAt,
    required this.cachedAt,
    required this.isCached,
  });

  final String base;
  final Map<String, double> rates;
  final DateTime updatedAt;
  final DateTime cachedAt;
  final bool isCached;

  double rateTo(String target) => target == base ? 1 : rates[target] ?? 0;
}

class HistoricalPoint {
  const HistoricalPoint(this.date, this.rate);

  final DateTime date;
  final double rate;
}

class RateService {
  static const _cachePrefix = 'latest_rates_v1_';
  static const sourceName = 'Currency data by fawazahmed0';
  static const sourceUrl = 'https://github.com/fawazahmed0/currency-api';

  final http.Client _client;

  RateService({http.Client? client}) : _client = client ?? http.Client();

  Future<RateSnapshot> latest(String base) async {
    try {
      final snapshot = await _fetch(base.toLowerCase(), 'latest');
      await _save(snapshot);
      return snapshot;
    } catch (_) {
      final cached = await _read(base.toLowerCase());
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<RateSnapshot> _fetch(String base, String version) async {
    final uri = Uri.parse(
      'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@$version/v1/currencies/$base.json',
    );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Rate service returned ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final date =
        DateTime.tryParse(decoded['date'] as String? ?? '') ?? DateTime.now();
    final rawRates = decoded[base] as Map<String, dynamic>?;
    if (rawRates == null) {
      throw const FormatException('Rates are missing from response.');
    }
    final rates = <String, double>{};
    rawRates.forEach((key, value) {
      if (value is num && value > 0) {
        rates[key.toUpperCase()] = value.toDouble();
      }
    });
    if (rates.isEmpty) {
      throw const FormatException('Rate service returned no rates.');
    }
    return RateSnapshot(
      base: base.toUpperCase(),
      rates: rates,
      updatedAt: date,
      cachedAt: DateTime.now(),
      isCached: false,
    );
  }

  Future<void> _save(RateSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_cachePrefix${snapshot.base}',
      jsonEncode({
        'base': snapshot.base,
        'rates': snapshot.rates,
        'updatedAt': snapshot.updatedAt.toIso8601String(),
        'cachedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<RateSnapshot?> _read(String base) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix${base.toUpperCase()}');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final rawRates = data['rates'] as Map<String, dynamic>;
      return RateSnapshot(
        base: data['base'] as String,
        rates: rawRates.map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
        ),
        updatedAt: DateTime.parse(data['updatedAt'] as String),
        cachedAt: DateTime.parse(
          data['cachedAt'] as String? ?? data['updatedAt'] as String,
        ),
        isCached: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<HistoricalPoint>> history({
    required String base,
    required String target,
    required int days,
  }) async {
    final now = DateTime.now().toUtc();
    // A compact daily series keeps the chart readable and limits requests.
    final count = days <= 31
        ? 8
        : days <= 93
        ? 10
        : days <= 186
        ? 12
        : 14;
    final requests = <Future<HistoricalPoint?>>[];
    for (var i = count - 1; i >= 0; i--) {
      final date = DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: (days * i / (count - 1)).round()));
      final stamp =
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      requests.add(_historyPoint(base, target, stamp));
    }
    final points =
        (await Future.wait(requests)).whereType<HistoricalPoint>().toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (points.isEmpty) {
      throw Exception('Historical rates are unavailable right now.');
    }
    return points;
  }

  Future<HistoricalPoint?> _historyPoint(
    String base,
    String target,
    String stamp,
  ) async {
    try {
      final snapshot = await _fetch(base.toLowerCase(), stamp);
      final rate = snapshot.rateTo(target.toUpperCase());
      return rate > 0 ? HistoricalPoint(snapshot.updatedAt, rate) : null;
    } catch (_) {
      // Some dates may not have a published snapshot; keep available points.
      return null;
    }
  }

  void dispose() => _client.close();
}
