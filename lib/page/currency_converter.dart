import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/rate_service.dart';

String _formatNumber(double number) {
  final value = number.toStringAsPrecision(10);
  if (!value.contains('.')) return value;
  return value
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class CurrencyConverter extends StatefulWidget {
  const CurrencyConverter({super.key});

  @override
  State<CurrencyConverter> createState() => _CurrencyConverterState();
}

class _CurrencyConverterState extends State<CurrencyConverter> {
  final _service = RateService();
  final _amountController = TextEditingController();
  final _currencies = const ['UGX', 'KES', 'USD', 'EUR'];
  String _base = 'UGX';
  String _target = 'KES';
  double _result = 0;
  RateSnapshot? _snapshot;
  bool _loadingRates = false;
  String? _rateError;
  int _periodDays = 30;
  List<HistoricalPoint> _history = [];
  bool _loadingHistory = false;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _refreshRates();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _service.dispose();
    super.dispose();
  }

  double get _rate => _snapshot?.rateTo(_target) ?? 0;

  Future<void> _refreshRates() async {
    setState(() {
      _loadingRates = true;
      _rateError = null;
    });
    try {
      final snapshot = await _service.latest(_base);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loadingRates = false;
        _rateError = _rate <= 0 ? 'This currency pair is unavailable.' : null;
      });
      _loadHistory();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingRates = false;
        _rateError =
            'Rates could not be loaded. Check your connection and try again.';
      });
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
      _history = [];
    });
    try {
      final points = await _service.history(
        base: _base,
        target: _target,
        days: _periodDays,
      );
      if (!mounted) return;
      setState(() {
        _history = points;
        _loadingHistory = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _historyError = 'Historical data is unavailable. Try again later.';
      });
    }
  }

  void _convert() {
    final amount =
        double.tryParse(_amountController.text.trim().replaceAll(',', '')) ?? 0;
    setState(() => _result = amount * _rate);
  }

  Future<void> _selectCurrency(String? value, {required bool isBase}) async {
    if (value == null) return;
    setState(() {
      if (isBase) {
        _base = value;
        if (_target == value) {
          _target = _currencies.firstWhere((c) => c != value);
        }
      } else {
        _target = value;
      }
      _result = 0;
      _snapshot = null;
    });
    await _refreshRates();
  }

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  void _openCalculator() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CalculatorSheet(
        currencies: _currencies,
        initialBase: _base,
        initialTarget: _target,
        onConvert: (amount, from, to) async {
          final rate = _snapshot?.base == from ? _snapshot!.rateTo(to) : null;
          if (rate != null && rate > 0) return amount * rate;
          final snapshot = await _service.latest(from);
          return amount * snapshot.rateTo(to);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rateText = _rate > 0 ? _rate.toStringAsPrecision(6) : '—';
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Currency Converter',
          style: TextStyle(color: Colors.red, fontSize: 20),
        ),
        backgroundColor: const Color.fromARGB(255, 136, 168, 222),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Quick calculator',
            onPressed: _openCalculator,
            icon: const Icon(Icons.calculate_outlined),
          ),
          IconButton(
            tooltip: 'Refresh rates',
            onPressed: _loadingRates ? null : _refreshRates,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      backgroundColor: Colors.grey.shade700,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshRates,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _buildConverterCard(rateText),
              const SizedBox(height: 16),
              _buildTrendCard(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCalculator,
        icon: const Icon(Icons.calculate),
        label: const Text('Quick calculator'),
      ),
    );
  }

  Widget _buildConverterCard(String rateText) {
    return Card(
      color: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'CONVERT CURRENCY',
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _currencyPicker(
                    _base,
                    (v) => _selectCurrency(v, isBase: true),
                    'From',
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final oldBase = _base;
                    setState(() {
                      _base = _target;
                      _target = oldBase;
                      _snapshot = null;
                      _result = 0;
                    });
                    _refreshRates();
                  },
                  icon: const Icon(Icons.swap_horiz, size: 30),
                  tooltip: 'Swap currencies',
                ),
                Expanded(
                  child: _currencyPicker(
                    _target,
                    (v) => _selectCurrency(v, isBase: false),
                    'To',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onSubmitted: (_) => _convert(),
              decoration: InputDecoration(
                labelText: 'Amount in $_base',
                prefixIcon: const Icon(Icons.payments_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _rate > 0 ? _convert : null,
              child: const Text('CONVERT'),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                '${_result.toStringAsFixed(2)} $_target',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff243b67),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            Row(
              children: [
                if (_loadingRates)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    _snapshot?.isCached == true
                        ? Icons.cloud_off
                        : Icons.cloud_done,
                    size: 17,
                    color: _snapshot?.isCached == true
                        ? Colors.orange.shade800
                        : Colors.green.shade700,
                  ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _loadingRates
                        ? 'Updating exchange rate…'
                        : _rateError ??
                              (_snapshot == null
                                  ? 'Rate unavailable'
                                  : '1 $_base = $rateText $_target${_snapshot!.isCached ? ' · Offline cache' : ''}'),
                    style: TextStyle(
                      fontSize: 12,
                      color: _rateError == null
                          ? Colors.black54
                          : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            if (_snapshot != null) ...[
              const SizedBox(height: 4),
              Text(
                'Rate date ${_dateLabel(_snapshot!.updatedAt)}${_snapshot!.isCached ? ' · Cached ${_dateLabel(_snapshot!.cachedAt)} ${_snapshot!.cachedAt.hour.toString().padLeft(2, '0')}:${_snapshot!.cachedAt.minute.toString().padLeft(2, '0')}' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              Text(
                'Source: ${RateService.sourceName}',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _currencyPicker(
    String value,
    ValueChanged<String?> onChanged,
    String label,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      DropdownButton<String>(
        value: value,
        isExpanded: true,
        items: _currencies
            .map(
              (c) => DropdownMenuItem(
                value: c,
                child: Text(
                  c,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    ],
  );

  Widget _buildTrendCard() {
    const periods = {30: '1M', 90: '3M', 180: '6M', 365: '1Y'};
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_base to $_target trend',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: periods.entries
                  .map(
                    (entry) => ChoiceChip(
                      label: Text(entry.value),
                      selected: _periodDays == entry.key,
                      onSelected: (_) {
                        setState(() => _periodDays = entry.key);
                        _loadHistory();
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              width: double.infinity,
              child: _loadingHistory
                  ? const Center(child: CircularProgressIndicator())
                  : _history.isEmpty
                  ? Center(
                      child: Text(
                        _historyError ?? 'Loading historical rates…',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    )
                  : CustomPaint(
                      painter: _TrendPainter(_history),
                      child: const SizedBox.expand(),
                    ),
            ),
            if (_history.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _dateLabel(_history.first.date),
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  Text(
                    '1 $_base = ${_history.last.rate.toStringAsPrecision(5)} $_target',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  Text(
                    _dateLabel(_history.last.date),
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points);
  final List<HistoricalPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0, right = 8.0, top = 12.0, bottom = 12.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;
    final values = points.map((p) => p.rate).toList();
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final span = maxValue - minValue;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = left + width * i / math.max(1, points.length - 1);
      final normalized = span == 0 ? 0.5 : (points[i].rate - minValue) / span;
      final y = top + height * (1 - normalized);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final grid = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = top + height * i / 3;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
    }
    final line = Paint()
      ..color = const Color(0xff3267bd)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);
    final fillPath = Path.from(path)
      ..lineTo(left + width, size.height - bottom)
      ..lineTo(left, size.height - bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = const Color(0xff3267bd).withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _CalculatorSheet extends StatefulWidget {
  const _CalculatorSheet({
    required this.currencies,
    required this.initialBase,
    required this.initialTarget,
    required this.onConvert,
  });
  final List<String> currencies;
  final String initialBase;
  final String initialTarget;
  final Future<double> Function(double amount, String from, String to)
  onConvert;

  @override
  State<_CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<_CalculatorSheet> {
  String _display = '0';
  String _stored = '';
  String? _operator;
  bool _newEntry = true;
  String? _error;
  late String _from = widget.initialBase;
  late String _to = widget.initialTarget;
  bool _busy = false;

  void _key(String key) {
    setState(() {
      _error = null;
      if ('+-×÷'.contains(key)) {
        _stored = _display;
        _operator = key;
        _newEntry = true;
      } else if (key == '=') {
        final a = double.tryParse(_stored) ?? 0;
        final b = double.tryParse(_display) ?? 0;
        if (_operator == '÷' && b == 0) {
          _error = 'Cannot divide by zero';
          return;
        }
        final answer = switch (_operator) {
          '+' => a + b,
          '-' => a - b,
          '×' => a * b,
          '÷' => a / b,
          _ => b,
        };
        _display = _formatNumber(answer);
        _operator = null;
        _newEntry = true;
      } else if (key == 'C') {
        _display = '0';
        _stored = '';
        _operator = null;
        _newEntry = true;
      } else if (key == '⌫') {
        _display = _display.length > 1
            ? _display.substring(0, _display.length - 1)
            : '0';
      } else {
        if (_newEntry) {
          _display = key == '.' ? '0.' : key;
          _newEntry = false;
        } else if (key != '.' || !_display.contains('.')) {
          _display += key;
        }
      }
    });
  }

  Future<void> _convert() async {
    final amount = double.tryParse(_display) ?? 0;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onConvert(amount, _from, _to);
      if (mounted) {
        setState(() {
          _display = _formatNumber(result);
          _busy = false;
          _newEntry = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Conversion rate unavailable';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = [
      'C',
      '⌫',
      '÷',
      '×',
      '7',
      '8',
      '9',
      '-',
      '4',
      '5',
      '6',
      '+',
      '1',
      '2',
      '3',
      '=',
      '.',
      '0',
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Quick calculator',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerRight,
                  child: Text(
                    _display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 4,
                  childAspectRatio: 1.5,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: keys
                      .map(
                        (key) => OutlinedButton(
                          onPressed: () => _key(key),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: '+-×÷='.contains(key)
                                ? Colors.blue.shade50
                                : null,
                          ),
                          child: Text(
                            key,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const Divider(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        value: _from,
                        isExpanded: true,
                        items: widget.currencies
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _from = v!),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward),
                    ),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _to,
                        isExpanded: true,
                        items: widget.currencies
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _to = v!),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _convert,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.currency_exchange),
                    label: Text('Convert $_from to $_to'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
