import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../../widgets/aviary_date_picker.dart';

class BulkBirdPurchaseScreen extends StatefulWidget {
  const BulkBirdPurchaseScreen({super.key});

  @override
  State<BulkBirdPurchaseScreen> createState() => _BulkBirdPurchaseScreenState();
}

class _BulkBirdPurchaseScreenState extends State<BulkBirdPurchaseScreen> {
  final _uuid = const Uuid();
  final _dateFormat = DateFormat('dd-MMM-yy');
  final _sellerController = TextEditingController();
  final _notesController = TextEditingController();
  final _sharedMutation = TextEditingController();
  final _sharedName = TextEditingController();
  final _sharedAgeYears = TextEditingController(text: '0');
  final _sharedAgeMonths = TextEditingController(text: '0');
  final _sharedAmount = TextEditingController();

  List<Map<String, dynamic>> _species = const [];
  List<Map<String, dynamic>> _cages = const [];
  List<String> _availableRings = const [];
  List<String> _managedMutations = const [];
  List<String> _managedNames = const [];
  bool _hasRingRange = false;
  String? _speciesId;
  String? _cageId;
  DateTime _date = DateTime.now();
  int _count = 1;
  bool _loading = true;
  bool _saving = false;

  bool _sameMutation = true;
  bool _sameName = false;
  bool _sameGender = true;
  bool _sameAge = true;
  bool _sameAmount = true;
  String _sharedGender = 'Unknown';

  final List<_PurchaseBirdEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _ensureEntries();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getSpecies(),
      DatabaseHelper.instance.getCages(),
    ]);
    if (!mounted) return;
    final species = results[0] as List<Map<String, dynamic>>;
    final cages = results[1] as List<Map<String, dynamic>>;
    setState(() {
      _species = species;
      _cages = cages;
      _speciesId ??= species.isEmpty ? null : species.first['id'].toString();
      _cageId ??= cages.isEmpty ? null : cages.first['id'].toString();
      _loading = false;
    });
    await _loadManagedOptions();
  }

  Future<void> _loadManagedOptions() async {
    final speciesId = _speciesId;
    if (speciesId == null) return;
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getAvailableRingNumbers(speciesId),
      DatabaseHelper.instance.getRingRanges(speciesId: speciesId),
      DatabaseHelper.instance.getManagedBirdValues(
        kind: 'Mutation',
        speciesId: speciesId,
      ),
      DatabaseHelper.instance.getManagedBirdValues(kind: 'Name'),
    ]);
    if (!mounted) return;
    setState(() {
      _availableRings = List<String>.from(results[0] as List<String>);
      _hasRingRange = (results[1] as List).isNotEmpty;
      _managedMutations = (results[2] as List<Map<String, dynamic>>)
          .map((row) => row['value'].toString())
          .toList();
      _managedNames = (results[3] as List<Map<String, dynamic>>)
          .map((row) => row['value'].toString())
          .toList();
    });
  }

  @override
  void dispose() {
    _sellerController.dispose();
    _notesController.dispose();
    _sharedMutation.dispose();
    _sharedName.dispose();
    _sharedAgeYears.dispose();
    _sharedAgeMonths.dispose();
    _sharedAmount.dispose();
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  void _ensureEntries() {
    while (_entries.length < _count) {
      _entries.add(_PurchaseBirdEntry());
    }
    while (_entries.length > _count) {
      _entries.removeLast().dispose();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showAviaryDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  int? _intValue(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  int? _ageDaysFor(_PurchaseBirdEntry entry) {
    final years = _intValue(_sameAge ? _sharedAgeYears : entry.ageYears);
    final months = _intValue(_sameAge ? _sharedAgeMonths : entry.ageMonths);
    if (years == null || months == null || years < 0 || months < 0) return null;
    return years * 365 + months * 30;
  }

  double? _priceFor(_PurchaseBirdEntry entry) {
    if (_sameAmount) {
      final total = double.tryParse(_sharedAmount.text.trim());
      if (total == null || _entries.isEmpty) return total;
      return total / _entries.length;
    }
    return double.tryParse(entry.amount.text.trim());
  }

  String _nameFor(_PurchaseBirdEntry entry) =>
      (_sameName ? _sharedName : entry.name).text.trim();

  String _mutationFor(_PurchaseBirdEntry entry) =>
      (_sameMutation ? _sharedMutation : entry.mutation).text.trim();

  String _genderFor(_PurchaseBirdEntry entry) =>
      _sameGender ? _sharedGender : entry.gender;

  String? _validate() {
    if (_speciesId == null) return 'Choose a species.';
    if (!_hasRingRange) {
      return 'Configure ring numbers for this species in Settings > Ring Management first.';
    }
    if (_cageId == null) return 'Choose a cage.';
    final rings = <String>{};
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      final ring = entry.ring.text.trim();
      if (ring.isEmpty) return 'Ring / ID is required for Bird ${i + 1}.';
      if (!rings.add(ring.toLowerCase())) {
        return 'Ring / ID "$ring" is repeated in this purchase.';
      }
      final ageDays = _ageDaysFor(entry);
      if (ageDays == null) return 'Enter a valid age for Bird ${i + 1}.';
      final price = _priceFor(entry);
      if (price == null || price <= 0) {
        return 'Enter a valid purchase amount for Bird ${i + 1}.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _saving = true);
    try {
      for (final entry in _entries) {
        final duplicate = await DatabaseHelper.instance.birdRingNumberExists(
          entry.ring.text.trim(),
        );
        if (duplicate) {
          throw StateError('Ring / ID ${entry.ring.text.trim()} already exists.');
        }
      }

      final rows = <Map<String, dynamic>>[];
      for (final entry in _entries) {
        final ageDays = _ageDaysFor(entry)!;
        rows.add({
          'id': _uuid.v4(),
          'ringNumber': entry.ring.text.trim(),
          'name': _nameFor(entry),
          'gender': _genderFor(entry),
          'mutation': _mutationFor(entry),
          'hatchDate': null,
          'speciesId': _speciesId,
          'ageGroup': null,
          'estimatedAgeDays': ageDays,
          'source': 'Purchase',
          'sourceDate': _date.toIso8601String(),
          'sourcePerson': _sellerController.text.trim(),
          'sourcePlace': null,
          'sourceDetails': null,
          'parentPairId': null,
          'purchasePrice': _priceFor(entry),
          'notes': _notesController.text.trim(),
          'cageId': _cageId,
          'nestClutchId': null,
          'leftNestDate': null,
          'saleStatus': 'Not for Sale',
        });
      }
      await DatabaseHelper.instance.insertPurchasedBirdBatch(rows);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Widget _sharedToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: value,
      title: Text('$label is same for all birds'),
      onChanged: _saving ? null : (checked) => onChanged(checked ?? false),
    );
  }

  Widget _managedTextField({
    required TextEditingController controller,
    required String label,
    required List<String> values,
  }) {
    final current = controller.text.trim();
    final options = <String>{...values, if (current.isNotEmpty) current}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return DropdownButtonFormField<String>(
      key: ValueKey('${label}_${controller.hashCode}_${current}_${values.length}'),
      initialValue: current.isEmpty ? '' : current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: values.isEmpty
            ? 'Add allowed values in Settings > ${label == 'Name' ? 'Bird Name' : 'Mutation'} Management.'
            : 'Choose a managed $label.',
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<String>(
          value: '',
          child: Text(label == 'Name' ? 'No name' : 'No mutation'),
        ),
        ...options.map(
          (value) => DropdownMenuItem<String>(value: value, child: Text(value)),
        ),
      ],
      onChanged: _saving
          ? null
          : (value) => setState(() => controller.text = value ?? ''),
    );
  }

  Widget _ringField(int index, _PurchaseBirdEntry entry) {
    final chosenByOthers = <String>{
      for (var i = 0; i < _entries.length; i++)
        if (i != index && _entries[i].ring.text.trim().isNotEmpty)
          _entries[i].ring.text.trim(),
    };
    final current = entry.ring.text.trim();
    final options = _availableRings
        .where((ring) => !chosenByOthers.contains(ring) || ring == current)
        .toList();
    if (current.isNotEmpty && !options.contains(current)) options.add(current);
    options.sort();
    return DropdownButtonFormField<String>(
      key: ValueKey('purchase_ring_${index}_$current'),
      initialValue: current.isEmpty ? null : current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Ring *',
        helperText: _hasRingRange
            ? 'Only available rings are shown.'
            : 'Configure rings in Settings > Ring Management.',
        border: const OutlineInputBorder(),
      ),
      items: options
          .map((ring) => DropdownMenuItem(value: ring, child: Text(ring)))
          .toList(),
      onChanged: _saving || !_hasRingRange
          ? null
          : (value) => setState(() => entry.ring.text = value ?? ''),
    );
  }

  Widget _genderField({required String value, required ValueChanged<String> onChanged}) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Gender',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'Male', child: Text('Male')),
        DropdownMenuItem(value: 'Female', child: Text('Female')),
        DropdownMenuItem(value: 'Unknown', child: Text('Unknown')),
      ],
      onChanged: _saving
          ? null
          : (selected) {
              if (selected != null) onChanged(selected);
            },
    );
  }

  Widget _ageFields(TextEditingController years, TextEditingController months) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: years,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Age Years',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: months,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Age Months',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Bird Purchase')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Card(
            color: AviaryColors.expense,
            child: const ListTile(
              leading: AviaryIcon(AviaryIconType.bird),
              title: Text(
                'Bulk Add Purchased Birds',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'Species, cage, source and purchase date are shared for this batch. Each bird remains a separate record.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text('Number of birds', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: _count > 1
                    ? () => setState(() {
                          _count--;
                          _ensureEntries();
                        })
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_count', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              IconButton(
                onPressed: _count < 50
                    ? () => setState(() {
                          _count++;
                          _ensureEntries();
                        })
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _speciesId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Species — shared',
              border: OutlineInputBorder(),
            ),
            items: _species
                .map((row) => DropdownMenuItem<String>(
                      value: row['id'].toString(),
                      child: Text(row['name']?.toString() ?? 'Species'),
                    ))
                .toList(),
            onChanged: _saving
                ? null
                : (value) async {
                    setState(() {
                      _speciesId = value;
                      for (final entry in _entries) {
                        entry.ring.clear();
                      }
                    });
                    await _loadManagedOptions();
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _cageId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Cage — shared',
              border: OutlineInputBorder(),
            ),
            items: _cages
                .map((row) => DropdownMenuItem<String>(
                      value: row['id'].toString(),
                      child: Text(row['identifier']?.toString() ?? 'Cage'),
                    ))
                .toList(),
            onChanged: _saving ? null : (value) => setState(() => _cageId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sellerController,
            decoration: const InputDecoration(
              labelText: 'Seller — shared',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _saving ? null : _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Purchase Date — shared',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.unfold_more),
              ),
              child: Text(_dateFormat.format(_date)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes — shared',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Shared or Individual Fields', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          _sharedToggle(label: 'Mutation', value: _sameMutation, onChanged: (v) => setState(() => _sameMutation = v)),
          if (_sameMutation)
            _managedTextField(
              controller: _sharedMutation,
              label: 'Mutation',
              values: _managedMutations,
            ),
          _sharedToggle(label: 'Name', value: _sameName, onChanged: (v) => setState(() => _sameName = v)),
          if (_sameName)
            _managedTextField(
              controller: _sharedName,
              label: 'Name',
              values: _managedNames,
            ),
          _sharedToggle(label: 'Gender', value: _sameGender, onChanged: (v) => setState(() => _sameGender = v)),
          if (_sameGender)
            _genderField(value: _sharedGender, onChanged: (v) => setState(() => _sharedGender = v)),
          _sharedToggle(label: 'Estimated age', value: _sameAge, onChanged: (v) => setState(() => _sameAge = v)),
          if (_sameAge) _ageFields(_sharedAgeYears, _sharedAgeMonths),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _sameAmount,
            title: const Text('Use one total amount for this purchase'),
            onChanged: _saving
                ? null
                : (value) => setState(() => _sameAmount = value ?? false),
          ),
          if (_sameAmount)
            TextField(
              controller: _sharedAmount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Total purchase amount', border: OutlineInputBorder()),
            ),
          const SizedBox(height: 18),
          ...List.generate(_entries.length, (index) {
            final entry = _entries[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bird ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 10),
                    _ringField(index, entry),
                    if (!_sameName) ...[
                      const SizedBox(height: 10),
                      _managedTextField(
                        controller: entry.name,
                        label: 'Name',
                        values: _managedNames,
                      ),
                    ],
                    if (!_sameMutation) ...[
                      const SizedBox(height: 10),
                      _managedTextField(
                        controller: entry.mutation,
                        label: 'Mutation',
                        values: _managedMutations,
                      ),
                    ],
                    if (!_sameGender) ...[
                      const SizedBox(height: 10),
                      _genderField(value: entry.gender, onChanged: (v) => setState(() => entry.gender = v)),
                    ],
                    if (!_sameAge) ...[
                      const SizedBox(height: 10),
                      _ageFields(entry.ageYears, entry.ageMonths),
                    ],
                    if (!_sameAmount) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: entry.amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Purchase Amount *', border: OutlineInputBorder()),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'SAVING...' : 'SAVE PURCHASE'),
          ),
        ],
      ),
    );
  }
}

class _PurchaseBirdEntry {
  final ring = TextEditingController();
  final name = TextEditingController();
  final mutation = TextEditingController();
  final ageYears = TextEditingController(text: '0');
  final ageMonths = TextEditingController(text: '0');
  final amount = TextEditingController();
  String gender = 'Unknown';

  void dispose() {
    ring.dispose();
    name.dispose();
    mutation.dispose();
    ageYears.dispose();
    ageMonths.dispose();
    amount.dispose();
  }
}
