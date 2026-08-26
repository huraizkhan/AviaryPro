import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';

class AddEggScreen extends StatefulWidget {
  final String? pairId;
  final String? clutchId;

  const AddEggScreen({
    super.key,
    this.pairId,
    this.clutchId,
  });

  @override
  State<AddEggScreen> createState() => _AddEggScreenState();
}

class _AddEggScreenState extends State<AddEggScreen> {
  static const automaticValue = '__automatic__';
  static const newClutchValue = '__new_clutch__';

  final notesController = TextEditingController();
  final dateFormat = DateFormat('dd-MMM-yy');

  List<Map<String, dynamic>> pairs = [];
  List<Map<String, dynamic>> clutches = [];
  String? selectedPairId;
  String selectedClutchValue = automaticValue;
  DateTime laidDate = DateTime.now();
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    selectedPairId = widget.pairId;
    _loadPairs();
  }

  @override
  void dispose() {
    notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPairs() async {
    final rows = await DatabaseHelper.instance.getActivePairsForSelection();
    if (!mounted) return;

    var pairId = selectedPairId;
    if (pairId == null && rows.length == 1) {
      pairId = rows.first['id'].toString();
    }

    setState(() {
      pairs = rows;
      selectedPairId = pairId;
      isLoading = false;
    });

    if (pairId != null) {
      await _loadClutches(pairId);
    }
  }

  Future<void> _loadClutches(String pairId) async {
    final rows = await DatabaseHelper.instance.getActiveClutchesForPair(pairId);
    if (!mounted) return;

    var nextValue = automaticValue;
    if (widget.clutchId != null &&
        rows.any((row) => row['id'].toString() == widget.clutchId)) {
      nextValue = widget.clutchId!;
    }

    setState(() {
      clutches = rows;
      selectedClutchValue = nextValue;
    });
  }

  String _birdLabel(Map<String, dynamic> pair, String prefix) {
    final ring = pair['${prefix}RingNumber']?.toString() ?? 'No ring';
    final name = pair['${prefix}Name']?.toString().trim() ?? '';
    return name.isEmpty ? ring : '$ring ($name)';
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
            text: _birdLabel(pair, 'male'),
            style: TextStyle(
              color: birdGenderTextColor(pair['maleGender']?.toString()),
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: ' × '),
          TextSpan(
            text: _birdLabel(pair, 'female'),
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

  String _clutchLabel(Map<String, dynamic> clutch) {
    final number = clutch['clutchNumber'] ?? '?';
    final eggs = (clutch['activeEggs'] as num?)?.toInt() ?? 0;
    final chicks = (clutch['chicksInNest'] as num?)?.toInt() ?? 0;
    return 'Clutch $number — $eggs eggs, $chicks chicks';
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: laidDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    setState(() => laidDate = date);
  }

  Future<void> _save() async {
    final pairId = selectedPairId;
    if (pairId == null) {
      _message('Select a pair first');
      return;
    }
    if (isSaving) return;

    setState(() => isSaving = true);
    try {
      final selectedClutchId =
          selectedClutchValue == automaticValue ||
                  selectedClutchValue == newClutchValue
              ? null
              : selectedClutchValue;

      await DatabaseHelper.instance.addEggAutomatically(
        eggId: const Uuid().v4(),
        pairId: pairId,
        laidDate: laidDate,
        selectedClutchId: selectedClutchId,
        createNewClutch: selectedClutchValue == newClutchValue,
        notes: notesController.text,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => isSaving = false);
      _message(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add Egg')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (pairs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Create an active pair first. Both birds must be in the same cage.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else ...[
            DropdownButtonFormField<String>(
              key: ValueKey('pair_$selectedPairId'),
              initialValue: selectedPairId,
              decoration: const InputDecoration(
                labelText: 'Pair',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: pairs.map((pair) {
                return DropdownMenuItem<String>(
                  value: pair['id'].toString(),
                  child: _pairLabel(pair),
                );
              }).toList(),
              onChanged: isSaving
                  ? null
                  : (value) async {
                      if (value == null) return;
                      setState(() {
                        selectedPairId = value;
                        clutches = [];
                        selectedClutchValue = automaticValue;
                      });
                      await _loadClutches(value);
                    },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'clutch_${selectedPairId}_${selectedClutchValue}_${clutches.length}',
              ),
              initialValue: selectedClutchValue,
              decoration: const InputDecoration(
                labelText: 'Clutch',
                border: OutlineInputBorder(),
                helperText: 'Automatic uses the species clutch window.',
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem(
                  value: automaticValue,
                  child: Text('Automatic (recommended)'),
                ),
                ...clutches.map((clutch) {
                  return DropdownMenuItem<String>(
                    value: clutch['id'].toString(),
                    child: Text(_clutchLabel(clutch)),
                  );
                }),
                const DropdownMenuItem(
                  value: newClutchValue,
                  child: Text('Create New Clutch Automatically'),
                ),
              ],
              onChanged: isSaving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => selectedClutchValue = value);
                      }
                    },
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: isSaving ? null : _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Egg laid date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_month),
                ),
                child: Text(dateFormat.format(laidDate)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: isSaving ? null : _save,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.egg_outlined),
              label: Text(isSaving ? 'SAVING...' : 'SAVE EGG'),
            ),
          ],
        ],
      ),
    );
  }
}
