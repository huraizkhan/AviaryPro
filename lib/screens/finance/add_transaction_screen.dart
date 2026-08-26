import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../cages/add_cage_screen.dart';
import '../breeding/add_egg_screen.dart';
import 'bird_sale_selection_screen.dart';
import 'bulk_bird_purchase_screen.dart';
import '../../widgets/aviary_date_picker.dart';

class AddTransactionScreen extends StatefulWidget {
  final String initialType;
  final List<Map<String, dynamic>> initialSaleBirds;
  final String? saleOutingId;

  const AddTransactionScreen({
    super.key,
    required this.initialType,
    this.initialSaleBirds = const [],
    this.saleOutingId,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  final quantityController = TextEditingController();
  final notesController = TextEditingController();
  final buyerController = TextEditingController();
  final samePriceController = TextEditingController();
  final saleOverrideController = TextEditingController();
  final dateFormat = DateFormat('dd-MMM-yy');

  late String type;
  late String category;
  DateTime date = DateTime.now();
  bool saving = false;

  List<Map<String, dynamic>> selectedSaleBirds = const [];
  List<Map<String, dynamic>> availableEggs = const [];
  Map<String, dynamic>? selectedEgg;
  String salePricingMode = 'factors';
  final Set<String> saleFactors = <String>{};
  final Set<String> overriddenBirdIds = <String>{};
  final Map<String, TextEditingController> individualPriceControllers = {};
  final Map<String, TextEditingController> groupPriceControllers = {};

  static const incomeCategories = <String>[
    'Bird Sale',
    'Egg Sale',
    'Other Income',
  ];

  static const expenseCategories = <String>[
    'Feed',
    'Medicine',
    'Cage',
    'Bird Purchase',
    'Egg Purchase',
    'Utilities',
    'Other Expense',
  ];

  @override
  void initState() {
    super.initState();
    type = widget.initialType == 'Expense' ? 'Expense' : 'Income';
    category = type == 'Income' ? incomeCategories.first : expenseCategories.first;
    if (widget.initialSaleBirds.isNotEmpty) {
      type = 'Income';
      category = 'Bird Sale';
      selectedSaleBirds = List<Map<String, dynamic>>.from(widget.initialSaleBirds);
      _prepareSaleControllers(selectedSaleBirds);
    }
    _loadAvailableEggs();
  }

  @override
  void dispose() {
    amountController.dispose();
    quantityController.dispose();
    notesController.dispose();
    buyerController.dispose();
    samePriceController.dispose();
    saleOverrideController.dispose();
    for (final controller in individualPriceControllers.values) {
      controller.dispose();
    }
    for (final controller in groupPriceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> get categories =>
      type == 'Income' ? incomeCategories : expenseCategories;

  bool get isBirdSale => type == 'Income' && category == 'Bird Sale';
  bool get isEggSale => type == 'Income' && category == 'Egg Sale';
  bool get isBirdPurchase => type == 'Expense' && category == 'Bird Purchase';
  bool get isEggPurchase => type == 'Expense' && category == 'Egg Purchase';
  bool get isCagePurchase => type == 'Expense' && category == 'Cage';
  bool get isFeedExpense => type == 'Expense' && category == 'Feed';

  Future<void> _loadAvailableEggs() async {
    final rows = await DatabaseHelper.instance.getAvailableEggsForSale();
    if (!mounted) return;
    setState(() {
      availableEggs = rows;
      if (selectedEgg != null &&
          !rows.any((row) => row['id']?.toString() == selectedEgg?['id']?.toString())) {
        selectedEgg = null;
      }
    });
  }

  Future<void> _selectEgg() async {
    await _loadAvailableEggs();
    if (!mounted) return;
    if (availableEggs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No eggs available.')),
      );
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .70,
          child: Column(
            children: [
              const ListTile(
                title: Text('Select Egg', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('Only eggs currently incubating are shown.'),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: availableEggs.length,
                  itemBuilder: (context, index) {
                    final egg = availableEggs[index];
                    final cage = egg['cageIdentifier']?.toString() ?? 'No cage';
                    final pair = egg['pairIdentifier']?.toString() ?? 'Pair';
                    final due = DateTime.tryParse(egg['expectedHatchDate']?.toString() ?? '');
                    return ListTile(
                      leading: const AviaryIcon(AviaryIconType.egg),
                      title: Text('$cage — $pair · Egg ${egg['eggNumber'] ?? '?'}'),
                      subtitle: Text(
                        due == null ? 'Hatch date not set' : 'Hatch: ${dateFormat.format(due)}',
                      ),
                      onTap: () => Navigator.pop(sheetContext, egg),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => selectedEgg = result);
  }

  Future<void> _pickDate() async {
    final picked = await showAviaryDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => date = picked);
  }

  void _prepareSaleControllers(List<Map<String, dynamic>> birds) {
    for (final bird in birds) {
      individualPriceControllers.putIfAbsent(
        bird['id'].toString(),
        () => TextEditingController(),
      );
    }
    for (final key in _saleGroups.keys) {
      groupPriceControllers.putIfAbsent(key, () => TextEditingController());
    }
  }

  Future<void> _selectSaleBirds() async {
    final eligible = widget.saleOutingId == null
        ? null
        : widget.initialSaleBirds.map((bird) => bird['id'].toString()).toSet();
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => BirdSaleSelectionScreen(
          initialSelectedIds: selectedSaleBirds
              .map((bird) => bird['id'].toString())
              .toSet(),
          eligibleBirdIds: eligible,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      selectedSaleBirds = result;
      overriddenBirdIds.removeWhere(
        (id) => !result.any((bird) => bird['id'].toString() == id),
      );
      _prepareSaleControllers(result);
    });
  }

  String _factorValue(Map<String, dynamic> bird, String factor) {
    return switch (factor) {
      'Species' => bird['speciesName']?.toString().trim().isNotEmpty == true
          ? bird['speciesName'].toString().trim()
          : 'Unknown species',
      'Mutation' => bird['mutation']?.toString().trim().isNotEmpty == true
          ? bird['mutation'].toString().trim()
          : 'No mutation',
      'Age Group' => bird['ageGroup']?.toString().trim().isNotEmpty == true
          ? bird['ageGroup'].toString().trim()
          : 'Unknown age',
      _ => '',
    };
  }

  List<String> get _availableSaleFactors {
    final values = <String>[];
    for (final factor in const ['Species', 'Mutation', 'Age Group']) {
      final distinct = selectedSaleBirds.map((bird) => _factorValue(bird, factor)).toSet();
      if (distinct.length > 1) values.add(factor);
    }
    return values;
  }

  String _saleGroupKey(Map<String, dynamic> bird) {
    if (saleFactors.isEmpty) return 'All selected birds';
    final ordered = const ['Species', 'Mutation', 'Age Group']
        .where(saleFactors.contains)
        .toList();
    return ordered.map((factor) => '$factor=${_factorValue(bird, factor)}').join('|');
  }

  String _saleGroupLabel(String key) {
    if (key == 'All selected birds') return key;
    return key
        .split('|')
        .map((part) => part.contains('=') ? part.split('=').skip(1).join('=') : part)
        .join(' · ');
  }

  Map<String, List<Map<String, dynamic>>> get _saleGroups {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final bird in selectedSaleBirds) {
      groups.putIfAbsent(_saleGroupKey(bird), () => []).add(bird);
    }
    return groups;
  }

  double _groupUnitPrice(String key) =>
      double.tryParse(groupPriceControllers[key]?.text.trim() ?? '') ?? 0;

  double? _priceForBird(Map<String, dynamic> bird) {
    final id = bird['id'].toString();
    if (salePricingMode == 'same') {
      final total = double.tryParse(samePriceController.text.trim());
      if (total == null || selectedSaleBirds.isEmpty) return total;
      return total / selectedSaleBirds.length;
    }
    if (salePricingMode == 'individual') {
      return double.tryParse(individualPriceControllers[id]?.text.trim() ?? '');
    }
    if (overriddenBirdIds.contains(id)) {
      return double.tryParse(individualPriceControllers[id]?.text.trim() ?? '');
    }
    return _groupUnitPrice(_saleGroupKey(bird));
  }

  double get _saleAllocatedTotal {
    var total = 0.0;
    for (final bird in selectedSaleBirds) {
      total += _priceForBird(bird) ?? 0;
    }
    return total;
  }

  double get _saleTargetTotal =>
      double.tryParse(samePriceController.text.trim()) ?? 0;

  double get _saleBalance => _saleTargetTotal - _saleAllocatedTotal;

  double get _saleTotal => salePricingMode == 'factors'
      ? _saleAllocatedTotal
      : salePricingMode == 'same'
          ? _saleTargetTotal
          : _saleAllocatedTotal;

  Future<void> _showSaleGroup(
    String key,
    List<Map<String, dynamic>> birds,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    '${_saleGroupLabel(key)} · ${birds.length} bird${birds.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Optional individual price overrides'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: birds.length,
                    itemBuilder: (context, index) {
                      final bird = birds[index];
                      final id = bird['id'].toString();
                      final ring = bird['ringNumber']?.toString() ?? 'Bird';
                      final name = bird['name']?.toString().trim() ?? '';
                      final override = overriddenBirdIds.contains(id);
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 5, 10, 10),
                          child: Column(
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: override,
                                title: Text(
                                  name.isEmpty ? ring : '$ring — $name',
                                  style: TextStyle(
                                    color: birdGenderTextColor(bird['gender']?.toString()),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${bird['speciesName'] ?? ''} · ${_factorValue(bird, 'Mutation')} · ${_factorValue(bird, 'Age Group')}',
                                ),
                                secondary: override
                                    ? const Chip(label: Text('Override'))
                                    : null,
                                onChanged: (value) {
                                  setState(() {
                                    if (value) {
                                      overriddenBirdIds.add(id);
                                    } else {
                                      overriddenBirdIds.remove(id);
                                    }
                                  });
                                  setSheetState(() {});
                                },
                              ),
                              if (override)
                                TextField(
                                  controller: individualPriceControllers.putIfAbsent(
                                    id,
                                    () => TextEditingController(),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) {
                                    setState(() {});
                                    setSheetState(() {});
                                  },
                                  decoration: const InputDecoration(
                                    labelText: 'Individual price',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int get _protectedSaleCount => selectedSaleBirds
      .where(
        (bird) =>
            (bird['saleStatus']?.toString() ?? 'Not for Sale') ==
            'Not for Sale',
      )
      .length;

  Future<bool> _confirmInternalSaleWarnings() async {
    final protectedCount = _protectedSaleCount;
    if (protectedCount == 0) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm bird sale'),
        content: Text(
          '$protectedCount selected bird${protectedCount == 1 ? '' : 's'} '
          'have an internal sale warning. Continue with this sale?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue Sale'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<Set<String>?> _askRemovedSaleRings() async {
    final withRings = selectedSaleBirds
        .where((bird) => (bird['ringNumber']?.toString().trim() ?? '').isNotEmpty)
        .toList();
    if (withRings.isEmpty) return <String>{};
    final removed = <String>{};
    return showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Were any rings removed?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Check only birds whose physical ring was removed. Unchecked rings stay assigned to the sold bird.',
                ),
                const SizedBox(height: 8),
                ...withRings.map((bird) {
                  final id = bird['id'].toString();
                  final ring = bird['ringNumber']?.toString() ?? '';
                  final name = bird['name']?.toString().trim() ?? '';
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: removed.contains(id),
                    title: Text(name.isEmpty ? ring : '$ring — $name'),
                    subtitle: const Text('Ring removed'),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        removed.add(id);
                      } else {
                        removed.remove(id);
                      }
                    }),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, Set<String>.from(removed)),
              child: const Text('Continue Sale'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveBirdSale() async {
    if (saving) return;
    if (selectedSaleBirds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one bird to sell.')),
      );
      return;
    }
    if (salePricingMode == 'factors') {
      if (_saleTargetTotal <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the total sale amount.')),
        );
        return;
      }
      if (_saleBalance.abs() > 0.009) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Balance remaining must be 0 before saving. Current: ${_saleBalance.toStringAsFixed(2)}',
            ),
          ),
        );
        return;
      }
    }
    for (final bird in selectedSaleBirds) {
      final price = _priceForBird(bird);
      if (price == null || price <= 0) {
        final ring = bird['ringNumber']?.toString() ?? 'bird';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter a valid sale price for $ring.')),
        );
        return;
      }
    }
    if (_protectedSaleCount > 0 &&
        saleOverrideController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a reason to override the sale warning.'),
        ),
      );
      return;
    }
    if (!await _confirmInternalSaleWarnings() || !mounted) return;
    final releaseRingBirdIds = await _askRemovedSaleRings();
    if (!mounted || releaseRingBirdIds == null) return;

    setState(() => saving = true);
    try {
      final soldItems = selectedSaleBirds
          .map((bird) => {
                'birdId': bird['id'].toString(),
                'price': _priceForBird(bird)!,
              })
          .toList();
      await DatabaseHelper.instance.sellBirdBatch(
        items: soldItems,
        soldAt: date,
        buyer: buyerController.text.trim(),
        notes: [
          if (_protectedSaleCount > 0)
            'Sale override reason: ${saleOverrideController.text.trim()}',
          if (notesController.text.trim().isNotEmpty)
            notesController.text.trim(),
        ].join('\n'),
        releaseRingBirdIds: releaseRingBirdIds,
      );
      if (widget.saleOutingId != null) {
        await DatabaseHelper.instance.recordOutingSoldBirds(
          outingId: widget.saleOutingId!,
          items: soldItems,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete sale: $error')),
      );
    }
  }

  Future<void> _saveEggSale() async {
    if (saving) return;
    if (selectedEgg == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an egg to sell.')),
      );
      return;
    }
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid sale amount.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await DatabaseHelper.instance.sellEgg(
        eggId: selectedEgg!['id'].toString(),
        price: amount,
        soldAt: date,
        notes: notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not sell egg: $error')),
      );
    }
  }

  Future<void> _saveEggPurchase() async {
    if (!formKey.currentState!.validate() || saving) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddEggScreen()),
    );
    if (!mounted || changed != true) return;
    setState(() => saving = true);
    try {
      await DatabaseHelper.instance.addFinanceTransaction({
        'id': const Uuid().v4(),
        'type': 'Expense',
        'category': 'Egg Purchase',
        'amount': double.parse(amountController.text.trim()),
        'date': date.toIso8601String(),
        'notes': [
          'Purchased egg added to breeding records',
          if (notesController.text.trim().isNotEmpty) notesController.text.trim(),
        ].join(' · '),
        'birdId': null,
        'createdAt': DateTime.now().toIso8601String(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Egg was added, but purchase record failed: $error')),
      );
    }
  }

  Future<void> _saveCagePurchase() async {
    if (!formKey.currentState!.validate() || saving) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddCageScreen()),
    );
    if (!mounted || changed != true) return;
    setState(() => saving = true);
    try {
      await DatabaseHelper.instance.addFinanceTransaction({
        'id': const Uuid().v4(),
        'type': 'Expense',
        'category': 'Cage',
        'amount': double.parse(amountController.text.trim()),
        'date': date.toIso8601String(),
        'notes': notesController.text.trim(),
        'birdId': null,
        'createdAt': DateTime.now().toIso8601String(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cage was added, but purchase record failed: $error')),
      );
    }
  }

  Future<void> _saveRegular() async {
    if (!formKey.currentState!.validate() || saving) return;
    setState(() => saving = true);

    try {
      final quantity = isFeedExpense
          ? double.tryParse(quantityController.text.trim())
          : null;
      if (isFeedExpense && (quantity == null || quantity <= 0)) {
        throw StateError('Enter the feed quantity in kg.');
      }
      await DatabaseHelper.instance.addFinanceTransaction({
        'id': const Uuid().v4(),
        'type': type,
        'category': category,
        'amount': double.parse(amountController.text.trim()),
        'quantity': quantity,
        'unit': isFeedExpense ? 'kg' : null,
        'date': date.toIso8601String(),
        'notes': notesController.text.trim(),
        'birdId': null,
        'createdAt': DateTime.now().toIso8601String(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save transaction: $error')),
      );
    }
  }

  Future<void> _openPurchase() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BulkBirdPurchaseScreen()),
    );
    if (!mounted || changed != true) return;
    Navigator.pop(context, true);
  }

  Widget _dateField() {
    return InkWell(
      onTap: saving ? null : _pickDate,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.unfold_more),
        ),
        child: Text(dateFormat.format(date)),
      ),
    );
  }

  Widget _salePricing() {
    if (selectedSaleBirds.isEmpty) return const SizedBox.shrink();
    final availableFactors = _availableSaleFactors;
    final groups = _saleGroups.entries.toList()
      ..sort((a, b) => _saleGroupLabel(a.key).compareTo(_saleGroupLabel(b.key)));
    for (final entry in groups) {
      groupPriceControllers.putIfAbsent(entry.key, () => TextEditingController());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'factors', label: Text('By Factors')),
            ButtonSegment(value: 'same', label: Text('One Total')),
            ButtonSegment(value: 'individual', label: Text('Separate')),
          ],
          selected: {salePricingMode},
          onSelectionChanged: saving
              ? null
              : (selection) => setState(() => salePricingMode = selection.first),
        ),
        const SizedBox(height: 12),
        if (salePricingMode == 'same') ...[
          TextField(
            controller: samePriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Total sale amount',
              helperText: 'The total is divided equally between selected birds.',
              border: OutlineInputBorder(),
            ),
          ),
        ] else if (salePricingMode == 'factors') ...[
          TextField(
            controller: samePriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Total sale amount',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          if (availableFactors.isNotEmpty) ...[
            const Text('Balance using factors', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: availableFactors.map((factor) {
                return FilterChip(
                  label: Text(factor),
                  selected: saleFactors.contains(factor),
                  onSelected: saving
                      ? null
                      : (selected) => setState(() {
                            if (selected) {
                              saleFactors.add(factor);
                            } else {
                              saleFactors.remove(factor);
                            }
                            _prepareSaleControllers(selectedSaleBirds);
                          }),
                );
              }).toList(),
            ),
          ] else
            const Text('All selected birds have the same available pricing factors.'),
          const SizedBox(height: 10),
          Card(
            color: _saleBalance.abs() <= .009
                ? AviaryColors.income.withValues(alpha: .15)
                : Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              title: const Text('Balance Remaining', style: TextStyle(fontWeight: FontWeight.w800)),
              trailing: Text(
                _saleBalance.toStringAsFixed(2),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          ...groups.map((entry) {
            final count = entry.value.length;
            final controller = groupPriceControllers[entry.key]!;
            final baseSubtotal = _groupUnitPrice(entry.key) *
                entry.value.where((bird) => !overriddenBirdIds.contains(bird['id'].toString())).length;
            final overrideSubtotal = entry.value
                .where((bird) => overriddenBirdIds.contains(bird['id'].toString()))
                .fold<double>(0, (sum, bird) => sum + (_priceForBird(bird) ?? 0));
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _showSaleGroup(entry.key, entry.value),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_saleGroupLabel(entry.key)} · $count bird${count == 1 ? '' : 's'}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (entry.value.any((bird) => overriddenBirdIds.contains(bird['id'].toString())))
                            const Chip(label: Text('Override'), visualDensity: VisualDensity.compact),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Price per bird',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Group subtotal: ${(baseSubtotal + overrideSubtotal).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ] else ...selectedSaleBirds.map((bird) {
          final id = bird['id'].toString();
          final ring = bird['ringNumber']?.toString() ?? 'Bird';
          final name = bird['name']?.toString().trim() ?? '';
          final controller = individualPriceControllers.putIfAbsent(
            id,
            () => TextEditingController(),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                label: Text(
                  '${name.isEmpty ? ring : '$ring — $name'} price',
                  style: TextStyle(
                    color: birdGenderTextColor(bird['gender']?.toString()),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          );
        }),
        Card(
          color: AviaryColors.income.withValues(alpha: .14),
          child: ListTile(
            title: Text('${selectedSaleBirds.length} birds selected'),
            trailing: Text(
              'Total: ${_saleTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _birdSaleForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: saving ? null : _selectSaleBirds,
          icon: const AviaryIcon(AviaryIconType.bird),
          label: Text(
            selectedSaleBirds.isEmpty
                ? 'Select Birds for Sale'
                : 'Change Selection (${selectedSaleBirds.length})',
          ),
        ),
        if (selectedSaleBirds.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'A Bird Sale cannot be saved until at least one bird is selected.',
              textAlign: TextAlign.center,
            ),
          ),
        _salePricing(),
        if (_protectedSaleCount > 0) ...[
          const SizedBox(height: 12),
          TextField(
            controller: saleOverrideController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Sale override reason *',
              helperText: 'Required because one or more selected birds have a sale warning.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: buyerController,
          decoration: const InputDecoration(
            labelText: 'Buyer',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _dateField(),
        const SizedBox(height: 12),
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
          onPressed: saving ? null : _saveBirdSale,
          icon: const Icon(Icons.sell_outlined),
          label: Text(saving ? 'SELLING...' : 'COMPLETE BIRD SALE'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add $type')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Income', label: Text('Income')),
                ButtonSegment(value: 'Expense', label: Text('Expense')),
              ],
              selected: {type},
              onSelectionChanged: saving
                  ? null
                  : (selection) {
                      final selectedType = selection.first;
                      setState(() {
                        type = selectedType;
                        category = selectedType == 'Income'
                            ? incomeCategories.first
                            : expenseCategories.first;
                        selectedEgg = null;
                      });
                      if (isEggSale) _loadAvailableEggs();
                    },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('${type}_$category'),
              initialValue: category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: categories
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          category = value;
                          selectedEgg = null;
                        });
                        if (isEggSale) _loadAvailableEggs();
                      }
                    },
            ),
            const SizedBox(height: 16),
            if (isBirdSale)
              _birdSaleForm()
            else if (isEggSale) ...[
              Card(
                color: AviaryColors.income,
                child: ListTile(
                  leading: const AviaryIcon(AviaryIconType.egg),
                  title: Text(
                    availableEggs.isEmpty
                        ? 'No eggs available'
                        : selectedEgg == null
                            ? '${availableEggs.length} egg${availableEggs.length == 1 ? '' : 's'} available'
                            : '${selectedEgg!['cageIdentifier'] ?? 'No cage'} — ${selectedEgg!['pairIdentifier'] ?? 'Pair'} · Egg ${selectedEgg!['eggNumber'] ?? '?'}',
                  ),
                  subtitle: const Text('Sold eggs are removed from active egg counts.'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: saving || availableEggs.isEmpty ? null : _selectEgg,
                icon: const AviaryIcon(AviaryIconType.egg),
                label: Text(selectedEgg == null ? 'SELECT EGG' : 'CHANGE EGG'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Sale Amount',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              _dateField(),
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
                onPressed: saving || availableEggs.isEmpty ? null : _saveEggSale,
                icon: const Icon(Icons.sell_outlined),
                label: Text(saving ? 'SELLING...' : 'COMPLETE EGG SALE'),
              ),
            ] else if (isBirdPurchase) ...[
              Card(
                color: AviaryColors.expense,
                child: const ListTile(
                  leading: AviaryIcon(AviaryIconType.bird),
                  title: Text('Bird Purchase'),
                  subtitle: Text(
                    'Add one or many purchased birds with shared or individual fields.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: saving ? null : _openPurchase,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('OPEN BIRD PURCHASE'),
              ),
            ] else ...[
              if (isFeedExpense) ...[
                TextFormField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Feed Quantity (kg)',
                    helperText: 'Used for monthly feed purchase/consumption trends.',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (!isFeedExpense) return null;
                    final quantity = double.tryParse(value?.trim() ?? '');
                    return quantity == null || quantity <= 0
                        ? 'Enter feed quantity in kg'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: isFeedExpense ? 'Total Feed Cost' : 'Amount',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (isBirdSale || isBirdPurchase) return null;
                  final amount = double.tryParse(value?.trim() ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _dateField(),
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
                onPressed: saving
                    ? null
                    : isCagePurchase
                        ? _saveCagePurchase
                        : isEggPurchase
                            ? _saveEggPurchase
                            : _saveRegular,
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  saving
                      ? 'SAVING...'
                      : isCagePurchase
                          ? 'ADD CAGE & SAVE PURCHASE'
                          : isEggPurchase
                              ? 'ADD EGG & SAVE PURCHASE'
                              : 'SAVE',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
