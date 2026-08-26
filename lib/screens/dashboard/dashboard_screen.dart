import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import 'package:provider/provider.dart';
import '../../providers/card_customization_provider.dart';
import '../../ui/aviary_design.dart';
import '../birds/bird_details_screen.dart';
import '../birds/sale_list_screen.dart';
import '../breeding/clutch_details_screen.dart';
import '../breeding/pair_details_screen.dart';
import '../history/history_screen.dart';
import 'dashboard_chick_cages_screen.dart';
import 'dashboard_egg_pairs_screen.dart';

class DashboardScreen extends StatefulWidget {
  final ValueChanged<int> onNavigate;

  const DashboardScreen({
    super.key,
    required this.onNavigate,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _money = NumberFormat('#,##0.##');
  Map<String, int> _summary = const {};
  Map<String, double> _finance = const {};
  List<Map<String, dynamic>> _alerts = const [];
  List<Map<String, dynamic>> _recent = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getDashboardSummary(),
      DatabaseHelper.instance.getDashboardAlerts(),
      DatabaseHelper.instance.getFinancePeriodSummary(),
      DatabaseHelper.instance.getActivityEvents(limit: 5),
    ]);
    if (!mounted) return;
    setState(() {
      _summary = results[0] as Map<String, int>;
      _alerts = results[1] as List<Map<String, dynamic>>;
      _finance = results[2] as Map<String, double>;
      _recent = results[3] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Color _alertColor(String severity) {
    return switch (severity) {
      'overdue' || 'due' => AviaryColors.hatchOneDay,
      'urgent' => AviaryColors.hatchOneDay.withValues(alpha: .82),
      'warning' => AviaryColors.hatchThreeDays,
      'notice' => AviaryColors.hatchFiveDays,
      'hatching' => AviaryColors.hatching,
      'complete' => AviaryColors.chicksHatched,
      _ => AviaryColors.eggsNormal,
    };
  }

  Widget _stat({
    required String label,
    required int value,
    required Widget icon,
    int? tab,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap ?? (tab == null ? null : () => widget.onNavigate(tab)),
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .20),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 170;
            final padding = compact ? 10.0 : 14.0;
            final gap = compact ? 8.0 : 12.0;
            return Padding(
              padding: EdgeInsets.all(padding),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: compact ? 18 : 20,
                    backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: .75),
                    child: icon,
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$value',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: compact ? 26 : 30,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 14 : 16,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }


  Future<void> _openAlert(Map<String, dynamic> alert) async {
    final type = alert['entityType']?.toString();
    final id = alert['entityId']?.toString();
    if (id == null || id.isEmpty) return;
    if (type == 'Pair') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PairDetailsScreen(pairId: id)),
      );
    } else if (type == 'Clutch') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClutchDetailsScreen(clutchId: id),
        ),
      );
    } else if (type == 'Bird') {
      final bird = await DatabaseHelper.instance.getBirdById(id);
      if (!mounted || bird == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: bird)),
      );
    }
    if (mounted) await _load();
  }

  Future<void> _dismiss(Map<String, dynamic> alert) async {
    final key = alert['alertKey']?.toString();
    if (key == null) return;
    await DatabaseHelper.instance.dismissDashboardAlert(key);
    if (!mounted) return;
    setState(() => _alerts = _alerts.where((item) => item != alert).toList());
  }

  Widget _todayCard() {
    final attention = _alerts.length;
    final forSale = _summary['saleList'] ?? 0;
    final taken = _summary['takenForSale'] ?? 0;
    final observations = _summary['observations'] ?? 0;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SaleListScreen()),
          );
          if (mounted) await _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.today_outlined),
                  SizedBox(width: 8),
                  Text('Today at a Glance', style: TextStyle(fontWeight: FontWeight.w800)),
                  Spacer(),
                  Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  Chip(label: Text('$attention attention'), visualDensity: VisualDensity.compact),
                  Chip(label: Text('$forSale for sale'), visualDensity: VisualDensity.compact),
                  if (taken > 0)
                    Chip(label: Text('$taken taken out'), visualDensity: VisualDensity.compact),
                  if (observations > 0)
                    Chip(label: Text('$observations unconfirmed'), visualDensity: VisualDensity.compact),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _financeCard() {
    final income = _finance['monthIncome'] ?? 0;
    final expense = _finance['monthExpense'] ?? 0;
    final balance = _finance['monthBalance'] ?? 0;
    return Card(
      color: aviaryCardSurface(
        context,
        tint: AviaryColors.finance.withValues(alpha: .08),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => widget.onNavigate(3),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  AviaryIcon(
                    AviaryIconType.finance,
                    color: AviaryColors.finance,
                  ),
                  SizedBox(width: 9),
                  Text(
                    'This Month',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Spacer(),
                  Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _moneyLine('Income', income, AviaryColors.finance),
                  ),
                  Expanded(
                    child: _moneyLine('Expense', expense, const Color(0xFFD2653A)),
                  ),
                  Expanded(
                    child: _moneyLine('Balance', balance, AviaryColors.dashboard),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moneyLine(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _money.format(value),
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final layout = context.watch<CardCustomizationProvider>();
    final summaryCards = <String, Widget>{
      'birds': _stat(
        label: 'Current Birds',
        value: _summary['birds'] ?? 0,
        icon: AviaryIcon(
          AviaryIconType.bird,
          ),
        tab: 1,
      ),
      'eggs': _stat(
        label: 'Eggs',
        value: _summary['eggs'] ?? 0,
        icon: AviaryIcon(
          AviaryIconType.egg,
          ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DashboardEggPairsScreen()),
          );
          if (mounted) await _load();
        },
      ),
      'pairs': _stat(
        label: 'Active Pairs',
        value: _summary['pairs'] ?? 0,
        icon: AviaryIcon(
          AviaryIconType.pair,
          ),
        tab: 2,
      ),
      'chicks': _stat(
        label: 'Chicks',
        value: _summary['chicks'] ?? 0,
        icon: AviaryIcon(
          AviaryIconType.chick,
          ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DashboardChickCagesScreen()),
          );
          if (mounted) await _load();
        },
      ),
    };
    final visibleSummaryCards = layout
        .orderFor('dashboard')
        .where((id) => layout.isVisible('dashboard', id) && summaryCards.containsKey(id))
        .map((id) => summaryCards[id]!)
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AviaryLayout.horizontalPadding(context),
          12,
          AviaryLayout.horizontalPadding(context),
          110,
        ),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 760 ? 4 : 2;
              final gap = width < 360 ? 8.0 : 10.0;
              final itemWidth =
                  (width - (gap * (columns - 1))) / columns;

              // Keep the original roomy dashboard-card proportions on normal
              // phones. On narrow cards / larger system text, add only the
              // extra height needed to prevent overflow instead of shrinking
              // the whole dashboard.
              final originalHeight = itemWidth / 1.55;
              final scaledLabelSize =
                  MediaQuery.textScalerOf(context).scale(16);
              final textScaleExtra =
                  (scaledLabelSize - 16).clamp(0.0, 10.0).toDouble();
              final compactMinHeight = 124.0 + (textScaleExtra * 2);
              final targetHeight = itemWidth < 170 &&
                      originalHeight < compactMinHeight
                  ? compactMinHeight
                  : originalHeight;
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
                childAspectRatio: itemWidth / targetHeight,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: visibleSummaryCards,
              );
            },
          ),
          const SizedBox(height: 10),
          _todayCard(),
          const SizedBox(height: 14),
          _financeCard(),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text(
                'Needs Attention',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text('${_alerts.length}'),
            ],
          ),
          const SizedBox(height: 9),
          if (_alerts.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline, color: AviaryColors.finance),
                title: Text('Nothing urgent right now'),
                subtitle: Text('Upcoming hatch and age alerts will appear here.'),
              ),
            )
          else
            ..._alerts.map((alert) {
              final severity = alert['severity']?.toString() ?? 'info';
              final isHatch = alert['kind'] == 'pair_hatch';
              final eggLines = (alert['eggLines'] as List?)
                      ?.map((item) => item.toString())
                      .toList() ??
                  const <String>[];
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Card(
                  color: aviaryCardSurface(context, tint: _alertColor(severity)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _openAlert(alert),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: aviaryAvatarSurface(context),
                            child: isHatch
                                ? const AviaryIcon(AviaryIconType.egg)
                                : const AviaryIcon(AviaryIconType.chick),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  alert['title']?.toString() ?? 'Alert',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (isHatch) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Pair ${alert['pairLabel'] ?? ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 7),
                                  ...eggLines.map(
                                    (line) => Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Text(line),
                                    ),
                                  ),
                                ] else
                                  Text(alert['body']?.toString() ?? ''),
                              ],
                            ),
                          ),
                          if (!isHatch)
                            IconButton(
                              tooltip: 'Dismiss',
                              onPressed: () => _dismiss(alert),
                              icon: const Icon(Icons.close),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Icon(Icons.chevron_right),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text(
                'Recent Activity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                },
                child: const Text('View all'),
              ),
            ],
          ),
          if (_recent.isEmpty)
            const Card(child: ListTile(title: Text('No activity yet.')))
          else
            ..._recent.map((event) {
              final date = DateTime.tryParse(event['eventDate']?.toString() ?? '');
              final dateLabel =
                  date == null ? '' : ' · ${DateFormat('dd-MMM').format(date)}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(event['title']?.toString() ?? 'Activity'),
                    subtitle: Text(
                      '${event['eventType'] ?? ''}$dateLabel',
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
