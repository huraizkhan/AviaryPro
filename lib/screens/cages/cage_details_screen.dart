import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../birds/add_bird_screen.dart';
import '../birds/bird_details_screen.dart';
import '../breeding/pair_details_screen.dart';
import 'assign_bird_screen.dart';
import 'create_pair_screen.dart';
import 'edit_cage_screen.dart';

class CageDetailsScreen extends StatefulWidget {
  const CageDetailsScreen({
    super.key,
    required this.cageId,
  });

  final String cageId;

  @override
  State<CageDetailsScreen> createState() => _CageDetailsScreenState();
}

class _CageDetailsScreenState extends State<CageDetailsScreen> {
  Map<String, dynamic>? cage;
  List<Map<String, dynamic>> birdsInCage = const [];
  List<Map<String, dynamic>> cagePairs = const [];
  List<Map<String, dynamic>> mergeCandidates = const [];
  List<Map<String, dynamic>> assignedMergeableCages = const [];
  List<Map<String, dynamic>> mergedCages = const [];
  bool loading = true;
  bool busy = false;

  bool get isEmpty => birdsInCage.isEmpty;

  bool get canMerge => mergeCandidates.any(
        (candidate) => candidate['isCurrent'] != true,
      );

  @override
  void initState() {
    super.initState();
    _loadCageDetails();
  }

  String _errorText(Object error) {
    return error.toString().replaceFirst('Bad state: ', '');
  }

  void _message(Object message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_errorText(message))),
    );
  }

  Future<void> _loadCageDetails() async {
    try {
      final results = await Future.wait<dynamic>([
        DatabaseHelper.instance.getCageById(widget.cageId),
        DatabaseHelper.instance.getBirdsInCage(widget.cageId),
        DatabaseHelper.instance.getPairsForCage(widget.cageId),
        DatabaseHelper.instance.getMergeSelectionGroups(widget.cageId),
        DatabaseHelper.instance.getAssignedMergeableCages(widget.cageId),
        DatabaseHelper.instance.getMergedCagesForTarget(widget.cageId),
      ]);
      if (!mounted) return;
      setState(() {
        cage = results[0] as Map<String, dynamic>?;
        birdsInCage = results[1] as List<Map<String, dynamic>>;
        cagePairs = results[2] as List<Map<String, dynamic>>;
        mergeCandidates = results[3] as List<Map<String, dynamic>>;
        assignedMergeableCages = results[4] as List<Map<String, dynamic>>;
        mergedCages = results[5] as List<Map<String, dynamic>>;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => loading = false);
      _message(error);
    }
  }

  Future<void> _edit() async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => EditCageScreen(cageId: widget.cageId),
      ),
    );
    if (!mounted) return;
    if (result == 'deleted') {
      // Let the Edit Cage route finish its reverse transition before closing
      // this details route. Popping both routes in the same frame can leave
      // inherited-widget dependents attached during disposal.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }
    if (result == true) await _loadCageDetails();
  }

  Future<void> _merge() async {
    final selectable = mergeCandidates
        .where((candidate) => candidate['isCurrent'] != true)
        .toList();
    if (selectable.isEmpty) {
      _message('No other portion is available in this whole cage.');
      return;
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Merge with'),
          children: mergeCandidates.map((candidate) {
            final isCurrent = candidate['isCurrent'] == true;
            final birdCount = (candidate['birdCount'] as num?)?.toInt() ?? 0;
            final pairCount = (candidate['pairCount'] as num?)?.toInt() ?? 0;
            final label = candidate['label']?.toString() ?? 'Cage';
            return SimpleDialogOption(
              onPressed: isCurrent
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        Map<String, dynamic>.from(candidate),
                      ),
              child: ListTile(
                enabled: !isCurrent,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  candidate['isGroup'] == true
                      ? Icons.grid_view_rounded
                      : Icons.home_outlined,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isCurrent
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
                subtitle: Text(
                  isCurrent
                      ? 'Current portion'
                      : '$birdCount bird${birdCount == 1 ? '' : 's'} · '
                          '$pairCount pair${pairCount == 1 ? '' : 's'}',
                ),
              ),
            );
          }).toList(),
        );
      },
    );
    if (selected == null || !mounted) return;

    final memberIds = (selected['memberIds'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        const <String>[];
    if (memberIds.isEmpty) return;
    final currentLabel = cage?['identifier']?.toString() ?? 'this cage';
    final selectedLabel = selected['label']?.toString() ?? 'selected cage';
    final selectedBirds = (selected['birdCount'] as num?)?.toInt() ?? 0;
    final selectedPairs = (selected['pairCount'] as num?)?.toInt() ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Merge $selectedLabel into $currentLabel?'),
        content: Text(
          'This will combine the selected portion${memberIds.length == 1 ? '' : 's'} '
          'with $currentLabel.\n\n'
          '$selectedBirds bird${selectedBirds == 1 ? '' : 's'} and '
          '$selectedPairs pair${selectedPairs == 1 ? '' : 's'} will move to '
          '$currentLabel. The selected cage number${memberIds.length == 1 ? '' : 's'} '
          'will disappear and the remaining series will close the gap.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.call_merge),
            label: const Text('Merge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => busy = true);
    try {
      await DatabaseHelper.instance.mergeCageGroup(
        sourceCageIds: memberIds,
        targetCageId: widget.cageId,
      );
      await _loadCageDetails();
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _unmerge(Map<String, dynamic> merged) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unmerge cage?'),
        content: const Text(
          'The hidden cage portion will return to the active numbered series. '
          'All birds and pairs will remain in the current merged cage. Move them '
          'manually afterward if they belong in the restored portion. Later cage '
          'numbers may shift upward.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unmerge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => busy = true);
    try {
      await DatabaseHelper.instance.unmergeCage(merged['id'].toString());
      await _loadCageDetails();
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sell() async {
    if (!isEmpty) {
      _message('Move all birds before selling this cage.');
      return;
    }
    if (mergedCages.isNotEmpty) {
      _message('Unmerge all portions before selling this cage.');
      return;
    }

    final formKey = GlobalKey<FormState>();
    final priceController = TextEditingController();
    final buyerController = TextEditingController();
    final notesController = TextEditingController();
    var saleDate = DateTime.now();

    final details = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogBodyContext, setDialogState) => AlertDialog(
            title: const Text('Sell Cage'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Sale Price *'),
                      validator: (value) {
                        final amount = double.tryParse(value?.trim() ?? '');
                        return amount == null || amount < 0
                            ? 'Enter a valid amount'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: buyerController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Buyer'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sale Date'),
                      subtitle: Text(
                        '${saleDate.day.toString().padLeft(2, '0')}/'
                        '${saleDate.month.toString().padLeft(2, '0')}/'
                        '${saleDate.year}',
                      ),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialogBodyContext,
                          initialDate: saleDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                        );
                        if (!dialogBodyContext.mounted) return;
                        if (picked != null) {
                          setDialogState(() => saleDate = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(dialogContext, {
                    'price': double.parse(priceController.text.trim()),
                    'buyer': buyerController.text.trim(),
                    'notes': notesController.text.trim(),
                    'date': saleDate,
                  });
                },
                child: const Text('Sell'),
              ),
            ],
          ),
        );
      },
    );
    priceController.dispose();
    buyerController.dispose();
    notesController.dispose();
    if (details == null || !mounted) return;

    setState(() => busy = true);
    try {
      await DatabaseHelper.instance.sellCage(
        cageId: widget.cageId,
        soldAt: details['date'] as DateTime,
        price: details['price'] as double,
        buyer: details['buyer']?.toString(),
        notes: details['notes']?.toString(),
        financeId: const Uuid().v4(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Color _genderColor(String gender) {
    return switch (gender) {
      'Male' => const Color(0xFF2878D4),
      'Female' => const Color(0xFFD94F8A),
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  Widget _genderLabel(String gender) {
    return Text(
      gender,
      style: TextStyle(
        color: _genderColor(gender),
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Future<void> _addBird() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.swap_horiz)),
                title: const Text('Move Existing Bird'),
                subtitle: const Text('Choose any current bird and move it here.'),
                onTap: () => Navigator.pop(sheetContext, 'existing'),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.add)),
                title: const Text('Add New Bird'),
                subtitle: const Text('Create a bird with this cage already selected.'),
                onTap: () => Navigator.pop(sheetContext, 'new'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => action == 'new'
            ? AddBirdScreen(initialCageId: widget.cageId)
            : AssignBirdScreen(cageId: widget.cageId),
      ),
    );
    if (!mounted || result != true) return;
    await _loadCageDetails();
  }

  Widget _buildPairCard(Map<String, dynamic> pair) {
    final maleRing = pair['maleRingNumber']?.toString().trim() ?? '';
    final femaleRing = pair['femaleRingNumber']?.toString().trim() ?? '';
    final maleName = pair['maleName']?.toString().trim() ?? '';
    final femaleName = pair['femaleName']?.toString().trim() ?? '';
    final species = pair['speciesName']?.toString().trim() ?? '';
    final maleLabel = maleName.isEmpty
        ? (maleRing.isEmpty ? 'Unknown' : maleRing)
        : maleRing.isEmpty
            ? maleName
            : '$maleName ($maleRing)';
    final femaleLabel = femaleName.isEmpty
        ? (femaleRing.isEmpty ? 'Unknown' : femaleRing)
        : femaleRing.isEmpty
            ? femaleName
            : '$femaleName ($femaleRing)';
    final status = pair['pairStatus']?.toString() ?? 'Unknown';
    final statusIcon = switch (status) {
      'Active' => Icons.favorite,
      'Separated' => Icons.call_split,
      _ => Icons.heart_broken,
    };

    return Card(
      child: ListTile(
        leading: Icon(statusIcon),
        title: Text(
          species.isEmpty
              ? pair['identifier']?.toString() ?? 'Pair'
              : '${pair['identifier'] ?? 'Pair'} · $species',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    maleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: birdGenderTextColor(
                        pair['maleGender']?.toString(),
                      ),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _genderLabel(pair['maleGender']?.toString() ?? 'Male'),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    femaleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: birdGenderTextColor(
                        pair['femaleGender']?.toString(),
                      ),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _genderLabel(pair['femaleGender']?.toString() ?? 'Female'),
              ],
            ),
            Text('Status: $status'),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PairDetailsScreen(pairId: pair['id'].toString()),
            ),
          );
          if (mounted) await _loadCageDetails();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = cage;
    if (loading || current == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cage')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final identifier = current['identifier']?.toString() ?? 'Cage';
    final physicalName = current['identityMode'] == 'series'
        ? current['physicalName']?.toString() ?? ''
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(identifier),
        actions: [
          IconButton(
            tooltip: 'Edit Cage',
            onPressed: busy ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadCageDetails,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Card(
                  color: mergedCages.isEmpty
                      ? null
                      : AviaryColors.hatchFiveDays.withValues(alpha: .45),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AviaryIcon(AviaryIconType.cage, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    identifier,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  if (physicalName.isNotEmpty) Text(physicalName),
                                ],
                              ),
                            ),
                            if (mergedCages.isNotEmpty)
                              const Chip(label: Text('Merged')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('Type: ${current['type'] ?? ''}'),
                        if ((current['location']?.toString() ?? '').isNotEmpty)
                          Text('Location: ${current['location']}'),
                        if ((current['notes']?.toString() ?? '').isNotEmpty)
                          Text('Notes: ${current['notes']}'),
                        if (mergedCages.isEmpty &&
                            assignedMergeableCages.isNotEmpty)
                          Text(
                            'Mergeable with: ${assignedMergeableCages.map((item) => item['identifier']).join(', ')}',
                          ),
                      ],
                    ),
                  ),
                ),
                if (mergedCages.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Merged portions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...mergedCages.map((merged) {
                    final label = merged['identityMode'] == 'series'
                        ? '${merged['physicalName'] ?? 'Cage'} · Portion ${merged['portionIndex'] ?? '?'}'
                        : merged['physicalName']?.toString() ?? 'Merged cage';
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.call_merge),
                        title: Text(label),
                        trailing: OutlinedButton(
                          onPressed: busy ? null : () => _unmerge(merged),
                          child: const Text('Unmerge'),
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : _addBird,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Bird'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CreatePairScreen(
                                      cageId: widget.cageId,
                                    ),
                                  ),
                                );
                                if (result == true) await _loadCageDetails();
                              },
                        icon: const Icon(Icons.favorite),
                        label: const Text('Create Pair'),
                      ),
                    ),
                  ],
                ),
                if (canMerge || isEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (canMerge) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : _merge,
                            icon: const Icon(Icons.call_merge),
                            label: const Text('Merge'),
                          ),
                        ),
                        if (isEmpty) const SizedBox(width: 8),
                      ],
                      if (isEmpty)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : _sell,
                            icon: const Icon(Icons.sell_outlined),
                            label: const Text('Sell Cage'),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  'Pairs',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                if (cagePairs.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No pair connected to this cage'),
                    ),
                  )
                else
                  ...cagePairs.map(_buildPairCard),
                const SizedBox(height: 28),
                Text(
                  'Birds in Cage',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                if (birdsInCage.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No birds assigned'),
                    ),
                  )
                else
                  ...birdsInCage.map(
                    (bird) => Card(
                      child: ListTile(
                        leading: const FaIcon(FontAwesomeIcons.dove),
                        title: Text(
                          bird['ringNumber']?.toString() ?? 'No ring',
                          style: TextStyle(
                            color: birdGenderTextColor(
                              bird['gender']?.toString(),
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((bird['name']?.toString().trim() ?? '').isNotEmpty)
                              Text(
                                bird['name'].toString(),
                                style: TextStyle(
                                  color: birdGenderTextColor(
                                    bird['gender']?.toString(),
                                  ),
                                ),
                              ),
                            _genderLabel(bird['gender']?.toString() ?? 'Unknown'),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final fullBird = await DatabaseHelper.instance
                              .getBirdById(bird['id'].toString());

                          if (fullBird == null || !context.mounted) return;

                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BirdDetailsScreen(bird: fullBird),
                            ),
                          );

                          if (!mounted) return;
                          await _loadCageDetails();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
