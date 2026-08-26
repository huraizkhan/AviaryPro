import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../cages/add_cage_screen.dart';
import '../breeding/add_egg_screen.dart';
import 'bird_sale_selection_screen.dart';
import 'bulk_bird_purchase_screen.dart';

class AddTransactionScreen extends StatefulWidget {
  final String initialType;

  const AddTransactionScreen({
    super.key,
    required this.initialType,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
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
  String salePricingMode = 'individual';
  final Map<String, TextEditingController> individualPriceControllers = {};
  final Map<String, TextEditingController> mutationPriceControllers = {};

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
    _loadAvailableEggs();
  }

  @override
  void dispose() {
    amountController.dispose();
    notesController.dispose();
    buyerController.dispose();
    samePriceController.dispose();
    saleOverrideController.dispose();
    for (final controller in individualPriceControllers.values) {
      controller.dispose();
    }
    for (final controller in mutationPriceControllers.values) {
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
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => date = picked);
  }

  Future<void> _selectSaleBirds() async {
    final result = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => BirdSaleSelectionScreen(
          initialSelectedIds: selectedSaleBirds
              .map((bird) => bird['id'].toString())
              .toSet(),
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      selectedSaleBirds = result;
      for (final bird in result) {
        individualPriceControllers.putIfAbsent(
          bird['id'].toString(),
          () => TextEditingController(),
        );
        mutationPriceControllers.putIfAbsent(
          _mutationKey(bird),
          () => TextEditingController(),
        );
      }
    });
  }

  String _mutationKey(Map<String, dynamic> bird) {
    final mutation = bird['mutation']?.toString().trim() ?? '';
    return mutation.isEmpty ? 'No mutation' : mutation;
  }

  double? _priceForBird(Map<String, dynamic> bird) {
    if (salePricingMode == 'same') {
      final total = double.tryParse(samePriceController.text.trim());
      if (total == null || selectedSaleBirds.isEmpty) return total;
      return total / selectedSaleBirds.length;
    }
    final text = salePricingMode == 'mutation'
        ? mutationPriceControllers[_mutationKey(bird)]?.text.trim() ?? ''
        : individualPriceControllers[bird['id'].toString()]?.text.trim() ?? '';
    return double.tryParse(text);
  }

  double get _saleTotal {
    var total = 0.0;
    for (final bird in selectedSaleBirds) {
      total += _priceForBird(bird) ?? 0;
    }
    return total;
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
      await DatabaseHelper.instance.sellBirdBatch(
        items: selectedSaleBirds
            .map((bird) => {
                  'birdId': bird['id'].toString(),
                  'price': _priceForBird(bird)!,
                })
            .toList(),
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
      await DatabaseHelper.instance.addFinanceTransaction({
        'id': const Uuid().v4(),
        'type': type,
        'category': category,
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
          suffixIcon: Icon(Icons.calendar_month),
        ),
        child: Text(dateFormat.format(date)),
      ),
    );
  }

  Widget _salePricing() {
    if (selectedSaleBirds.isEmpty) return const SizedBox.shrink();
    final mutations = selectedSaleBirds.map(_mutationKey).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'individual', label: Text('Each Bird')),
            ButtonSegment(value: 'same', label: Text('One Total')),
            ButtonSegment(value: 'mutation', label: Text('By Mutation')),
          ],
          selected: {salePricingMode},
          onSelectionChanged: saving
              ? null
              : (selection) => setState(() => salePricingMode = selection.first),
        ),
        const SizedBox(height: 12),
        if (salePricingMode == 'same')
          TextField(
            controller: samePriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Total sale amount',
              border: OutlineInputBorder(),
            ),
          )
        else if (salePricingMode == 'mutation')
          ...mutations.map((mutation) {
            final count = selectedSaleBirds.where((bird) => _mutationKey(bird) == mutation).length;
            final controller = mutationPriceControllers.putIfAbsent(
              mutation,
              () => TextEditingController(),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '$mutation · $count bird${count == 1 ? '' : 's'}',
                  border: const OutlineInputBorder(),
                ),
              ),
            );
          })
        else
          ...selectedSaleBirds.map((bird) {
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
          color: AviaryColors.income,
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
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
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
