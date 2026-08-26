import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';

class SelectFosterClutchScreen extends StatefulWidget {
  final String? excludedClutchId;

  const SelectFosterClutchScreen({
    super.key,
    this.excludedClutchId,
  });

  @override
  State<SelectFosterClutchScreen> createState() =>
      _SelectFosterClutchScreenState();
}

class _SelectFosterClutchScreenState
    extends State<SelectFosterClutchScreen> {
  static const newClutchValue = '__new__';

  List<Map<String, dynamic>> pairs = [];
  List<Map<String, dynamic>> clutches = [];
  String? pairId;
  String? clutchValue;
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _loadPairs();
  }

  Future<void> _loadPairs() async {
    final rows = await DatabaseHelper.instance.getActivePairsForSelection();
    if (!mounted) return;
    setState(() {
      pairs = rows;
      loading = false;
    });
  }

  Future<void> _loadClutches(String selectedPairId) async {
    final rows = await DatabaseHelper.instance
        .getActiveClutchesForPair(selectedPairId);
    final filtered = rows
        .where((row) => row['id'].toString() != widget.excludedClutchId)
        .toList();
    if (!mounted) return;
    setState(() {
      clutches = filtered;
      clutchValue = filtered.isEmpty
          ? newClutchValue
          : filtered.first['id'].toString();
    });
  }

  Widget _pairLabel(Map<String, dynamic> pair) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${pair['cageIdentifier'] ?? 'No cage'} — '
                '${pair['identifier'] ?? 'Pair'} — ',
          ),
          TextSpan(
            text: pair['maleRingNumber']?.toString() ?? 'Male',
            style: TextStyle(
              color: birdGenderTextColor(pair['maleGender']?.toString()),
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: ' × '),
          TextSpan(
            text: pair['femaleRingNumber']?.toString() ?? 'Female',
            style: TextStyle(
              color: birdGenderTextColor(pair['femaleGender']?.toString()),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  Future<void> _continue() async {
    final selectedPairId = pairId;
    final selectedClutch = clutchValue;
    if (selectedPairId == null || selectedClutch == null) return;
    setState(() => saving = true);

    try {
      final clutchId = selectedClutch == newClutchValue
          ? await DatabaseHelper.instance.createClutch(
              pairId: selectedPairId,
              startedAt: DateTime.now(),
              notes: 'Created automatically for fostering',
            )
          : selectedClutch;
      if (!mounted) return;
      Navigator.pop(context, clutchId);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Foster Nest')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('foster_pair_$pairId'),
                  initialValue: pairId,
                  decoration: const InputDecoration(
                    labelText: 'Foster Pair',
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items: pairs.map((pair) {
                    return DropdownMenuItem<String>(
                      value: pair['id'].toString(),
                      child: _pairLabel(pair),
                    );
                  }).toList(),
                  onChanged: saving
                      ? null
                      : (value) async {
                          if (value == null) return;
                          setState(() {
                            pairId = value;
                            clutches = [];
                            clutchValue = null;
                          });
                          await _loadClutches(value);
                        },
                ),
                const SizedBox(height: 16),
                if (pairId != null)
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'foster_clutch_${pairId}_${clutchValue}_${clutches.length}',
                    ),
                    initialValue: clutchValue,
                    decoration: const InputDecoration(
                      labelText: 'Foster Clutch',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      ...clutches.map((clutch) {
                        return DropdownMenuItem<String>(
                          value: clutch['id'].toString(),
                          child: Text(
                            'Clutch ${clutch['clutchNumber']} — '
                            '${clutch['activeEggs'] ?? 0} eggs, '
                            '${clutch['chicksInNest'] ?? 0} chicks',
                          ),
                        );
                      }),
                      const DropdownMenuItem(
                        value: newClutchValue,
                        child: Text('Create New Foster Clutch'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => setState(() => clutchValue = value),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: saving || pairId == null || clutchValue == null
                      ? null
                      : _continue,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(saving ? 'SAVING...' : 'USE FOSTER NEST'),
                ),
              ],
            ),
    );
  }
}
