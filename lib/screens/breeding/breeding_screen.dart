import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/database_helper.dart';
import '../../providers/card_customization_provider.dart';
import '../../ui/aviary_design.dart';
import '../../ui/list_grid_toggle.dart';
import 'pair_details_screen.dart';

enum BreedingView { pairs, breeding }

class BreedingScreen extends StatefulWidget {
  const BreedingScreen({super.key});

  @override
  State<BreedingScreen> createState() => _BreedingScreenState();
}

class _BreedingScreenState extends State<BreedingScreen> {
  BreedingView view = BreedingView.pairs;
  bool loading = true;
  bool pairsGridView = false;
  bool breedingGridView = false;
  String? loadError;
  Map<String, int> summary = const {};
  List<Map<String, dynamic>> pairs = const [];

  bool get breedingOnly => view == BreedingView.breeding;

  @override
  void initState() {
    super.initState();
    _loadViewMode();
    _load();
  }

  bool get gridView =>
      view == BreedingView.pairs ? pairsGridView : breedingGridView;

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPairs = prefs.getBool('pairs_grid_view') ?? false;
    final savedBreeding = prefs.getBool('breeding_grid_view') ?? false;
    if (!mounted) return;
    setState(() {
      pairsGridView = savedPairs;
      breedingGridView = savedBreeding;
    });
  }

  Future<void> _setGridView(bool value) async {
    final isPairs = view == BreedingView.pairs;
    setState(() {
      if (isPairs) {
        pairsGridView = value;
      } else {
        breedingGridView = value;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      isPairs ? 'pairs_grid_view' : 'breeding_grid_view',
      value,
    );
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        loadError = null;
      });
    }

    try {
      final pairResult = await DatabaseHelper.instance
          .getBreedingPairs()
          .timeout(const Duration(seconds: 12));
      pairResult.sort((a, b) => _naturalCompare(
            a['cageIdentifier']?.toString() ?? '',
            b['cageIdentifier']?.toString() ?? '',
          ));

      final activeCount = pairResult.where(_isBreedingPair).length;
      final totalEggs = pairResult.fold<int>(
        0,
        (sum, pair) =>
            sum + ((pair['activeEggCount'] as num?)?.toInt() ?? 0),
      );
      final chicksInNest = pairResult.fold<int>(
        0,
        (sum, pair) => sum + ((pair['chicksInNest'] as num?)?.toInt() ?? 0),
      );

      if (!mounted) return;
      setState(() {
        summary = {
          'allPairs': pairResult.length,
          'activePairs': activeCount,
          'totalEggs': totalEggs,
          'chicksInNest': chicksInNest,
        };
        pairs = pairResult;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = 'Could not load breeding pairs';
      });
    }
  }

  List<Map<String, dynamic>> get visiblePairs {
    if (!breedingOnly) return pairs;
    return pairs.where(_isBreedingPair).toList();
  }

  bool _isBreedingPair(Map<String, dynamic> pair) {
    return const {'Laying', 'Incubating', 'Hatching', 'Chicks', 'Breeding'}
        .contains(_stage(pair));
  }

  Widget _statCard(
    String label,
    int value,
    AviaryIconType icon,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: .20)),
      ),
      child: Column(
        children: [
          AviaryIcon(icon, color: scheme.primary),
          const SizedBox(height: 5),
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimaryContainer,
                ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid() {
    final prefs = context.watch<CardCustomizationProvider>();
    final cards = <String, Widget>{
      'allPairs': _statCard(
        'Pairs',
        summary['allPairs'] ?? 0,
        AviaryIconType.pair,
      ),
      'activePairs': _statCard(
        'Breeding',
        summary['activePairs'] ?? 0,
        AviaryIconType.pair,
      ),
      'eggs': _statCard(
        'Eggs',
        summary['totalEggs'] ?? 0,
        AviaryIconType.egg,
      ),
      'chicks': _statCard(
        'Chicks In Nest',
        summary['chicksInNest'] ?? 0,
        AviaryIconType.chick,
      ),
    };
    final visible = prefs
        .orderFor('breeding')
        .where((id) => prefs.isVisible('breeding', id) && cards.containsKey(id))
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final itemWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: visible
              .map((id) => SizedBox(width: itemWidth, child: cards[id]!))
              .toList(),
        );
      },
    );
  }

  int _naturalCompare(String left, String right) {
    final pattern = RegExp(r'(\d+|\D+)');
    final a = pattern
        .allMatches(left.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    final b = pattern
        .allMatches(right.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    final length = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final an = int.tryParse(a[i]);
      final bn = int.tryParse(b[i]);
      final result = an != null && bn != null
          ? an.compareTo(bn)
          : a[i].compareTo(b[i]);
      if (result != 0) return result;
    }
    return a.length.compareTo(b.length);
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
    final metricsUnavailable =
        (pair['metricsUnavailable'] as num?)?.toInt() == 1;
    if (metricsUnavailable) {
      return pair['breedingStatus']?.toString() == 'Active'
          ? 'Breeding'
          : 'Resting';
    }

    final activeClutches = (pair['activeClutchCount'] as num?)?.toInt() ?? 0;
    final allClutches = (pair['totalClutchCount'] as num?)?.toInt() ?? 0;
    final chicks = (pair['chicksInNest'] as num?)?.toInt() ?? 0;
    final eggs = (pair['activeEggCount'] as num?)?.toInt() ?? 0;
    final totalEggs = (pair['currentEggCount'] as num?)?.toInt() ?? 0;
    final hatched = (pair['hatchedEggCount'] as num?)?.toInt() ?? 0;
    final expected = (pair['expectedEggCount'] as num?)?.toInt() ?? 0;

    if (activeClutches == 0) return allClutches == 0 ? 'Bonding' : 'Resting';
    if (chicks > 0 && eggs == 0) return 'Chicks';

    if (eggs > 0) {
      final next = _nextHatch(pair);
      if (hatched > 0) return 'Hatching';
      if (next != null) {
        final now = DateTime.now();
        final days = DateTime(next.year, next.month, next.day)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
        if (days <= 1) return 'Hatching';
      }
      final latest = DateTime.tryParse(pair['latestEggDate']?.toString() ?? '');
      final stillLayingByExpectation = expected > 0 && totalEggs < expected;
      final stillLayingByRecency = expected == 0 &&
          hatched == 0 &&
          latest != null &&
          DateTime.now().difference(latest).inDays <= 2;
      if (stillLayingByExpectation || stillLayingByRecency) return 'Laying';
      return 'Incubating';
    }

    return chicks > 0 ? 'Chicks' : 'Resting';
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

  Future<void> _openPair(Map<String, dynamic> pair) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PairDetailsScreen(pairId: pair['id'].toString()),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Widget _pairCard(Map<String, dynamic> pair, {required bool compact}) {
    final cage = pair['cageIdentifier']?.toString() ?? 'No cage';
    final species = pair['speciesName']?.toString() ?? 'Unknown species';
    final activeEggs = (pair['activeEggCount'] as num?)?.toInt() ?? 0;
    final chicks = (pair['chicksInNest'] as num?)?.toInt() ?? 0;
    final activeClutches = (pair['activeClutchCount'] as num?)?.toInt() ?? 0;
    final tint = _pairTint(pair);
    final stage = _stage(pair);

    if (compact) {
      return Card(
        color: aviaryCardSurface(context, tint: tint),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openPair(pair),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '$cage · $species',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(stage),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _birdLabel(pair, 'male'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: birdGenderTextColor('Male'),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _birdLabel(pair, 'female'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: birdGenderTextColor('Female'),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const AviaryIcon(AviaryIconType.egg, size: 14),
                      label: Text('$activeEggs'),
                    ),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const AviaryIcon(AviaryIconType.chick, size: 14),
                      label: Text('$chicks'),
                    ),
                    if (activeClutches > 1)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('$activeClutches clutches'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

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

    return Card(
      color: aviaryCardSurface(context, tint: tint),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openPair(pair),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: aviaryAvatarSurface(context),
                    child: AviaryIcon(
                      activeEggs > 0 ? AviaryIconType.egg : AviaryIconType.pair,
                      color: AviaryColors.breeding,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      '$cage · $species',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(stage),
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
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pairList() {
    final data = visiblePairs;
    if (data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            breedingOnly
                ? 'No pairs are breeding right now'
                : 'No pairs created yet',
          ),
        ),
      );
    }

    if (!gridView) {
      return Column(
        children: data
            .map((pair) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _pairCard(pair, compact: false),
                ))
            .toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 800
            ? 3
            : constraints.maxWidth < 360
                ? 1
                : 2;
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: data
              .map((pair) => SizedBox(
                    width: itemWidth,
                    child: _pairCard(pair, compact: true),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _errorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 34),
            const SizedBox(height: 8),
            Text(loadError ?? 'Could not load breeding pairs'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AviaryLayout.horizontalPadding(context),
          12,
          AviaryLayout.horizontalPadding(context),
          100,
        ),
        children: [
          _summaryGrid(),
          const SizedBox(height: 14),
          AviarySegmentedControl<BreedingView>(
            items: const [
              (BreedingView.pairs, 'Pairs'),
              (BreedingView.breeding, 'Breeding'),
            ],
            selected: view,
            accent: AviaryColors.breeding,
            onChanged: (value) => setState(() => view = value),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: AviaryListGridToggle(
              gridView: gridView,
              onChanged: _setGridView,
            ),
          ),
          const SizedBox(height: 10),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (loadError != null)
            _errorState()
          else
            _pairList(),
        ],
      ),
    );
  }
}
