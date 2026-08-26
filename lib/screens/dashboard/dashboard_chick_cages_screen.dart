import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../birds/bird_details_screen.dart';
import '../cages/cage_details_screen.dart';

enum _ChickView { byCage, allChicks }

class DashboardChickCagesScreen extends StatefulWidget {
  const DashboardChickCagesScreen({super.key});

  @override
  State<DashboardChickCagesScreen> createState() =>
      _DashboardChickCagesScreenState();
}

class _DashboardChickCagesScreenState extends State<DashboardChickCagesScreen> {
  List<Map<String, dynamic>> _cages = const [];
  List<Map<String, dynamic>> _chicks = const [];
  _ChickView _view = _ChickView.byCage;
  String _countMode = 'Mutation';
  String? _selectedCountValue;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCountMode();
  }

  Future<void> _loadCountMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('all_chicks_count_mode');
    if (!mounted || saved == null) return;
    if (const {'Mutation', 'Species', 'Name', 'Gender'}.contains(saved)) {
      setState(() => _countMode = saved);
    }
  }

  Future<void> _setCountMode(String value) async {
    setState(() {
      _countMode = value;
      _selectedCountValue = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('all_chicks_count_mode', value);
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getCagesWithChicks(),
      DatabaseHelper.instance.getChicksWithParents(),
    ]);
    if (!mounted) return;
    setState(() {
      _cages = results[0] as List<Map<String, dynamic>>;
      _chicks = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  String _countValue(Map<String, dynamic> chick) {
    return switch (_countMode) {
      'Species' => chick['speciesName']?.toString().trim() ?? '',
      'Name' => chick['name']?.toString().trim() ?? '',
      'Gender' => chick['gender']?.toString().trim() ?? 'Unknown',
      _ => chick['mutation']?.toString().trim() ?? '',
    };
  }

  String _countDisplay(String value) {
    if (value.isNotEmpty) return value;
    return switch (_countMode) {
      'Name' => 'Unnamed',
      'Mutation' => 'No mutation',
      _ => 'Unknown',
    };
  }

  String _birdLabel(String? ring, String? name) {
    final cleanRing = ring?.trim() ?? '';
    final cleanName = name?.trim() ?? '';
    if (cleanRing.isEmpty) return cleanName.isEmpty ? 'Unknown' : cleanName;
    return cleanName.isEmpty ? cleanRing : '$cleanRing $cleanName';
  }

  String _parentsLabel(Map<String, dynamic> chick) {
    final father = _birdLabel(
      chick['fatherRingNumber']?.toString(),
      chick['fatherName']?.toString(),
    );
    final mother = _birdLabel(
      chick['motherRingNumber']?.toString(),
      chick['motherName']?.toString(),
    );
    return '$father × $mother';
  }

  List<Map<String, dynamic>> get _visibleChicks {
    final value = _selectedCountValue;
    if (value == null) return _chicks;
    return _chicks.where((chick) => _countValue(chick) == value).toList();
  }

  Widget _countSummary() {
    final counts = <String, int>{};
    for (final chick in _chicks) {
      final value = _countValue(chick);
      counts[value] = (counts[value] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final countResult = b.value.compareTo(a.value);
        if (countResult != 0) return countResult;
        return _countDisplay(a.key)
            .toLowerCase()
            .compareTo(_countDisplay(b.key).toLowerCase());
      });
    return Card(
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
                  value: _countMode,
                  items: const ['Mutation', 'Species', 'Name', 'Gender']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _setCountMode(value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entries
                  .map(
                    (entry) => FilterChip(
                      selected: _selectedCountValue == entry.key,
                      label: Text('${_countDisplay(entry.key)} ${entry.value}'),
                      onSelected: (selected) => setState(
                        () => _selectedCountValue = selected ? entry.key : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChick(Map<String, dynamic> chick) async {
    final bird = await DatabaseHelper.instance.getBirdById(chick['id'].toString());
    if (!mounted || bird == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: bird)),
    );
    if (mounted) await _load();
  }

  Widget _allChicksView() {
    final chicks = _visibleChicks;
    if (_chicks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 150),
        child: Center(child: Text('No chicks currently in nests.')),
      );
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final chick in chicks) {
      final pair = chick['parentPairIdentifier']?.toString().trim();
      final key = pair == null || pair.isEmpty ? 'Parents unknown' : pair;
      grouped.putIfAbsent(key, () => []).add(chick);
    }

    return Column(
      children: [
        _countSummary(),
        const SizedBox(height: 10),
        if (chicks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('No chicks match this count pill.'),
          )
        else
          ...grouped.entries.map((group) {
            final first = group.value.first;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${group.key} · ${_parentsLabel(first)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const Divider(),
                      ...group.value.map((chick) {
                        final ring = chick['ringNumber']?.toString() ?? 'Chick';
                        final name = chick['name']?.toString().trim() ?? '';
                        final species = chick['speciesName']?.toString() ?? '';
                        final mutation = chick['mutation']?.toString().trim() ?? '';
                        final gender = chick['gender']?.toString() ?? 'Unknown';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: AviaryIcon(AviaryIconType.chick),
                          ),
                          title: Text(
                            name.isEmpty ? ring : '$ring — $name',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: birdGenderTextColor(gender),
                            ),
                          ),
                          subtitle: Text(
                            [
                              species,
                              if (mutation.isNotEmpty) mutation,
                              gender,
                              'Parents: ${_parentsLabel(chick)}',
                            ].where((value) => value.isNotEmpty).join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openChick(chick),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _cagesView() {
    if (_cages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 150),
        child: Center(child: Text('No cages currently have chicks.')),
      );
    }
    return Column(
      children: _cages.map((cage) {
        final count = (cage['chickCount'] as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: AviaryIcon(AviaryIconType.chick),
              ),
              title: Text(
                cage['identifier']?.toString() ?? 'Cage',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('$count chick${count == 1 ? '' : 's'} in nest'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CageDetailsScreen(
                      cageId: cage['id'].toString(),
                    ),
                  ),
                );
                if (mounted) await _load();
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chicks')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                children: [
                  AviarySegmentedControl<_ChickView>(
                    items: const [
                      (_ChickView.byCage, 'By Cage'),
                      (_ChickView.allChicks, 'All Chicks'),
                    ],
                    selected: _view,
                    accent: AviaryColors.birds,
                    onChanged: (value) => setState(() => _view = value),
                  ),
                  const SizedBox(height: 12),
                  if (_view == _ChickView.byCage) _cagesView() else _allChicksView(),
                ],
              ),
            ),
    );
  }
}
