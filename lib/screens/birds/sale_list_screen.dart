import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../../widgets/aviary_date_picker.dart';
import '../finance/add_transaction_screen.dart';
import '../finance/bird_sale_selection_screen.dart';
import '../sales/bird_value_calculator_screen.dart';
import 'bird_details_screen.dart';

class SaleListScreen extends StatefulWidget {
  const SaleListScreen({super.key});

  @override
  State<SaleListScreen> createState() => _SaleListScreenState();
}

class _SaleListScreenState extends State<SaleListScreen> {
  final _date = DateFormat('dd-MMM-yy');
  final _money = NumberFormat('#,##0.##');
  List<Map<String, dynamic>> _birds = const [];
  List<Map<String, dynamic>> _outings = const [];
  Map<String, int> _summary = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await Future.wait<dynamic>([
      DatabaseHelper.instance.getSaleListBirds(),
      DatabaseHelper.instance.getSaleOutings(),
      DatabaseHelper.instance.getSaleWorkspaceSummary(),
    ]);
    if (!mounted) return;
    setState(() {
      _birds = result[0] as List<Map<String, dynamic>>;
      _outings = result[1] as List<Map<String, dynamic>>;
      _summary = result[2] as Map<String, int>;
      _loading = false;
    });
  }

  String _label(Map<String, dynamic> bird) {
    final ring = bird['ringNumber']?.toString().trim() ?? '';
    final name = bird['name']?.toString().trim() ?? '';
    if (ring.isEmpty) return name.isEmpty ? 'No ring' : name;
    return name.isEmpty ? ring : '$ring — $name';
  }

  Future<void> _remove(Map<String, dynamic> bird) async {
    await DatabaseHelper.instance.updateBirdSaleStatus(
      birdId: bird['id'].toString(),
      status: 'Not for Sale',
    );
    if (mounted) await _load();
  }

  Future<void> _addBirds() async {
    final all = await DatabaseHelper.instance.getBirds();
    if (!mounted) return;
    final candidates = all.where((bird) {
      return bird['active'] != 0 &&
          bird['pairId'] == null &&
          (bird['saleStatus']?.toString() ?? 'Not for Sale') == 'Not for Sale';
    }).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No birds available to add to the sale list.')),
      );
      return;
    }

    final selected = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => BirdSaleSelectionScreen(
          eligibleBirdIds: candidates.map((bird) => bird['id'].toString()).toSet(),
        ),
      ),
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    for (final bird in selected) {
      await DatabaseHelper.instance.updateBirdSaleStatus(
        birdId: bird['id'].toString(),
        status: 'Available',
      );
    }
    if (mounted) await _load();
  }

  Future<void> _takeForSale() async {
    if (_birds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No birds are currently For Sale.')),
      );
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _CreateSaleOutingScreen(birds: _birds)),
    );
    if (mounted && changed == true) await _load();
  }

  Future<void> _valueCalculator() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BirdValueCalculatorScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _sellFromOuting(Map<String, dynamic> outing) async {
    final birds = await DatabaseHelper.instance.getSaleOutingBirds(
      outing['id'].toString(),
      status: 'Taken',
    );
    if (!mounted) return;
    if (birds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No birds are still out on this sale trip.')),
      );
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          initialType: 'Income',
          initialSaleBirds: birds,
          saleOutingId: outing['id'].toString(),
        ),
      ),
    );
    if (mounted && changed == true) await _load();
  }

  Future<void> _returnRemaining(Map<String, dynamic> outing) async {
    final count = (outing['stillOutCount'] as num?)?.toInt() ?? 0;
    if (count <= 0) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Return unsold birds?'),
        content: Text(
          '$count bird${count == 1 ? '' : 's'} will return to the For Sale list. '
          'Their cage assignments stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Return All'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await DatabaseHelper.instance.returnSaleOutingBirds(outing['id'].toString());
    if (mounted) await _load();
  }

  Future<void> _openBird(Map<String, dynamic> bird) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: bird)),
    );
    if (mounted) await _load();
  }

  Widget _summaryTile(String label, String key, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              '${_summary[key] ?? 0}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outingCard(Map<String, dynamic> outing) {
    final rawDate = DateTime.tryParse(outing['outingDate']?.toString() ?? '');
    final taken = (outing['takenCount'] as num?)?.toInt() ?? 0;
    final sold = (outing['soldCount'] as num?)?.toInt() ?? 0;
    final returned = (outing['returnedCount'] as num?)?.toInt() ?? 0;
    final stillOut = (outing['stillOutCount'] as num?)?.toInt() ?? 0;
    final soldAmount = (outing['soldAmount'] as num?)?.toDouble() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    outing['locationName']?.toString() ?? 'Sale location',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(rawDate == null ? '—' : _date.format(rawDate)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(label: Text('Taken $taken'), visualDensity: VisualDensity.compact),
                Chip(label: Text('Sold $sold'), visualDensity: VisualDensity.compact),
                if (returned > 0)
                  Chip(label: Text('Returned $returned'), visualDensity: VisualDensity.compact),
                if (stillOut > 0)
                  Chip(label: Text('Still out $stillOut'), visualDensity: VisualDensity.compact),
                if (soldAmount > 0)
                  Chip(
                    label: Text('Rs ${_money.format(soldAmount)}'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (stillOut > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _sellFromOuting(outing),
                      icon: const Icon(Icons.sell_outlined),
                      label: const Text('Sell'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _returnRemaining(outing),
                      icon: const Icon(Icons.keyboard_return),
                      label: const Text('Return'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final open = _outings
        .where((outing) => ((outing['stillOutCount'] as num?)?.toInt() ?? 0) > 0)
        .toList();
    final history = _outings
        .where((outing) => ((outing['stillOutCount'] as num?)?.toInt() ?? 0) == 0)
        .take(10)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Sale Workspace')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          children: [
            Row(
              children: [
                _summaryTile('For Sale', 'forSale', Icons.sell_outlined, AviaryColors.finance),
                const SizedBox(width: 6),
                _summaryTile('Taken', 'taken', Icons.outbox_outlined, Colors.orange),
                const SizedBox(width: 6),
                _summaryTile('Sold', 'sold', Icons.check_circle_outline, AviaryColors.income),
                const SizedBox(width: 6),
                _summaryTile('Returned', 'returned', Icons.keyboard_return, Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _takeForSale,
                    icon: const Icon(Icons.outbox_outlined),
                    label: const Text('Take for Sale'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _valueCalculator,
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Value Calculator'),
                  ),
                ),
              ],
            ),
            if (open.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Currently Out', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              ...open.map(_outingCard),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Text('For Sale (${_birds.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton.icon(onPressed: _addBirds, icon: const Icon(Icons.add), label: const Text('Add Birds')),
              ],
            ),
            if (_birds.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No birds currently marked For Sale.', textAlign: TextAlign.center)))
            else
              ..._birds.map((bird) {
                final mutation = bird['mutation']?.toString().trim() ?? '';
                final age = bird['ageGroup']?.toString().trim() ?? '';
                final cage = bird['cageIdentifier']?.toString().trim() ?? '';
                return Card(
                  child: ListTile(
                    onTap: () => _openBird(bird),
                    leading: const AviaryIcon(AviaryIconType.bird),
                    title: Text(
                      _label(bird),
                      style: TextStyle(fontWeight: FontWeight.w800, color: birdGenderTextColor(bird['gender']?.toString())),
                    ),
                    subtitle: Text([
                      bird['speciesName']?.toString() ?? 'Unknown species',
                      if (mutation.isNotEmpty) mutation,
                      if (age.isNotEmpty) age,
                      if (cage.isNotEmpty) aviaryCageLabel(cage),
                    ].join(' · ')),
                    trailing: IconButton(
                      tooltip: 'Remove from For Sale',
                      onPressed: () => _remove(bird),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ),
                );
              }),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Recent Sale Outings', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              ...history.map(_outingCard),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateSaleOutingScreen extends StatefulWidget {
  const _CreateSaleOutingScreen({required this.birds});

  final List<Map<String, dynamic>> birds;

  @override
  State<_CreateSaleOutingScreen> createState() => _CreateSaleOutingScreenState();
}

class _CreateSaleOutingScreenState extends State<_CreateSaleOutingScreen> {
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final _date = DateFormat('dd-MMM-yy');
  List<Map<String, dynamic>> _locations = const [];
  Set<String> _selected = <String>{};
  DateTime _outingDate = DateTime.now();
  String? _locationId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.birds.map((bird) => bird['id'].toString()).toSet();
    _loadLocations();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    final rows = await DatabaseHelper.instance.getSaleLocations();
    if (!mounted) return;
    setState(() => _locations = rows);
  }

  String _birdLabel(Map<String, dynamic> bird) {
    final ring = bird['ringNumber']?.toString().trim() ?? '';
    final name = bird['name']?.toString().trim() ?? '';
    return name.isEmpty ? (ring.isEmpty ? 'Bird' : ring) : (ring.isEmpty ? name : '$ring — $name');
  }

  Future<void> _pickDate() async {
    final value = await showAviaryDatePicker(
      context: context,
      initialDate: _outingDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (mounted && value != null) setState(() => _outingDate = value);
  }

  Future<void> _chooseBirds() async {
    final birds = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(
        builder: (_) => BirdSaleSelectionScreen(
          initialSelectedIds: _selected,
          eligibleBirdIds: widget.birds.map((bird) => bird['id'].toString()).toSet(),
        ),
      ),
    );
    if (!mounted || birds == null) return;
    setState(() => _selected = birds.map((bird) => bird['id'].toString()).toSet());
  }

  Future<void> _manageLocations() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheet) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: [
              const ListTile(title: Text('Saved Sale Locations', style: TextStyle(fontWeight: FontWeight.w800))),
              if (_locations.isEmpty) const ListTile(title: Text('No saved locations yet.')),
              ..._locations.map((location) => ListTile(
                    title: Text(location['name']?.toString() ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await DatabaseHelper.instance.removeSaleLocation(location['id'].toString());
                        final rows = await DatabaseHelper.instance.getSaleLocations();
                        if (!mounted) return;
                        setState(() {
                          _locations = rows;
                          if (_locationId == location['id'].toString()) _locationId = null;
                        });
                        setSheet(() {});
                      },
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one bird.')));
      return;
    }
    final selectedLocation = _locations.where((row) => row['id'].toString() == _locationId).toList();
    final location = _locationController.text.trim().isNotEmpty
        ? _locationController.text.trim()
        : selectedLocation.isEmpty
            ? ''
            : selectedLocation.first['name'].toString();
    if (location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter or choose a sale location.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await DatabaseHelper.instance.createSaleOuting(
        birdIds: _selected.toList(),
        outingDate: _outingDate,
        locationName: location,
        notes: _notesController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take Birds for Sale')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(_date.format(_outingDate)),
            trailing: const Icon(Icons.unfold_more),
            onTap: _pickDate,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _locationId,
            decoration: const InputDecoration(labelText: 'Remembered location', border: OutlineInputBorder()),
            items: _locations
                .map((row) => DropdownMenuItem(value: row['id'].toString(), child: Text(row['name'].toString())))
                .toList(),
            onChanged: (value) => setState(() {
              _locationId = value;
              if (value != null) _locationController.clear();
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _locationController,
            onChanged: (value) {
              if (value.trim().isNotEmpty && _locationId != null) setState(() => _locationId = null);
            },
            decoration: const InputDecoration(labelText: 'Or new location', border: OutlineInputBorder()),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: _manageLocations, icon: const Icon(Icons.manage_search), label: const Text('Manage Locations')),
          ),
          const SizedBox(height: 4),
          Card(
            child: ListTile(
              leading: const AviaryIcon(AviaryIconType.bird),
              title: Text('${_selected.length} birds selected', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Birds stay assigned to their cages until actually sold.'),
              trailing: TextButton(onPressed: _chooseBirds, child: const Text('Change')),
            ),
          ),
          if (_selected.isNotEmpty)
            ...widget.birds.where((bird) => _selected.contains(bird['id'].toString())).take(8).map((bird) => ListTile(
                  dense: true,
                  title: Text(_birdLabel(bird), style: TextStyle(fontWeight: FontWeight.w700, color: birdGenderTextColor(bird['gender']?.toString()))),
                  subtitle: Text('${bird['speciesName'] ?? ''}${(bird['mutation']?.toString().trim() ?? '').isEmpty ? '' : ' · ${bird['mutation']}'}'),
                )),
          if (_selected.length > 8) Padding(padding: const EdgeInsets.only(left: 16), child: Text('+ ${_selected.length - 8} more')),
          const SizedBox(height: 10),
          TextField(controller: _notesController, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.outbox_outlined),
            label: Text(_saving ? 'SAVING...' : 'MARK AS TAKEN FOR SALE'),
          ),
        ],
      ),
    );
  }
}
