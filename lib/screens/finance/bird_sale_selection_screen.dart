import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';

enum _SaleBirdView { byCage, allBirds }

class BirdSaleSelectionScreen extends StatefulWidget {
  const BirdSaleSelectionScreen({
    super.key,
    this.initialSelectedIds = const <String>{},
  });

  final Set<String> initialSelectedIds;

  @override
  State<BirdSaleSelectionScreen> createState() => _BirdSaleSelectionScreenState();
}

class _BirdSaleSelectionScreenState extends State<BirdSaleSelectionScreen> {
  _SaleBirdView _view = _SaleBirdView.byCage;
  List<Map<String, dynamic>> _birds = const [];
  bool _loading = true;
  late Set<String> _selected;
  Set<String> _species = <String>{};
  Set<String> _names = <String>{};
  Set<String> _mutations = <String>{};
  Set<String> _genders = <String>{};
  Set<String> _ages = <String>{};

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelectedIds};
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getBirds();
    if (!mounted) return;
    setState(() {
      _birds = rows.where((bird) => bird['active'] != 0).toList();
      _selected.removeWhere(
        (id) => !_birds.any((bird) => bird['id']?.toString() == id),
      );
      _loading = false;
    });
  }

  DateTime? _birth(Map<String, dynamic> bird) {
    final hatch = DateTime.tryParse(bird['hatchDate']?.toString() ?? '');
    if (hatch != null) return hatch;
    final source = DateTime.tryParse(bird['sourceDate']?.toString() ?? '');
    final days = (bird['estimatedAgeDays'] as num?)?.toInt();
    if (source == null || days == null) return null;
    return source.subtract(Duration(days: days));
  }

  int _naturalCompare(String left, String right) {
    final pattern = RegExp(r'(\d+|\D+)');
    final a = pattern
        .allMatches(left.toLowerCase())
        .map((match) => match.group(0)!)
        .toList();
    final b = pattern
        .allMatches(right.toLowerCase())
        .map((match) => match.group(0)!)
        .toList();
    final length = a.length < b.length ? a.length : b.length;
    for (var index = 0; index < length; index++) {
      final an = int.tryParse(a[index]);
      final bn = int.tryParse(b[index]);
      final result = an != null && bn != null
          ? an.compareTo(bn)
          : a[index].compareTo(b[index]);
      if (result != 0) return result;
    }
    return a.length.compareTo(b.length);
  }

  String _ageGroup(Map<String, dynamic> bird) {
    final birth = _birth(bird);
    if (birth == null) return bird['ageGroup']?.toString() ?? 'Unknown';
    final now = DateTime.now();
    var months = (now.year - birth.year) * 12 + now.month - birth.month;
    if (now.day < birth.day) months--;
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(birth.year, birth.month, birth.day))
        .inDays;
    final adult = (bird['adultAgeMonths'] as num?)?.toInt();
    final young = (bird['chickToYoungDays'] as num?)?.toInt();
    if (adult != null && months >= adult) return 'Adult';
    if (young != null && days >= young) return 'Young';
    return 'Chick';
  }

  List<Map<String, dynamic>> get _visible {
    final result = _birds.where((bird) {
      final species = bird['speciesName']?.toString().trim() ?? '';
      final name = bird['name']?.toString().trim() ?? '';
      final mutation = bird['mutation']?.toString().trim() ?? '';
      final gender = bird['gender']?.toString() ?? 'Unknown';
      final age = _ageGroup(bird);
      return (_species.isEmpty || _species.contains(species)) &&
          (_names.isEmpty || _names.contains(name)) &&
          (_mutations.isEmpty || _mutations.contains(mutation)) &&
          (_genders.isEmpty || _genders.contains(gender)) &&
          (_ages.isEmpty || _ages.contains(age));
    }).toList();
    result.sort(
      (a, b) => _naturalCompare(
        a['ringNumber']?.toString() ?? '',
        b['ringNumber']?.toString() ?? '',
      ),
    );
    return result;
  }

  int get _filterCount => [_species, _names, _mutations, _genders, _ages]
      .where((set) => set.isNotEmpty)
      .length;

  Future<void> _filter() async {
    final result = await Navigator.push<_SaleFilterValues>(
      context,
      MaterialPageRoute(
        builder: (_) => _SaleFilterScreen(
          birds: _birds,
          ageGroupFor: _ageGroup,
          initial: _SaleFilterValues(
            species: {..._species},
            names: {..._names},
            mutations: {..._mutations},
            genders: {..._genders},
            ages: {..._ages},
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _species = result.species;
      _names = result.names;
      _mutations = result.mutations;
      _genders = result.genders;
      _ages = result.ages;
    });
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _selectAllVisible() {
    final ids = _visible.map((bird) => bird['id'].toString()).toSet();
    final all = ids.isNotEmpty && ids.every(_selected.contains);
    setState(() {
      if (all) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  Widget _birdTile(Map<String, dynamic> bird) {
    final id = bird['id'].toString();
    final ring = bird['ringNumber']?.toString() ?? 'No ring';
    final name = bird['name']?.toString().trim() ?? '';
    final mutation = bird['mutation']?.toString().trim() ?? '';
    return CheckboxListTile(
      value: _selected.contains(id),
      secondary: const AviaryIcon(AviaryIconType.bird),
      title: Text(
        name.isEmpty ? ring : '$ring — $name',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: birdGenderTextColor(bird['gender']?.toString()),
        ),
      ),
      subtitle: Text(
        '${bird['speciesName'] ?? 'Unknown species'}'
        '${mutation.isEmpty ? '' : ' · $mutation'} · ${bird['gender'] ?? 'Unknown'}',
      ),
      onChanged: (_) => _toggle(id),
    );
  }

  Widget _byCage() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final bird in _visible) {
      final cage = bird['cageIdentifier']?.toString() ?? 'No Cage';
      grouped.putIfAbsent(cage, () => []).add(bird);
    }
    if (grouped.isEmpty) return const Center(child: Text('No birds match filters'));
    final keys = grouped.keys.toList()..sort();
    return Column(
      children: keys.map((cage) {
        final birds = grouped[cage]!;
        final selectedCount = birds
            .where((bird) => _selected.contains(bird['id'].toString()))
            .length;
        return Card(
          child: ExpansionTile(
            leading: const AviaryIcon(AviaryIconType.cage),
            title: Text(
              cage == 'No Cage' ? cage : aviaryCageLabel(cage),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text('${birds.length} birds · $selectedCount selected'),
            children: birds.map(_birdTile).toList(),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleIds = _visible.map((bird) => bird['id'].toString()).toSet();
    final allVisible = visibleIds.isNotEmpty && visibleIds.every(_selected.contains);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Birds for Sale'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () {
                    final selectedBirds = _birds
                        .where((bird) => _selected.contains(bird['id'].toString()))
                        .toList();
                    Navigator.pop(context, selectedBirds);
                  },
            child: Text('Done (${_selected.length})'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  AviarySegmentedControl<_SaleBirdView>(
                    items: const [
                      (_SaleBirdView.byCage, 'Cages'),
                      (_SaleBirdView.allBirds, 'All Birds'),
                    ],
                    selected: _view,
                    accent: AviaryColors.finance,
                    onChanged: (value) => setState(() => _view = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _filter,
                          icon: const Icon(Icons.filter_alt_outlined),
                          label: Text(_filterCount == 0 ? 'Filter' : 'Filter ($_filterCount)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _visible.isEmpty ? null : _selectAllVisible,
                          icon: Icon(allVisible ? Icons.deselect : Icons.select_all),
                          label: Text(allVisible ? 'Deselect All' : 'Select All'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_visible.length} birds · ${_selected.length} selected',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_view == _SaleBirdView.byCage)
                    _byCage()
                  else if (_visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No birds match filters')),
                    )
                  else
                    ..._visible.map(
                      (bird) => Card(child: _birdTile(bird)),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SaleFilterValues {
  _SaleFilterValues({
    required this.species,
    required this.names,
    required this.mutations,
    required this.genders,
    required this.ages,
  });

  final Set<String> species;
  final Set<String> names;
  final Set<String> mutations;
  final Set<String> genders;
  final Set<String> ages;
}

class _SaleFilterScreen extends StatefulWidget {
  const _SaleFilterScreen({
    required this.birds,
    required this.ageGroupFor,
    required this.initial,
  });

  final List<Map<String, dynamic>> birds;
  final String Function(Map<String, dynamic>) ageGroupFor;
  final _SaleFilterValues initial;

  @override
  State<_SaleFilterScreen> createState() => _SaleFilterScreenState();
}

class _SaleFilterScreenState extends State<_SaleFilterScreen> {
  late Set<String> species;
  late Set<String> names;
  late Set<String> mutations;
  late Set<String> genders;
  late Set<String> ages;

  @override
  void initState() {
    super.initState();
    species = {...widget.initial.species};
    names = {...widget.initial.names};
    mutations = {...widget.initial.mutations};
    genders = {...widget.initial.genders};
    ages = {...widget.initial.ages};
  }

  Set<String> _options(String type) {
    final result = <String>{};
    for (final bird in widget.birds) {
      final value = switch (type) {
        'Species' => bird['speciesName']?.toString().trim() ?? '',
        'Name' => bird['name']?.toString().trim() ?? '',
        'Mutation' => bird['mutation']?.toString().trim() ?? '',
        'Gender' => bird['gender']?.toString() ?? 'Unknown',
        'Age Group' => widget.ageGroupFor(bird),
        _ => '',
      };
      if (value.isNotEmpty) result.add(value);
    }
    return result;
  }

  Set<String> _selected(String type) => switch (type) {
        'Species' => species,
        'Name' => names,
        'Mutation' => mutations,
        'Gender' => genders,
        'Age Group' => ages,
        _ => <String>{},
      };

  String _value(Map<String, dynamic> bird, String type) => switch (type) {
        'Species' => bird['speciesName']?.toString().trim() ?? '',
        'Name' => bird['name']?.toString().trim() ?? '',
        'Mutation' => bird['mutation']?.toString().trim() ?? '',
        'Gender' => bird['gender']?.toString() ?? 'Unknown',
        'Age Group' => widget.ageGroupFor(bird),
        _ => '',
      };

  bool _matchesOther(Map<String, dynamic> bird, String ignored) {
    bool test(String type, Set<String> selected) =>
        type == ignored || selected.isEmpty || selected.contains(_value(bird, type));
    return test('Species', species) &&
        test('Name', names) &&
        test('Mutation', mutations) &&
        test('Gender', genders) &&
        test('Age Group', ages);
  }

  bool _available(String type, String option) {
    if (_selected(type).contains(option)) return true;
    return widget.birds.any(
      (bird) => _matchesOther(bird, type) && _value(bird, type) == option,
    );
  }

  void _pruneOtherSelections(String preservedType) {
    const types = ['Species', 'Name', 'Mutation', 'Gender', 'Age Group'];
    for (final type in types) {
      if (type == preservedType) continue;
      final selected = _selected(type);
      selected.removeWhere(
        (option) => !widget.birds.any(
          (bird) => _matchesOther(bird, type) && _value(bird, type) == option,
        ),
      );
    }
  }

  int get matching => widget.birds.where((bird) {
        bool test(String type, Set<String> selected) =>
            selected.isEmpty || selected.contains(_value(bird, type));
        return test('Species', species) &&
            test('Name', names) &&
            test('Mutation', mutations) &&
            test('Gender', genders) &&
            test('Age Group', ages);
      }).length;

  Widget _section(String type) {
    final selected = _selected(type);
    final options = _options(type).toList()..sort();
    return Card(
      child: ExpansionTile(
        initiallyExpanded: type == 'Species' || type == 'Mutation',
        title: Text(selected.isEmpty ? type : '$type (${selected.length})'),
        children: options.map((option) {
          final enabled = _available(type, option);
          return CheckboxListTile(
            value: selected.contains(option),
            title: Text(option),
            onChanged: enabled
                ? (checked) {
                    setState(() {
                      if (checked == true) {
                        selected.add(option);
                      } else {
                        selected.remove(option);
                      }
                      _pruneOtherSelections(type);
                    });
                  }
                : null,
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Filter Sale Birds')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          ListTile(
            title: Text('$matching of ${widget.birds.length} birds match'),
            subtitle: const Text('Unavailable combinations are disabled.'),
          ),
          _section('Species'),
          _section('Name'),
          _section('Mutation'),
          _section('Gender'),
          _section('Age Group'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  species.clear();
                  names.clear();
                  mutations.clear();
                  genders.clear();
                  ages.clear();
                }),
                child: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _SaleFilterValues(
                    species: {...species},
                    names: {...names},
                    mutations: {...mutations},
                    genders: {...genders},
                    ages: {...ages},
                  ),
                ),
                child: Text('Apply ($matching)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
