import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../finance/bird_sale_selection_screen.dart';

class BirdValueCalculatorScreen extends StatefulWidget {
  const BirdValueCalculatorScreen({super.key});

  @override
  State<BirdValueCalculatorScreen> createState() => _BirdValueCalculatorScreenState();
}

class _BirdValueCalculatorScreenState extends State<BirdValueCalculatorScreen> {
  final _money = NumberFormat('#,##0');
  List<Map<String, dynamic>> _allBirds = const [];
  Set<String> _selectedIds = <String>{};
  final Map<String, TextEditingController> _priceControllers = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _priceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _age(Map<String, dynamic> bird) =>
      bird['ageGroup']?.toString().trim().isNotEmpty == true
          ? bird['ageGroup'].toString().trim()
          : 'Unknown';

  String _mutation(Map<String, dynamic> bird) {
    final value = bird['mutation']?.toString().trim() ?? '';
    return value.isEmpty ? 'No mutation' : value;
  }

  String _groupKey(Map<String, dynamic> bird) =>
      '${bird['speciesId'] ?? ''}|${_mutation(bird).toLowerCase()}|${_age(bird).toLowerCase()}';

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getBirds(),
      DatabaseHelper.instance.getSalePriceGuides(),
    ]);
    if (!mounted) return;
    final birds = (results[0] as List<Map<String, dynamic>>)
        .where((bird) => (bird['active'] as num?)?.toInt() != 0)
        .toList();
    final guides = results[1] as List<Map<String, dynamic>>;
    final guideMap = <String, double>{};
    for (final guide in guides) {
      final key = '${guide['speciesId'] ?? ''}|'
          '${(guide['mutation']?.toString().trim().isEmpty ?? true) ? 'no mutation' : guide['mutation'].toString().trim().toLowerCase()}|'
          '${guide['ageGroup']?.toString().trim().toLowerCase() ?? 'unknown'}';
      guideMap[key] = (guide['price'] as num?)?.toDouble() ?? 0;
    }

    for (final bird in birds) {
      final key = _groupKey(bird);
      _priceControllers.putIfAbsent(
        key,
        () => TextEditingController(
          text: guideMap[key] == null || guideMap[key]! <= 0
              ? ''
              : guideMap[key]!.toStringAsFixed(0),
        ),
      );
    }
    final forSale = birds
        .where((bird) => const {'Available', 'Reserved'}.contains(bird['saleStatus']))
        .map((bird) => bird['id'].toString())
        .toSet();
    setState(() {
      _allBirds = birds;
      _selectedIds = forSale.isEmpty
          ? birds.map((bird) => bird['id'].toString()).toSet()
          : forSale;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _selected => _allBirds
      .where((bird) => _selectedIds.contains(bird['id'].toString()))
      .toList();

  Map<String, List<Map<String, dynamic>>> get _groups {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final bird in _selected) {
      result.putIfAbsent(_groupKey(bird), () => []).add(bird);
    }
    return result;
  }

  double _groupPrice(String key) =>
      double.tryParse(_priceControllers[key]?.text.trim() ?? '') ?? 0;

  double get _total {
    var value = 0.0;
    for (final entry in _groups.entries) {
      value += _groupPrice(entry.key) * entry.value.length;
    }
    return value;
  }

  Future<void> _chooseBirds() async {
    final selected = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => BirdSaleSelectionScreen(initialSelectedIds: _selectedIds),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _selectedIds = selected.map((bird) => bird['id'].toString()).toSet();
    });
  }

  void _useForSale() {
    setState(() {
      _selectedIds = _allBirds
          .where((bird) => const {'Available', 'Reserved'}.contains(bird['saleStatus']))
          .map((bird) => bird['id'].toString())
          .toSet();
    });
  }

  void _useAll() {
    setState(() {
      _selectedIds = _allBirds.map((bird) => bird['id'].toString()).toSet();
    });
  }

  Future<void> _saveGuides() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      for (final entry in _groups.entries) {
        final price = _groupPrice(entry.key);
        if (price <= 0 || entry.value.isEmpty) continue;
        final bird = entry.value.first;
        await DatabaseHelper.instance.setSalePriceGuide(
          speciesId: bird['speciesId'].toString(),
          mutation: bird['mutation']?.toString().trim() ?? '',
          ageGroup: _age(bird),
          price: price,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estimated bird prices saved.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showGroup(List<Map<String, dynamic>> birds) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              ListTile(
                title: Text('${birds.length} birds',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Birds included in this estimate group'),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: birds.length,
                  itemBuilder: (context, index) {
                    final bird = birds[index];
                    final ring = bird['ringNumber']?.toString() ?? 'No ring';
                    final name = bird['name']?.toString().trim() ?? '';
                    final eye = bird['eyeColor']?.toString().trim() ?? '';
                    return ListTile(
                      leading: const AviaryIcon(AviaryIconType.bird),
                      title: Text(
                        name.isEmpty ? ring : '$ring — $name',
                        style: TextStyle(
                          color: birdGenderTextColor(bird['gender']?.toString()),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${bird['cageIdentifier'] ?? 'No cage'}'
                        '${eye.isEmpty ? '' : ' · $eye eyes'}',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final entries = _groups.entries.toList()
      ..sort((a, b) {
        final left = a.value.first;
        final right = b.value.first;
        final l = '${left['speciesName']} ${_mutation(left)} ${_age(left)}';
        final r = '${right['speciesName']} ${_mutation(right)} ${_age(right)}';
        return l.toLowerCase().compareTo(r.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Bird Value Calculator')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          Card(
            color: AviaryColors.finance.withValues(alpha: .10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selected.length} birds selected',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(onPressed: _useForSale, child: const Text('For Sale')),
                      OutlinedButton(onPressed: _useAll, child: const Text('All Active')),
                      FilledButton.icon(
                        onPressed: _chooseBirds,
                        icon: const Icon(Icons.checklist),
                        label: const Text('Choose Birds'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              title: const Text('Estimated Total',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text(
                _money.format(_total),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AviaryColors.finance,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Select birds to calculate their estimated value.'),
              ),
            )
          else
            ...entries.map((entry) {
              final bird = entry.value.first;
              final price = _groupPrice(entry.key);
              final subtitle = <String>[
                '${entry.value.length} bird${entry.value.length == 1 ? '' : 's'}',
                if ((bird['eyeColor']?.toString().trim() ?? '').isNotEmpty)
                  '${bird['eyeColor']} eyes',
              ].join(' · ');
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _showGroup(entry.value),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${bird['speciesName'] ?? 'Species'} · ${_mutation(bird)} · ${_age(bird)}',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          Text(subtitle),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _priceControllers[entry.key],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Estimated price per bird',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Group: ${_money.format(price * entry.value.length)}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          if (entries.isNotEmpty)
            FilledButton.icon(
              onPressed: _saving ? null : _saveGuides,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'SAVING...' : 'SAVE ESTIMATED PRICES'),
            ),
        ],
      ),
    );
  }
}
