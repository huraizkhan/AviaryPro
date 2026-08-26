import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/database_helper.dart';
import '../../providers/bird_provider.dart';
import '../../providers/card_customization_provider.dart';
import '../../ui/aviary_design.dart';
import '../cages/cage_details_screen.dart';
import 'add_bird_screen.dart';
import 'bird_details_screen.dart';

enum BirdListView { byCage, allBirds }

class BirdsScreen extends StatefulWidget {
  const BirdsScreen({super.key});

  @override
  State<BirdsScreen> createState() => _BirdsScreenState();
}

class _BirdsScreenState extends State<BirdsScreen> {
  BirdListView view = BirdListView.byCage;
  List<Map<String, dynamic>> cageSummary = [];
  int currentBirdCount = 0;
  bool loadingCages = true;

  Set<String> speciesFilters = <String>{};
  Set<String> nameFilters = <String>{};
  Set<String> genderFilters = <String>{};
  Set<String> mutationFilters = <String>{};
  Set<String> ageFilters = <String>{};

  String countMode = 'Mutation';
  bool _countExpanded = false;

  bool selectionMode = false;
  final Set<String> selectedBirdIds = <String>{};
  Map<String, Map<String, dynamic>>? _lastBulkUndo;

  @override
  void initState() {
    super.initState();
    _loadCages();
    _loadCountMode();
  }

  Future<void> _loadCountMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('all_birds_count_mode');
    if (!mounted || saved == null) return;
    if (const {'Mutation', 'Species', 'Name', 'Gender'}.contains(saved)) {
      setState(() => countMode = saved);
    }
  }

  Future<void> _setCountMode(String value) async {
    setState(() => countMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('all_birds_count_mode', value);
  }

  Future<void> _loadCages() async {
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getBirdCageSummary(),
      DatabaseHelper.instance.getCurrentBirdCount(),
    ]);
    if (!mounted) return;
    setState(() {
      cageSummary = results[0] as List<Map<String, dynamic>>;
      currentBirdCount = results[1] as int;
      loadingCages = false;
    });
  }

  DateTime? _effectiveBirthDate(Map<String, dynamic> bird) {
    final hatchDate = DateTime.tryParse(bird['hatchDate']?.toString() ?? '');
    if (hatchDate != null) return hatchDate;
    final sourceDate = DateTime.tryParse(bird['sourceDate']?.toString() ?? '');
    final estimatedDays = (bird['estimatedAgeDays'] as num?)?.toInt();
    if (sourceDate == null || estimatedDays == null) return null;
    return sourceDate.subtract(Duration(days: estimatedDays));
  }

  int _ageInCompletedMonths(DateTime birthDate) {
    final today = DateTime.now();
    var months = (today.year - birthDate.year) * 12;
    months += today.month - birthDate.month;
    if (today.day < birthDate.day) months--;
    return months < 0 ? 0 : months;
  }

  int _ageInDays(DateTime birthDate) {
    final today = DateTime.now();
    final start = DateTime(birthDate.year, birthDate.month, birthDate.day);
    final end = DateTime(today.year, today.month, today.day);
    return end.difference(start).inDays.clamp(0, 100000).toInt();
  }

  String _ageGroup(Map<String, dynamic> bird) {
    final birthDate = _effectiveBirthDate(bird);
    if (birthDate == null) {
      return bird['ageGroup']?.toString() ?? 'Unknown';
    }
    final youngAt = (bird['chickToYoungDays'] as num?)?.toInt();
    final adultAt = (bird['adultAgeMonths'] as num?)?.toInt();
    if (adultAt != null && _ageInCompletedMonths(birthDate) >= adultAt) {
      return 'Adult';
    }
    if (youngAt != null && _ageInDays(birthDate) >= youngAt) return 'Young';
    return 'Chick';
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
    for (var index = 0; index < length; index++) {
      final aNumber = int.tryParse(a[index]);
      final bNumber = int.tryParse(b[index]);
      final result = aNumber != null && bNumber != null
          ? aNumber.compareTo(bNumber)
          : a[index].compareTo(b[index]);
      if (result != 0) return result;
    }
    return a.length.compareTo(b.length);
  }

  bool _matchesFilters(Map<String, dynamic> bird) {
    final species = bird['speciesName']?.toString().trim() ?? '';
    final name = bird['name']?.toString().trim() ?? '';
    final gender = bird['gender']?.toString() ?? 'Unknown';
    final mutation = bird['mutation']?.toString().trim() ?? '';
    final age = _ageGroup(bird);
    if (speciesFilters.isNotEmpty && !speciesFilters.contains(species)) {
      return false;
    }
    if (nameFilters.isNotEmpty && !nameFilters.contains(name)) return false;
    if (genderFilters.isNotEmpty && !genderFilters.contains(gender)) {
      return false;
    }
    if (mutationFilters.isNotEmpty && !mutationFilters.contains(mutation)) {
      return false;
    }
    if (ageFilters.isNotEmpty && !ageFilters.contains(age)) return false;
    return true;
  }

  List<Map<String, dynamic>> _filteredBirds(List<Map<String, dynamic>> birds) {
    final result = birds.where(_matchesFilters).toList();
    result.sort(
      (a, b) => _naturalCompare(
        a['ringNumber']?.toString() ?? '',
        b['ringNumber']?.toString() ?? '',
      ),
    );
    return result;
  }

  int get _activeFilterCount => [
        speciesFilters,
        nameFilters,
        genderFilters,
        mutationFilters,
        ageFilters,
      ].where((set) => set.isNotEmpty).length;

  Future<void> _showFilters(List<Map<String, dynamic>> birds) async {
    final result = await Navigator.push<_BirdFilterSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => _BirdFilterScreen(
          birds: birds,
          initial: _BirdFilterSelection(
            species: {...speciesFilters},
            names: {...nameFilters},
            genders: {...genderFilters},
            mutations: {...mutationFilters},
            ages: {...ageFilters},
          ),
          ageGroupFor: _ageGroup,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      speciesFilters = result.species;
      nameFilters = result.names;
      genderFilters = result.genders;
      mutationFilters = result.mutations;
      ageFilters = result.ages;
      final visibleIds = birds.where((bird) {
        final species = bird['speciesName']?.toString().trim() ?? '';
        final name = bird['name']?.toString().trim() ?? '';
        final gender = bird['gender']?.toString() ?? 'Unknown';
        final mutation = bird['mutation']?.toString().trim() ?? '';
        final age = _ageGroup(bird);
        return (speciesFilters.isEmpty || speciesFilters.contains(species)) &&
            (nameFilters.isEmpty || nameFilters.contains(name)) &&
            (genderFilters.isEmpty || genderFilters.contains(gender)) &&
            (mutationFilters.isEmpty || mutationFilters.contains(mutation)) &&
            (ageFilters.isEmpty || ageFilters.contains(age));
      }).map((bird) => bird['id'].toString()).toSet();
      selectedBirdIds.removeWhere((id) => !visibleIds.contains(id));
    });
  }

  Future<void> _openDetails(
    BuildContext context,
    Map<String, dynamic> bird,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: bird)),
    );
    if (!context.mounted) return;
    await context.read<BirdProvider>().loadBirds();
    await _loadCages();
  }

  Future<void> _editBird(
    BuildContext context,
    Map<String, dynamic> bird,
  ) async {
    final changed = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => AddBirdScreen(bird: bird)),
    );
    if (!context.mounted || (changed != true && changed != 'deleted')) return;
    await context.read<BirdProvider>().loadBirds();
    await _loadCages();
  }

  void _toggleSelection(Map<String, dynamic> bird) {
    final id = bird['id'].toString();
    setState(() {
      selectionMode = true;
      if (!selectedBirdIds.add(id)) selectedBirdIds.remove(id);
    });
  }

  void _toggleSelectAll(List<Map<String, dynamic>> visibleBirds) {
    final visibleIds = visibleBirds.map((bird) => bird['id'].toString()).toSet();
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(selectedBirdIds.contains);
    setState(() {
      if (allSelected) {
        selectedBirdIds.removeAll(visibleIds);
      } else {
        selectedBirdIds.addAll(visibleIds);
      }
    });
  }

  Future<void> _quickEdit() async {
    if (selectedBirdIds.isEmpty) return;
    final changes = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _BirdQuickEditScreen(count: selectedBirdIds.length),
      ),
    );
    if (!mounted || changes == null || changes.isEmpty) return;
    try {
      final previous = await DatabaseHelper.instance.quickEditBirds(
        birdIds: selectedBirdIds.toList(),
        changes: changes,
      );
      if (!mounted) return;
      await context.read<BirdProvider>().loadBirds();
      if (!mounted) return;
      setState(() => _lastBulkUndo = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated ${previous.length} birds'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: _undoLastQuickEdit,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _undoLastQuickEdit() async {
    final previous = _lastBulkUndo;
    if (previous == null || previous.isEmpty) return;
    await DatabaseHelper.instance.undoQuickEditBirds(previous);
    if (!mounted) return;
    await context.read<BirdProvider>().loadBirds();
    if (!mounted) return;
    setState(() => _lastBulkUndo = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bulk edit undone')),
    );
  }

  Color _birdTint(Map<String, dynamic> bird) {
    // Bird identity/status is already visible through text and chips. Avoid
    // painting the entire card by pair/gender state, especially in dark mode.
    return Colors.transparent;
  }

  Color _cageTint(Map<String, dynamic> cage) {
    final activeEggs = (cage['activeEggCount'] as num?)?.toInt() ?? 0;
    final unresolved = (cage['unresolvedEggCount'] as num?)?.toInt() ?? 0;
    final chicks = (cage['chicksInNest'] as num?)?.toInt() ?? 0;
    final nextHatch =
        DateTime.tryParse(cage['nextExpectedHatchDate']?.toString() ?? '');
    final tint = aviaryBreedingTint(
      activeEggs: activeEggs,
      chicksInNest: chicks,
      unresolvedEggs: unresolved,
      nextHatchDate: nextHatch,
    );
    return tint;
  }

  Widget _summaryHeader() {
    final totalPairs = cageSummary.fold<int>(
      0,
      (sum, cage) => sum + ((cage['pairCount'] as num?)?.toInt() ?? 0),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: aviaryAvatarSurface(context),
            child: AviaryIcon(
              AviaryIconType.bird,
              size: 30,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$currentBirdCount Current Birds',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text('${cageSummary.length} cages · $totalPairs active pairs'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCages() {
    if (loadingCages) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (cageSummary.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('No cages currently contain birds')),
      );
    }
    return Column(
      children: cageSummary.map((cage) {
        final birdCount = (cage['birdCount'] as num?)?.toInt() ?? 0;
        final pairCount = (cage['pairCount'] as num?)?.toInt() ?? 0;
        final eggs = (cage['activeEggCount'] as num?)?.toInt() ?? 0;
        final chicks = (cage['chicksInNest'] as num?)?.toInt() ?? 0;
        final physicalLabel = cage['identityMode'] == 'series' &&
                (cage['physicalName']?.toString() ?? '').isNotEmpty
            ? '${cage['physicalName']}\n'
            : '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            color: aviaryCardSurface(context, tint: _cageTint(cage)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: aviaryAvatarSurface(context),
                child: const AviaryIcon(
                  AviaryIconType.cage,
                  color: AviaryColors.cages,
                ),
              ),
              title: Text(
                cage['identifier']?.toString() ?? 'Cage',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '$physicalLabel$birdCount birds · $pairCount pairs'
                '${eggs > 0 ? ' · $eggs eggs' : ''}'
                '${chicks > 0 ? ' · $chicks chicks' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final birdProvider = context.read<BirdProvider>();
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CageDetailsScreen(cageId: cage['id'].toString()),
                  ),
                );
                if (!mounted) return;
                await _loadCages();
                await birdProvider.loadBirds();
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  String _countValue(Map<String, dynamic> bird) {
    return switch (countMode) {
      'Species' => bird['speciesName']?.toString().trim() ?? '',
      'Name' => bird['name']?.toString().trim() ?? '',
      'Gender' => bird['gender']?.toString().trim() ?? 'Unknown',
      _ => bird['mutation']?.toString().trim() ?? '',
    };
  }

  String _countDisplay(String value) {
    if (value.isNotEmpty) return value;
    return switch (countMode) {
      'Name' => 'Unnamed',
      'Mutation' => 'No mutation',
      _ => 'Unknown',
    };
  }

  bool _countPillSelected(String value) {
    return switch (countMode) {
      'Species' => speciesFilters.length == 1 && speciesFilters.contains(value),
      'Name' => nameFilters.length == 1 && nameFilters.contains(value),
      'Gender' => genderFilters.length == 1 && genderFilters.contains(value),
      _ => mutationFilters.length == 1 && mutationFilters.contains(value),
    };
  }

  void _applyCountPill(String value) {
    final wasSelected = _countPillSelected(value);
    setState(() {
      speciesFilters.clear();
      nameFilters.clear();
      genderFilters.clear();
      mutationFilters.clear();
      ageFilters.clear();
      if (!wasSelected) {
        switch (countMode) {
          case 'Species':
            speciesFilters.add(value);
            break;
          case 'Name':
            nameFilters.add(value);
            break;
          case 'Gender':
            genderFilters.add(value);
            break;
          default:
            mutationFilters.add(value);
        }
      }
      selectionMode = false;
      selectedBirdIds.clear();
    });
  }

  Widget _countSummary(List<Map<String, dynamic>> allBirds) {
    final counts = <String, int>{};
    for (final bird in allBirds) {
      final value = _countValue(bird);
      counts[value] = (counts[value] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return _countDisplay(a.key)
            .toLowerCase()
            .compareTo(_countDisplay(b.key).toLowerCase());
      });
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Automatic Count',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                DropdownButton<String>(
                  value: countMode,
                  items: const ['Mutation', 'Species', 'Name', 'Gender']
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _setCountMode(value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final selectedKeys = entries
                    .where((entry) => _countPillSelected(entry.key))
                    .map((entry) => entry.key)
                    .toSet();
                final shown = _countExpanded
                    ? entries
                    : entries
                        .where((entry) => selectedKeys.contains(entry.key))
                        .followedBy(entries.where((entry) => !selectedKeys.contains(entry.key)))
                        .take(4)
                        .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: shown
                          .map((entry) => FilterChip(
                                selected: _countPillSelected(entry.key),
                                label: Text('${_countDisplay(entry.key)} ${entry.value}'),
                                onSelected: (_) => _applyCountPill(entry.key),
                              ))
                          .toList(),
                    ),
                    if (entries.length > 4)
                      TextButton.icon(
                        onPressed: () => setState(() => _countExpanded = !_countExpanded),
                        icon: Icon(_countExpanded ? Icons.expand_less : Icons.expand_more),
                        label: Text(_countExpanded ? 'Show less' : 'Show ${entries.length - shown.length} more'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterAndCountBar(
    List<Map<String, dynamic>> allBirds,
    List<Map<String, dynamic>> visibleBirds,
  ) {
    final countLabel = _activeFilterCount == 0
        ? '${allBirds.length} Birds'
        : '${visibleBirds.length} of ${allBirds.length} Birds';
    final filterLabel =
        _activeFilterCount == 0 ? 'Filter' : 'Filter ($_activeFilterCount)';
    final visibleIds = visibleBirds.map((bird) => bird['id'].toString()).toSet();
    final allVisibleSelected = visibleIds.isNotEmpty &&
        visibleIds.every((id) => selectedBirdIds.contains(id));

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showFilters(allBirds),
                icon: const Icon(Icons.filter_alt_outlined),
                label: Text(filterLabel),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: IgnorePointer(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.numbers_outlined),
                  label: Text(countLabel),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (!selectionMode)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => selectionMode = true),
              icon: const Icon(Icons.check_box_outlined),
              label: const Text('Select'),
            ),
          )
        else
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: visibleBirds.isEmpty
                    ? null
                    : () => _toggleSelectAll(visibleBirds),
                icon: Icon(
                  allVisibleSelected
                      ? Icons.deselect_outlined
                      : Icons.select_all_outlined,
                ),
                label: Text(allVisibleSelected ? 'Deselect All' : 'Select All'),
              ),
              TextButton.icon(
                onPressed: selectedBirdIds.isEmpty ? null : _quickEdit,
                icon: const Icon(Icons.edit_note_outlined),
                label: Text('Quick Edit (${selectedBirdIds.length})'),
              ),
              if (_lastBulkUndo != null)
                TextButton.icon(
                  onPressed: _undoLastQuickEdit,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo Edit'),
                ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    selectionMode = false;
                    selectedBirdIds.clear();
                  });
                },
                icon: const Icon(Icons.close),
                label: const Text('Done'),
              ),
            ],
          ),
      ],
    );
  }

  String _shortDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${parsed.day.toString().padLeft(2, '0')}-${months[parsed.month - 1]}-${(parsed.year % 100).toString().padLeft(2, '0')}';
  }

  String _parentCardLocation(Map<String, dynamic> bird) {
    String location(String prefix) {
      final active = bird['${prefix}Active'] != 0;
      final cage = bird['${prefix}CageIdentifier']?.toString().trim() ?? '';
      if (active && cage.isNotEmpty) return aviaryCageLabel(cage);
      final sold = bird['${prefix}SaleStatus']?.toString() == 'Sold';
      final reason = bird['${prefix}RemovalReason']?.toString().trim() ?? '';
      if (!active) return sold ? 'Sold' : (reason.isEmpty ? 'Removed' : reason);
      return 'No cage';
    }
    final maleId = bird['parentMaleBirdId']?.toString() ?? '';
    final femaleId = bird['parentFemaleBirdId']?.toString() ?? '';
    if (maleId.isEmpty && femaleId.isEmpty) return '';
    final male = maleId.isEmpty ? '' : location('parentMale');
    final female = femaleId.isEmpty ? '' : location('parentFemale');
    if (male.isNotEmpty && male == female) return 'Parents $male';
    return [if (male.isNotEmpty) 'M $male', if (female.isNotEmpty) 'F $female'].join(' · ');
  }

  String _birdCardFieldValue(Map<String, dynamic> bird, String id) {
    final mutation = bird['mutation']?.toString().trim() ?? '';
    final cage = bird['cageIdentifier']?.toString().trim() ?? '';
    final mateRing = bird['partnerRingNumber']?.toString().trim() ?? '';
    final mateName = bird['partnerName']?.toString().trim() ?? '';
    final male = _birdLabelFromMap(bird, 'parentMaleRingNumber', 'parentMaleName');
    final female = _birdLabelFromMap(bird, 'parentFemaleRingNumber', 'parentFemaleName');
    return switch (id) {
      'cage' => cage.isEmpty ? 'No cage' : aviaryCageLabel(cage),
      'species' => bird['speciesName']?.toString().trim() ?? '',
      'mutation' => mutation.isEmpty ? 'No mutation' : mutation,
      'age' => _ageGroup(bird),
      'pair' => bird['pairId'] == null ? 'Unpaired' : 'Paired',
      'saleStatus' => bird['saleStatus']?.toString().trim() ?? '',
      'gender' => bird['gender']?.toString().trim() ?? 'Unknown',
      'eyeColor' => (bird['eyeColor']?.toString().trim().isNotEmpty ?? false) ? '${bird['eyeColor']} eyes' : '',
      'downColor' => (bird['downColor']?.toString().trim().isNotEmpty ?? false) ? '${bird['downColor']} down' : '',
      'mate' => mateRing.isEmpty && mateName.isEmpty ? '' : 'Mate ${mateName.isEmpty ? mateRing : mateName}',
      'parents' => [male, female].where((value) => value.isNotEmpty).join(' × '),
      'parentCages' => _parentCardLocation(bird),
      'source' => bird['source']?.toString().trim() ?? '',
      'hatchDate' => _shortDate(bird['hatchDate']),
      'sourceDate' => _shortDate(bird['sourceDate']),
      'nest' => bird['nestClutchId'] == null ? '' : 'In nest',
      'notes' => (bird['notes']?.toString().trim().isNotEmpty ?? false) ? 'Notes' : '',
      _ => '',
    };
  }

  String _birdLabelFromMap(Map<String, dynamic> bird, String ringKey, String nameKey) {
    final ring = bird[ringKey]?.toString().trim() ?? '';
    final name = bird[nameKey]?.toString().trim() ?? '';
    if (ring.isEmpty) return name;
    return name.isEmpty ? ring : '$ring ($name)';
  }

  IconData _birdFieldIcon(String id) => switch (id) {
        'cage' => Icons.home_work_outlined,
        'species' => Icons.pets_outlined,
        'mutation' => Icons.palette_outlined,
        'age' => Icons.cake_outlined,
        'pair' => Icons.favorite_outline,
        'saleStatus' => Icons.sell_outlined,
        'gender' => Icons.wc_outlined,
        'eyeColor' => Icons.visibility_outlined,
        'downColor' => Icons.brush_outlined,
        'mate' => Icons.favorite_border,
        'parents' => Icons.account_tree_outlined,
        'parentCages' => Icons.home_outlined,
        'source' => Icons.info_outline,
        'hatchDate' => Icons.egg_outlined,
        'sourceDate' => Icons.event_outlined,
        'nest' => Icons.home_outlined,
        'notes' => Icons.notes_outlined,
        _ => Icons.label_outline,
      };

  Widget _birdCardField(Map<String, dynamic> bird, String id, String style) {
    final value = _birdCardFieldValue(bird, id);
    if (value.isEmpty) return const SizedBox.shrink();
    if (style == 'text') {
      return Padding(
        padding: const EdgeInsets.only(right: 9, bottom: 4),
        child: Text(value, style: Theme.of(context).textTheme.bodySmall),
      );
    }
    if (style == 'icon') {
      return Padding(
        padding: const EdgeInsets.only(right: 7, bottom: 4),
        child: Tooltip(message: value, child: Icon(_birdFieldIcon(id), size: 18)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 5, bottom: 4),
      child: Chip(
        avatar: Icon(_birdFieldIcon(id), size: 14),
        label: Text(value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildBirds(List<Map<String, dynamic>> birdList) {
    if (birdList.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('No birds match the selected filters')),
      );
    }
    return Column(
      children: birdList.map((bird) {
        final ring = bird['ringNumber']?.toString() ?? 'No ring';
        final name = bird['name']?.toString().trim() ?? '';
        final gender = bird['gender']?.toString() ?? 'Unknown';
        final selected = selectedBirdIds.contains(bird['id'].toString());
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : aviaryCardSurface(context, tint: _birdTint(bird)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              onLongPress: selectionMode
                  ? () => _toggleSelection(bird)
                  : () => _editBird(context, bird),
              onTap: selectionMode
                  ? () => _toggleSelection(bird)
                  : () => _openDetails(context, bird),
              leading: selectionMode
                  ? Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleSelection(bird),
                    )
                  : CircleAvatar(
                      backgroundColor: aviaryAvatarSurface(context),
                      child: const AviaryIcon(AviaryIconType.bird),
                    ),
              title: Text(
                name.isEmpty ? ring : '$ring — $name',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: birdGenderTextColor(gender),
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Builder(
                  builder: (context) {
                    final prefs = context.watch<CardCustomizationProvider>();
                    return Wrap(
                      children: prefs.birdFieldOrder
                          .where((id) => prefs.birdFieldStyle(id) != 'hidden')
                          .map((id) => _birdCardField(bird, id, prefs.birdFieldStyle(id)))
                          .toList(),
                    );
                  },
                ),
              ),
              trailing: selectionMode
                  ? null
                  : PopupMenuButton<String>(
                      tooltip: 'Bird options',
                      onSelected: (value) {
                        if (value == 'edit') _editBird(context, bird);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allBirds = context
        .watch<BirdProvider>()
        .birds
        .where((bird) => bird['active'] != 0)
        .toList();
    allBirds.sort(
      (a, b) => _naturalCompare(
        a['ringNumber']?.toString() ?? '',
        b['ringNumber']?.toString() ?? '',
      ),
    );
    final visibleBirds = _filteredBirds(allBirds);

    return RefreshIndicator(
      onRefresh: () async {
        await context.read<BirdProvider>().loadBirds();
        await _loadCages();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          ...context
              .watch<CardCustomizationProvider>()
              .orderFor('birds')
              .where((id) => context
                  .watch<CardCustomizationProvider>()
                  .isVisible('birds', id))
              .expand((id) sync* {
            if (id == 'summary') {
              yield _summaryHeader();
              yield const SizedBox(height: 12);
            } else if (id == 'automaticCount' && view == BirdListView.allBirds) {
              yield _countSummary(allBirds);
              yield const SizedBox(height: 12);
            }
          }),
          AviarySegmentedControl<BirdListView>(
            items: const [
              (BirdListView.byCage, 'By Cage'),
              (BirdListView.allBirds, 'All Birds'),
            ],
            selected: view,
            accent: AviaryColors.birds,
            onChanged: (value) => setState(() => view = value),
          ),
          const SizedBox(height: 12),
          if (view == BirdListView.byCage)
            _buildCages()
          else ...[
            _filterAndCountBar(allBirds, visibleBirds),
            const SizedBox(height: 10),
            _buildBirds(visibleBirds),
          ],
        ],
      ),
    );
  }
}

class _BirdFilterSelection {
  _BirdFilterSelection({
    Set<String>? species,
    Set<String>? names,
    Set<String>? genders,
    Set<String>? mutations,
    Set<String>? ages,
  })  : species = species ?? <String>{},
        names = names ?? <String>{},
        genders = genders ?? <String>{},
        mutations = mutations ?? <String>{},
        ages = ages ?? <String>{};

  final Set<String> species;
  final Set<String> names;
  final Set<String> genders;
  final Set<String> mutations;
  final Set<String> ages;
}

class _BirdFilterScreen extends StatefulWidget {
  const _BirdFilterScreen({
    required this.birds,
    required this.initial,
    required this.ageGroupFor,
  });

  final List<Map<String, dynamic>> birds;
  final _BirdFilterSelection initial;
  final String Function(Map<String, dynamic> bird) ageGroupFor;

  @override
  State<_BirdFilterScreen> createState() => _BirdFilterScreenState();
}

class _BirdFilterScreenState extends State<_BirdFilterScreen> {
  late Set<String> species;
  late Set<String> names;
  late Set<String> genders;
  late Set<String> mutations;
  late Set<String> ages;

  @override
  void initState() {
    super.initState();
    species = {...widget.initial.species};
    names = {...widget.initial.names};
    genders = {...widget.initial.genders};
    mutations = {...widget.initial.mutations};
    ages = {...widget.initial.ages};
  }

  List<String> _options(String category) {
    final values = <String>{};
    for (final bird in widget.birds) {
      final value = switch (category) {
        'Species' => bird['speciesName']?.toString().trim() ?? '',
        'Name' => bird['name']?.toString().trim() ?? '',
        'Gender' => bird['gender']?.toString().trim() ?? 'Unknown',
        'Mutation' => bird['mutation']?.toString().trim() ?? '',
        'Age Group' => widget.ageGroupFor(bird),
        _ => '',
      };
      if (value.isNotEmpty || category == 'Mutation') values.add(value);
    }
    final result = values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  Set<String> _setFor(String category) => switch (category) {
        'Species' => species,
        'Name' => names,
        'Gender' => genders,
        'Mutation' => mutations,
        'Age Group' => ages,
        _ => <String>{},
      };

  String _valueFor(Map<String, dynamic> bird, String category) =>
      switch (category) {
        'Species' => bird['speciesName']?.toString().trim() ?? '',
        'Name' => bird['name']?.toString().trim() ?? '',
        'Gender' => bird['gender']?.toString().trim() ?? 'Unknown',
        'Mutation' => bird['mutation']?.toString().trim() ?? '',
        'Age Group' => widget.ageGroupFor(bird),
        _ => '',
      };

  bool _matchesOtherCategories(Map<String, dynamic> bird, String ignored) {
    bool check(String category, Set<String> selected) {
      if (category == ignored || selected.isEmpty) return true;
      return selected.contains(_valueFor(bird, category));
    }

    return check('Species', species) &&
        check('Name', names) &&
        check('Gender', genders) &&
        check('Mutation', mutations) &&
        check('Age Group', ages);
  }

  bool _available(String category, String option) {
    if (_setFor(category).contains(option)) return true;
    return widget.birds.any(
      (bird) =>
          _matchesOtherCategories(bird, category) &&
          _valueFor(bird, category) == option,
    );
  }

  void _pruneOtherSelections(String preservedCategory) {
    const categories = ['Species', 'Name', 'Gender', 'Mutation', 'Age Group'];
    for (final category in categories) {
      if (category == preservedCategory) continue;
      final selected = _setFor(category);
      selected.removeWhere(
        (option) => !widget.birds.any(
          (bird) =>
              _matchesOtherCategories(bird, category) &&
              _valueFor(bird, category) == option,
        ),
      );
    }
  }

  int get _matchingCount => widget.birds.where((bird) {
        bool check(String category, Set<String> selected) =>
            selected.isEmpty || selected.contains(_valueFor(bird, category));
        return check('Species', species) &&
            check('Name', names) &&
            check('Gender', genders) &&
            check('Mutation', mutations) &&
            check('Age Group', ages);
      }).length;

  Widget _category(String title) {
    final selected = _setFor(title);
    final options = _options(title);
    return Card(
      child: ExpansionTile(
        initiallyExpanded: title == 'Species' || title == 'Mutation',
        title: Text(
          selected.isEmpty ? title : '$title (${selected.length})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        children: options.map((option) {
          final enabled = _available(title, option);
          return CheckboxListTile(
            value: selected.contains(option),
            title: Text(
              title == 'Mutation' && option.isEmpty ? 'No mutation' : option,
              style: TextStyle(
                color: enabled
                    ? null
                    : Theme.of(context).disabledColor,
              ),
            ),
            onChanged: enabled
                ? (checked) {
                    setState(() {
                      if (checked == true) {
                        selected.add(option);
                      } else {
                        selected.remove(option);
                      }
                      _pruneOtherSelections(title);
                    });
                  }
                : null,
          );
        }).toList(),
      ),
    );
  }

  void _clear() {
    setState(() {
      species.clear();
      names.clear();
      genders.clear();
      mutations.clear();
      ages.clear();
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _BirdFilterSelection(
        species: {...species},
        names: {...names},
        genders: {...genders},
        mutations: {...mutations},
        ages: {...ages},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Filter Birds')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
        children: [
          Card(
            color: aviaryCardSurface(
              context,
              tint: AviaryColors.birds.withValues(alpha: .10),
            ),
            child: ListTile(
              leading: const Icon(Icons.filter_alt_outlined),
              title: Text(
                '$_matchingCount of ${widget.birds.length} birds match',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Select multiple values. Unavailable combinations are greyed out.',
              ),
            ),
          ),
          _category('Species'),
          _category('Name'),
          _category('Gender'),
          _category('Mutation'),
          _category('Age Group'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _clear,
                child: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _apply,
                child: Text('Apply ($_matchingCount)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BirdQuickEditScreen extends StatefulWidget {
  const _BirdQuickEditScreen({required this.count});

  final int count;

  @override
  State<_BirdQuickEditScreen> createState() => _BirdQuickEditScreenState();
}

class _BirdQuickEditScreenState extends State<_BirdQuickEditScreen> {
  final nameController = TextEditingController();
  final mutationController = TextEditingController();
  bool editName = false;
  bool editMutation = false;
  bool editGender = false;
  String gender = 'Unknown';

  @override
  void dispose() {
    nameController.dispose();
    mutationController.dispose();
    super.dispose();
  }

  void _save() {
    final changes = <String, dynamic>{};
    if (editName) changes['name'] = nameController.text.trim();
    if (editMutation) changes['mutation'] = mutationController.text.trim();
    if (editGender) changes['gender'] = gender;
    if (changes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one field to edit')),
      );
      return;
    }
    Navigator.pop(context, changes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Quick Edit ${widget.count} Birds')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: editName,
            title: const Text('Change Name'),
            subtitle: const Text('Applies the same name to every selected bird'),
            onChanged: (value) => setState(() => editName = value ?? false),
          ),
          if (editName)
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'New Name',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 10),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: editMutation,
            title: const Text('Change Mutation'),
            onChanged: (value) => setState(() => editMutation = value ?? false),
          ),
          if (editMutation)
            TextField(
              controller: mutationController,
              decoration: const InputDecoration(
                labelText: 'New Mutation',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 10),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: editGender,
            title: const Text('Change Gender'),
            onChanged: (value) => setState(() => editGender = value ?? false),
          ),
          if (editGender)
            DropdownButtonFormField<String>(
              initialValue: gender,
              decoration: const InputDecoration(
                labelText: 'Gender',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Male', child: Text('Male')),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Unknown', child: Text('Unknown')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => gender = value);
              },
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.done_all),
            label: const Text('Apply to Selected Birds'),
          ),
          const SizedBox(height: 8),
          const Text(
            'An Undo option will be available after the bulk edit is applied.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
