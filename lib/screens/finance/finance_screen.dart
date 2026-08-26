import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import 'add_transaction_screen.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  final dateFormat = DateFormat('dd-MMM-yy');
  final moneyFormat = NumberFormat('#,##0.00');

  Map<String, double> summary = const {};
  Map<String, double> feedAnalytics = const {};
  List<Map<String, dynamic>> transactions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getFinancePeriodSummary(),
      DatabaseHelper.instance.getFinanceTransactions(),
      DatabaseHelper.instance.getFeedAnalytics(),
    ]);
    if (!mounted) return;
    setState(() {
      summary = results[0] as Map<String, double>;
      transactions = results[1] as List<Map<String, dynamic>>;
      feedAnalytics = results[2] as Map<String, double>;
      loading = false;
    });
  }

  Future<void> _add(String type) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(initialType: type),
      ),
    );
    if (!mounted || changed != true) return;
    await _load();
  }

  Widget _periodCard({
    required String title,
    required double income,
    required double expense,
    required double balance,
  }) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AviaryIcon(
                    AviaryIconType.finance,
                    color: AviaryColors.finance,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _moneyLine('Income', income, AviaryColors.finance),
              const SizedBox(height: 6),
              _moneyLine('Expense', expense, const Color(0xFFC85B37)),
              const Divider(height: 18),
              _moneyLine(
                'Balance',
                balance,
                balance >= 0 ? AviaryColors.finance : const Color(0xFFC85B37),
                bold: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moneyLine(
    String label,
    double value,
    Color color, {
    bool bold = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
          ),
        ),
        Text(
          moneyFormat.format(value),
          style: TextStyle(
            color: color,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _feedStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _periodCard(
                title: 'This Month',
                income: summary['monthIncome'] ?? 0,
                expense: summary['monthExpense'] ?? 0,
                balance: summary['monthBalance'] ?? 0,
              ),
              const SizedBox(width: 10),
              _periodCard(
                title: 'This Year',
                income: summary['yearIncome'] ?? 0,
                expense: summary['yearExpense'] ?? 0,
                balance: summary['yearBalance'] ?? 0,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            color: aviaryCardSurface(
              context,
              tint: AviaryColors.breeding.withValues(alpha: .10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.grass_outlined, color: AviaryColors.breeding),
                      SizedBox(width: 8),
                      Text('Feed Trend', style: TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _feedStat(
                          'This month',
                          '${(feedAnalytics['monthKg'] ?? 0).toStringAsFixed(1)} kg',
                        ),
                      ),
                      Expanded(
                        child: _feedStat(
                          '3-month avg',
                          '${(feedAnalytics['rollingMonthlyKg'] ?? 0).toStringAsFixed(1)} kg/mo',
                        ),
                      ),
                      Expanded(
                        child: _feedStat(
                          'Month cost',
                          moneyFormat.format(feedAnalytics['monthCost'] ?? 0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AviaryColors.finance,
                  ),
                  onPressed: () => _add('Income'),
                  icon: const Icon(Icons.add),
                  label: const Text('Income'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC85B37),
                  ),
                  onPressed: () => _add('Expense'),
                  icon: const Icon(Icons.remove),
                  label: const Text('Expense'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Transactions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (transactions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No transactions yet.'),
              ),
            )
          else
            ...transactions.map((item) {
              final type = item['type']?.toString() ?? 'Income';
              final isIncome = type == 'Income';
              final date = DateTime.tryParse(item['date']?.toString() ?? '');
              final bird = item['ringNumber']?.toString();
              final notes = item['notes']?.toString().trim() ?? '';
              final quantity = (item['quantity'] as num?)?.toDouble();
              final unit = item['unit']?.toString().trim() ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  color: aviaryCardSurface(
                    context,
                    tint: isIncome ? AviaryColors.income : AviaryColors.expense,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: aviaryAvatarSurface(context),
                      child: Icon(
                        isIncome ? Icons.south_west : Icons.north_east,
                        color: isIncome
                            ? AviaryColors.finance
                            : const Color(0xFFC85B37),
                      ),
                    ),
                    title: Text(
                      item['category']?.toString() ?? type,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: date == null ? '-' : dateFormat.format(date),
                          ),
                          if (bird != null) const TextSpan(text: ' · Bird '),
                          if (bird != null)
                            TextSpan(
                              text: bird,
                              style: TextStyle(
                                color: birdGenderTextColor(
                                  item['birdGender']?.toString(),
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (quantity != null && quantity > 0)
                            TextSpan(
                              text: '\n${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1)} ${unit.isEmpty ? 'kg' : unit}',
                            ),
                          if (notes.isNotEmpty) TextSpan(text: '\n$notes'),
                        ],
                      ),
                    ),
                    isThreeLine: notes.isNotEmpty,
                    trailing: Text(
                      '${isIncome ? '+' : '-'}${moneyFormat.format((item['amount'] as num?)?.toDouble() ?? 0)}',
                      style: TextStyle(
                        color: isIncome
                            ? AviaryColors.finance
                            : const Color(0xFFC85B37),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
