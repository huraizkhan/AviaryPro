import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import 'pair_details_screen.dart';
import 'select_cage_for_pair_screen.dart';

enum BreedingView { allPairs, activeBreeding }

class BreedingScreen extends StatefulWidget {
  const BreedingScreen({super.key});

  @override
  State<BreedingScreen> createState() => _BreedingScreenState();
}

class _BreedingScreenState extends State<BreedingScreen> {
  BreedingView view = BreedingView.allPairs;
  bool loading = true;
  Map<String, int> summary = const {};
  List<Map<String, dynamic>> pairs = const [];

  bool get activeOnly => view == BreedingView.activeBreeding;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => loading = true);
    final summaryResult = await DatabaseHelper.instance.getBreedingSummary();
    final pairResult = await DatabaseHelper.instance.getBreedingPairs(
      activeOnly: activeOnly,
    );
    if (!mounted) return;
    setState(() {
      summary = summaryResult;
      pairs = pairResult;
      loading = false;
    });
  }

  Future<void> _createPair() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const SelectCageForPairScreen(),
      ),
    );
    if (!mounted || changed != true) return;
    await _load();
  }

  Widget _statCard(
    String label,
    int value,
    AviaryIconType icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            AviaryIcon(icon, color: color),
            const SizedBox(height: 5),
            Text(
              '$value',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _birdLabel(Map<String, dynamic> pair, String prefix) {
    final name = pair['${prefix}Name']?.toString().trim();
    final ring = pair['${prefix}RingNumber']?.toString().trim() ?? '';
    return name == null || name.isEmpty ? ring : '$name ($ring)';
  }

  DateTime? _nextHatch(Map<String, dynamic> pair) {
    return DateTime.tryParse(pair['nextExpectedHatchDate']?.toString() ?? '');
  }

  String _stage(Map<String, dynamic> pair) {
    final chicks = (pair['chicksInNest'] as num?)?.toInt() ?? 0;
    if (chicks > 0) return 'Chicks';
    final eggs = (pair['activeEggCount'] as num?)?.toInt() ?? 0;
    if (eggs > 0) {
      final next = _nextHatch(pair);
      if (next != null) {
        final now = DateTime.now();
        final days = DateTime(next.year, next.month, next.day)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
        if (days >= -1 && days <= 1) return 'Hatching';
      }
      return 'Incubating';
    }
    final clutches = (pair['activeClutchCount'] as num?)?.toInt() ?? 0;
    if (clutches > 0) return 'Laying';
    return pair['breedingStatus'] == 'Active' ? 'Bonding' : 'Resting';
  }

  Color _pairTint(Map<String, dynamic> pair) {
    return aviaryBreedingTint(
      activeEggs: (pair['activeEggCount'] as num?)?.toInt() ?? 0,
      chicksInNest: (pair['chicksInNest'] as num?)?.toInt() ?? 0,
      unresolvedEggs: (pair['unresolvedEggCount'] as num?)?.toInt() ?? 0,
      nextHatchDate: _nextHatch(pair),
    );
  }

  Color _genderColor(String gender) {
    return switch (gender) {
      'Male' => const Color(0xFF2878D4),
      'Female' => const Color(0xFFD94F8A),
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  Widget _countColumn(String label, int value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AviaryLayout.horizontalPadding(context),
          12,
          AviaryLayout.horizontalPadding(context),
          100,
        ),
        children: [
          Row(
            children: [
              _statCard(
                'All Pairs',
                summary['allPairs'] ?? 0,
                AviaryIconType.pair,
                AviaryColors.breeding,
              ),
              const SizedBox(width: 10),
              _statCard(
                'Active Breeding Pairs',
                summary['activePairs'] ?? 0,
                AviaryIconType.pair,
                const Color(0xFFD45B8C),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statCard(
                'Eggs',
                summary['totalEggs'] ?? 0,
                AviaryIconType.egg,
                AviaryColors.breeding,
              ),
              const SizedBox(width: 10),
              _statCard(
                'Chicks In Nest',
                summary['chicksInNest'] ?? 0,
                AviaryIconType.chick,
                AviaryColors.birds,
              ),
            ],
          ),
          const SizedBox(height: 14),
          AviarySegmentedControl<BreedingView>(
            items: const [
              (BreedingView.allPairs, 'All Pairs'),
              (BreedingView.activeBreeding, 'Active Breeding'),
            ],
            selected: view,
            accent: AviaryColors.breeding,
            onChanged: (value) {
              setState(() => view = value);
              _load();
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _createPair,
            icon: const AviaryIcon(
              AviaryIconType.pair,
              color: Colors.white,
            ),
            label: const Text('CREATE PAIR'),
          ),
          const SizedBox(height: 12),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (pairs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  activeOnly
                      ? 'No active breeding pairs'
                      : 'No pairs created yet',
                ),
              ),
            )
          else
            ...pairs.map((pair) {
              final cage = pair['cageIdentifier']?.toString() ?? 'No cage';
              final pairId = pair['identifier']?.toString() ?? 'Pair';
              final species = pair['speciesName']?.toString() ?? 'Unknown species';
              final activeEggs =
                  (pair['activeEggCount'] as num?)?.toInt() ?? 0;
              final chicks = (pair['chicksInNest'] as num?)?.toInt() ?? 0;
              final activeClutches =
                  (pair['activeClutchCount'] as num?)?.toInt() ?? 0;
              final tint = _pairTint(pair);

              Widget birdColumn(String prefix, String gender) {
                return Expanded(
                  child: Column(
                    crossAxisAlignment: prefix == 'male'
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.end,
                    children: [
                      Text(
                        _birdLabel(pair, prefix),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: prefix == 'male' ? TextAlign.left : TextAlign.right,
                        style: TextStyle(
                          color: birdGenderTextColor(gender),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        gender,
                        style: TextStyle(
                          color: _genderColor(gender),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  color: tint == Colors.transparent ? Colors.white : tint,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PairDetailsScreen(
                            pairId: pair['id'].toString(),
                          ),
                        ),
                      );
                      if (!mounted) return;
                      await _load();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.white.withValues(alpha: .75),
                                child: AviaryIcon(
                                  activeEggs > 0
                                      ? AviaryIconType.egg
                                      : AviaryIconType.pair,
                                  color: AviaryColors.breeding,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  '$cage — $pairId · $species',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(_stage(pair)),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 290),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  birdColumn('male', 'Male'),
                                  const SizedBox(width: 8),
                                  birdColumn('female', 'Female'),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 20),
                          Row(
                            children: [
                              _countColumn('Eggs', activeEggs),
                              _countColumn('Chicks', chicks),
                            ],
                          ),
                          if (activeClutches > 1) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                '$activeClutches Clutches',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
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
