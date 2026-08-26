import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';

import '../../database/database_helper.dart';
import '../../providers/bird_provider.dart';
import '../../services/notification_service.dart';
import '../../ui/aviary_design.dart';
import '../birds/bird_details_screen.dart';
import 'add_egg_screen.dart';
import 'select_foster_clutch_screen.dart';
import '../../widgets/aviary_date_picker.dart';

class ClutchDetailsScreen extends StatefulWidget {
  final String clutchId;

  const ClutchDetailsScreen({
    super.key,
    required this.clutchId,
  });

  @override
  State<ClutchDetailsScreen> createState() => _ClutchDetailsScreenState();
}

class _ClutchDetailsScreenState extends State<ClutchDetailsScreen> {
  static const eggStatuses = <String>[
    'Incubating',
    'Fertile',
    'Infertile',
    'Dead Embryo',
    'Cracked',
    'Missing',
  ];

  final dateFormat = DateFormat('dd-MMM-yy');
  Map<String, dynamic>? clutch;
  List<Map<String, dynamic>> eggs = [];
  List<Map<String, dynamic>> chicks = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait<dynamic>([
        DatabaseHelper.instance.getClutchById(widget.clutchId),
        DatabaseHelper.instance.getEggsForClutch(widget.clutchId),
        DatabaseHelper.instance.getChicksForClutch(widget.clutchId),
      ]);
      if (!mounted) return;
      setState(() {
        clutch = results[0] as Map<String, dynamic>?;
        eggs = results[1] as List<Map<String, dynamic>>;
        chicks = results[2] as List<Map<String, dynamic>>;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _message('Clutch could not be loaded: $error');
    }
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? 'Not set' : dateFormat.format(date);
  }

  Future<void> _addEgg() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEggScreen(
          pairId: clutch?['pairId']?.toString(),
          clutchId: widget.clutchId,
        ),
      ),
    );
    if (!mounted || result != true) return;
    await _loadData();
    await NotificationService.instance.syncFromDatabase();
  }

  int get _biologicalEggCount => eggs
      .where((egg) => egg['clutchId']?.toString() == widget.clutchId)
      .length;

  Future<void> _editExpectedEggs() async {
    if (_biologicalEggCount == 0) {
      _message('Record the first egg before adding an expectation.');
      return;
    }

    final value = await showDialog<int>(
      context: context,
      builder: (_) => _ExpectedEggsDialog(
        recordedEggs: _biologicalEggCount,
        currentExpectedEggs: (clutch?['expectedEggs'] as num?)?.toInt(),
      ),
    );
    if (!mounted || value == null) return;

    await DatabaseHelper.instance.setExpectedEggs(
      clutchId: widget.clutchId,
      expectedEggs: value,
    );
    if (mounted) await _loadData();
  }

  Future<void> _clearExpectedEggs() async {
    await DatabaseHelper.instance.setExpectedEggs(
      clutchId: widget.clutchId,
      expectedEggs: null,
    );
    if (mounted) await _loadData();
  }

  Future<void> _changeEggStatus(
    Map<String, dynamic> egg,
    String status,
  ) async {
    await DatabaseHelper.instance.updateEggStatus(
      eggId: egg['id'].toString(),
      status: status,
    );
    if (!mounted) return;
    await _loadData();
    await NotificationService.instance.syncFromDatabase();
  }

  Future<void> _hatchEgg(Map<String, dynamic> egg) async {
    final result = await showDialog<_HatchEggResult>(
      context: context,
      builder: (_) => _HatchEggDialog(
        eggNumber: egg['eggNumber']?.toString() ?? '?',
      ),
    );
    if (!mounted || result == null) return;

    try {
      await DatabaseHelper.instance.hatchEgg(
        eggId: egg['id'].toString(),
        birdId: const Uuid().v4(),
        ringNumber: result.ringNumber,
        hatchDate: result.hatchDate,
        name: result.name,
        eyeColor: result.eyeColor,
        downColor: result.downColor,
        notes: result.notes,
      );
      if (!mounted) return;
      await context.read<BirdProvider>().loadBirds();
      if (!mounted) return;
      await _loadData();
      await NotificationService.instance.syncFromDatabase();
    } catch (error) {
      if (!mounted) return;
      _message(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _fosterEgg(Map<String, dynamic> egg) async {
    final targetClutchId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectFosterClutchScreen(
          excludedClutchId:
              egg['currentClutchId']?.toString() ?? egg['clutchId'].toString(),
        ),
      ),
    );
    if (!mounted || targetClutchId == null) return;

    await DatabaseHelper.instance.fosterEgg(
      eggId: egg['id'].toString(),
      targetClutchId: targetClutchId,
    );
    if (!mounted) return;
    await _loadData();
    await NotificationService.instance.syncFromDatabase();
  }

  Future<void> _fosterChick(Map<String, dynamic> chick) async {
    final targetClutchId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectFosterClutchScreen(
          excludedClutchId: chick['nestClutchId']?.toString(),
        ),
      ),
    );
    if (!mounted || targetClutchId == null) return;

    await DatabaseHelper.instance.fosterChick(
      birdId: chick['id'].toString(),
      targetClutchId: targetClutchId,
    );
    if (!mounted) return;
    await context.read<BirdProvider>().loadBirds();
    if (!mounted) return;
    await _loadData();
  }

  Future<void> _moveChick(Map<String, dynamic> chick) async {
    final cages = await DatabaseHelper.instance.getCages();
    if (!mounted) return;
    final currentCageId = chick['cageId']?.toString();
    final availableCages = cages
        .where((cage) => cage['id']?.toString() != currentCageId)
        .toList();
    if (availableCages.isEmpty) {
      _message('Add a separate cage first');
      return;
    }

    final cageId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Move Chick to Cage'),
        children: availableCages.map((cage) {
          final physicalName = cage['identityMode'] == 'series'
              ? cage['physicalName']?.toString() ?? ''
              : '';
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(
              dialogContext,
              cage['id'].toString(),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const AviaryIcon(AviaryIconType.cage),
              title: Text(cage['identifier']?.toString() ?? 'Cage'),
              subtitle: Text(
                [
                  if (physicalName.isNotEmpty) physicalName,
                  if ((cage['location']?.toString() ?? '').isNotEmpty)
                    cage['location'].toString(),
                ].join(' · '),
              ),
            ),
          );
        }).toList(),
      ),
    );
    if (!mounted || cageId == null) return;

    final speciesId = chick['speciesId']?.toString();
    if (speciesId == null || speciesId.isEmpty) {
      _message('This chick does not have a species assigned.');
      return;
    }
    final ringRanges =
        await DatabaseHelper.instance.getRingRanges(speciesId: speciesId);
    if (!mounted) return;
    if (ringRanges.isEmpty) {
      _message('Configure rings for this species in Settings > Ring Management first.');
      return;
    }
    final permanentRings =
        await DatabaseHelper.instance.getAvailableRingNumbers(speciesId);
    if (!mounted) return;
    if (permanentRings.isEmpty) {
      _message('No permanent rings are available for this species.');
      return;
    }

    var selectedPermanentRing = permanentRings.first;
    var notForSale = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Move Chick to Cage'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This youngster will be For Sale by default.'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedPermanentRing,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Permanent Ring *',
                  helperText: 'Temporary chick ID stays in history.',
                  border: OutlineInputBorder(),
                ),
                items: permanentRings
                    .map((ring) => DropdownMenuItem(
                          value: ring,
                          child: Text(ring),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedPermanentRing = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: notForSale,
                onChanged: (value) =>
                    setDialogState(() => notForSale = value ?? false),
                title: const Text('Mark Not for Sale'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Move'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;

    await DatabaseHelper.instance.moveChickFromNest(
      birdId: chick['id'].toString(),
      cageId: cageId,
      saleStatus: notForSale ? 'Not for Sale' : 'Available',
      permanentRingNumber: selectedPermanentRing,
    );
    if (!mounted) return;
    await context.read<BirdProvider>().loadBirds();
    if (!mounted) return;
    await _loadData();
  }


  Future<void> _markChickDied(Map<String, dynamic> chick) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark chick as died?'),
        content: Text(
          chick['ringNumber']?.toString() ?? 'Chick',
          style: TextStyle(
            color: birdGenderTextColor(chick['gender']?.toString()),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await DatabaseHelper.instance.markChickDied(chick['id'].toString());
    if (!mounted) return;
    await context.read<BirdProvider>().loadBirds();
    if (!mounted) return;
    await _loadData();
  }

  Future<void> _openBird(Map<String, dynamic> chick) async {
    final bird = await DatabaseHelper.instance.getBirdById(chick['id'].toString());
    if (!mounted || bird == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: bird)),
    );
    if (!mounted) return;
    await _loadData();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Color _eggTint(Map<String, dynamic> egg) {
    final status = egg['status']?.toString() ?? 'Incubating';
    if (status == 'Hatched') return AviaryColors.chicksHatched;
    if (!const ['Incubating', 'Fertile'].contains(status)) {
      return AviaryColors.expense.withValues(alpha: .75);
    }
    final expected = DateTime.tryParse(
      egg['expectedHatchDate']?.toString() ?? '',
    );
    return aviaryBreedingTint(
      activeEggs: 1,
      chicksInNest: 0,
      unresolvedEggs: 1,
      nextHatchDate: expected,
    );
  }

  Color _clutchTint() {
    final unresolved = eggs.where((egg) {
      return const ['Incubating', 'Fertile']
          .contains(egg['status']?.toString());
    }).length;
    final inNest = chicks.where((chick) {
      return chick['leftNestDate'] == null && chick['active'] != 0;
    }).length;
    DateTime? next;
    for (final egg in eggs) {
      if (!const ['Incubating', 'Fertile']
          .contains(egg['status']?.toString())) {
        continue;
      }
      final date = DateTime.tryParse(
        egg['expectedHatchDate']?.toString() ?? '',
      );
      if (date != null && (next == null || date.isBefore(next))) next = date;
    }
    final tint = aviaryBreedingTint(
      activeEggs: unresolved,
      chicksInNest: inNest,
      unresolvedEggs: unresolved,
      nextHatchDate: next,
    );
    return tint;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (clutch == null) {
      return const Scaffold(
        body: Center(child: Text('Clutch not found')),
      );
    }

    final isActive = clutch!['status'] == 'Active';
    return Scaffold(
      appBar: AppBar(
        title: Text('Clutch ${clutch!['clutchNumber'] ?? ''}'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          children: [
            Card(
              color: aviaryCardSurface(context, tint: _clutchTint()),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${clutch!['cageIdentifier'] ?? 'No cage'} → '
                      '${clutch!['pairIdentifier'] ?? 'Pair'} → '
                      'Clutch ${clutch!['clutchNumber']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: clutch!['maleRingNumber']?.toString() ?? 'Male',
                            style: TextStyle(
                              color: birdGenderTextColor(
                                clutch!['maleGender']?.toString(),
                              ),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: ' × '),
                          TextSpan(
                            text: clutch!['femaleRingNumber']?.toString() ?? 'Female',
                            style: TextStyle(
                              color: birdGenderTextColor(
                                clutch!['femaleGender']?.toString(),
                              ),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text('First egg: ${_formatDate(clutch!['firstEggDate'])}'),
                    Text('Status: ${clutch!['status']}'),
                    Text(
                      'Incubation: ${clutch!['incubationDays'] ?? 'Not set'} days',
                    ),
                    if ((clutch!['notes']?.toString().trim() ?? '').isNotEmpty)
                      Text('Notes: ${clutch!['notes']}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (isActive) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Expected Eggs',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              clutch!['expectedEggs'] == null
                                  ? 'Not set'
                                  : '${clutch!['expectedEggs']} expected · $_biologicalEggCount recorded',
                            ),
                          ],
                        ),
                      ),
                      if (clutch!['expectedEggs'] != null)
                        TextButton(
                          onPressed: _clearExpectedEggs,
                          child: const Text('No More Eggs Expected'),
                        )
                      else
                        OutlinedButton(
                          onPressed: _editExpectedEggs,
                          child: const Text('Set'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Text(
                  'Eggs (${eggs.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (isActive)
                  FilledButton.icon(
                    onPressed: _addEgg,
                    icon: const Icon(Icons.add),
                    label: const Text('Egg'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (eggs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No eggs currently connected to this clutch.'),
                ),
              )
            else
              ...eggs.map(_eggCard),
            const SizedBox(height: 18),
            Text(
              'Chicks in This Nest (${chicks.where((c) => c['leftNestDate'] == null && c['active'] != 0).length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (chicks.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No chicks in this nest.'),
                ),
              )
            else
              ...chicks.map(_chickCard),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'The clutch closes automatically after every egg is resolved and every chick has left the nest or is marked died.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEggStatusPicker(Map<String, dynamic> egg) async {
    final current = egg['status']?.toString() ?? 'Incubating';
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Wrap(
            runSpacing: 6,
            children: [
              ListTile(
                title: const Text(
                  'Change egg status',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('Current: $current'),
              ),
              ...eggStatuses
                  .where((status) => status != current)
                  .map(
                    (status) => ListTile(
                      leading: const Icon(Icons.egg_outlined),
                      title: Text(status),
                      onTap: () => Navigator.pop(sheetContext, status),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    await _changeEggStatus(egg, selected);
  }

  Widget _eggCard(Map<String, dynamic> egg) {
    final status = egg['status']?.toString() ?? 'Incubating';
    final fostered = egg['isFostered'] == 1;
    final isHatched = status == 'Hatched';
    final isPending = status == 'Incubating' || status == 'Fertile';

    return Card(
      color: aviaryCardSurface(context, tint: _eggTint(egg)),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: aviaryAvatarSurface(context),
          child: AviaryIcon(
            isHatched ? AviaryIconType.chick : AviaryIconType.egg,
          ),
        ),
        title: Text('Egg ${egg['eggNumber']} — $status'),
        subtitle: Text(
          'Laid: ${_formatDate(egg['laidDate'])}\n'
          'Expected: ${_formatDate(egg['expectedHatchDate'])}'
          '${fostered ? '\nFostered to ${egg['currentCageIdentifier'] ?? 'cage'} — ${egg['currentPairIdentifier'] ?? 'pair'}' : ''}'
          '${(egg['notes']?.toString().trim() ?? '').isNotEmpty ? '\nNote: ${egg['notes']}' : ''}',
        ),
        isThreeLine: true,
        trailing: isPending
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _hatchEgg(egg),
                    icon: const AviaryIcon(AviaryIconType.chick, size: 18),
                    label: const Text('Hatch'),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More egg actions',
                    onSelected: (value) {
                      if (value == 'foster') _fosterEgg(egg);
                      if (value == 'status') _showEggStatusPicker(egg);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'foster',
                        child: Text('Foster Egg'),
                      ),
                      PopupMenuItem(
                        value: 'status',
                        child: Text('Change Status…'),
                      ),
                    ],
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _chickCard(Map<String, dynamic> chick) {
    final active = chick['active'] != 0;
    final inNest = chick['leftNestDate'] == null && active;
    final name = chick['name']?.toString().trim() ?? '';
    final ring = chick['ringNumber']?.toString() ?? 'Chick';

    return Card(
      color: aviaryCardSurface(context, tint: AviaryColors.chick),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _openBird(chick),
        leading: CircleAvatar(
          backgroundColor: aviaryAvatarSurface(context),
          child: const AviaryIcon(AviaryIconType.chick),
        ),
        title: Text(
          name.isEmpty ? ring : '$ring — $name',
          style: TextStyle(
            color: birdGenderTextColor(chick['gender']?.toString()),
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          'Hatched: ${_formatDate(chick['hatchDate'])}\n'
          '${inNest ? 'In nest' : active ? 'Moved to ${chick['cageIdentifier'] ?? 'another cage'}' : 'Removed: ${chick['removalReason'] ?? 'Inactive'}'}',
        ),
        isThreeLine: true,
        trailing: inNest
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'move') _moveChick(chick);
                  if (value == 'foster') _fosterChick(chick);
                  if (value == 'died') _markChickDied(chick);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'move', child: Text('Move to Cage')),
                  PopupMenuItem(value: 'foster', child: Text('Foster Chick')),
                  PopupMenuItem(value: 'died', child: Text('Mark Died')),
                ],
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _HatchEggResult {
  final String ringNumber;
  final String name;
  final String notes;
  final String? eyeColor;
  final String? downColor;
  final DateTime hatchDate;

  const _HatchEggResult({
    required this.ringNumber,
    required this.name,
    required this.notes,
    required this.eyeColor,
    required this.downColor,
    required this.hatchDate,
  });
}

class _HatchEggDialog extends StatefulWidget {
  final String eggNumber;

  const _HatchEggDialog({required this.eggNumber});

  @override
  State<_HatchEggDialog> createState() => _HatchEggDialogState();
}

class _HatchEggDialogState extends State<_HatchEggDialog> {
  late final TextEditingController _ringController;
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _dateFormat = DateFormat('dd-MMM-yy');
  DateTime _hatchDate = DateTime.now();
  String? _eyeColor;
  String? _downColor;
  String? _ringError;
  bool _closing = false;

  void _cancelSafely() {
    if (_closing) return;
    _closing = true;
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _ringController = TextEditingController(
      text: 'CH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
    );
  }

  @override
  void dispose() {
    _ringController.dispose();
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showAviaryDatePicker(
      context: context,
      initialDate: _hatchDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (!mounted || picked == null) return;
    setState(() => _hatchDate = picked);
  }

  void _submit() {
    final ring = _ringController.text.trim();
    if (ring.isEmpty) {
      setState(() => _ringError = 'Ring number is required.');
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _HatchEggResult(
        ringNumber: ring,
        name: _nameController.text.trim(),
        notes: _notesController.text.trim(),
        eyeColor: _eyeColor,
        downColor: _downColor,
        hatchDate: _hatchDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _cancelSafely();
      },
      child: AlertDialog(
      title: Text('Hatch Egg ${widget.eggNumber}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ringController,
              decoration: InputDecoration(
                labelText: 'Chick ID / Ring Number',
                errorText: _ringError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _eyeColor,
                    decoration: const InputDecoration(
                      labelText: 'Eye Color',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Black', child: Text('Black eyes')),
                      DropdownMenuItem(value: 'Red', child: Text('Red eyes')),
                    ],
                    onChanged: (value) => setState(() => _eyeColor = value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _downColor,
                    decoration: const InputDecoration(
                      labelText: 'Down Color',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'White', child: Text('White')),
                      DropdownMenuItem(value: 'Yellow', child: Text('Yellow')),
                    ],
                    onChanged: (value) => setState(() => _downColor = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Hatch Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.unfold_more),
                ),
                child: Text(_dateFormat.format(_hatchDate)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancelSafely,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Hatch'),
        ),
      ],
      ),
    );
  }
}

class _ExpectedEggsDialog extends StatefulWidget {
  final int recordedEggs;
  final int? currentExpectedEggs;

  const _ExpectedEggsDialog({
    required this.recordedEggs,
    required this.currentExpectedEggs,
  });

  @override
  State<_ExpectedEggsDialog> createState() => _ExpectedEggsDialogState();
}

class _ExpectedEggsDialogState extends State<_ExpectedEggsDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentExpectedEggs?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      setState(() => _errorText = 'Enter a valid number.');
      return;
    }
    if (parsed <= widget.recordedEggs) {
      setState(
        () => _errorText =
            'Expected eggs must be more than ${widget.recordedEggs}.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Expected Eggs'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        decoration: InputDecoration(
          labelText: 'Expected total eggs',
          helperText: 'Currently recorded: ${widget.recordedEggs}',
          errorText: _errorText,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

