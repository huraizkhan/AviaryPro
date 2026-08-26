import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../database/database_helper.dart';
import '../../providers/bird_provider.dart';
import '../../ui/aviary_design.dart';
import '../cages/create_pair_screen.dart';
import '../history/family_tree_screen.dart';
import '../history/history_screen.dart';
import 'bird_offspring_screen.dart';
import 'add_bird_screen.dart';
import '../../widgets/aviary_date_picker.dart';

class BirdDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> bird;

  const BirdDetailsScreen({
    super.key,
    required this.bird,
  });

  @override
  State<BirdDetailsScreen> createState() => _BirdDetailsScreenState();
}

class _BirdDetailsScreenState extends State<BirdDetailsScreen> {
  final dateFormat = DateFormat('dd-MMM-yy');
  late Map<String, dynamic> bird;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    bird = Map<String, dynamic>.from(widget.bird);
  }

  int _ageInCompletedMonths(DateTime birthDate) {
    final today = DateTime.now();
    var months = (today.year - birthDate.year) * 12;
    months += today.month - birthDate.month;
    if (today.day < birthDate.day) months--;
    return months < 0 ? 0 : months;
  }

  int _ageInDays(DateTime birthDate) {
    final today = DateTime.now();
    final start = DateTime(birthDate.year, birthDate.month, birthDate.day);
    final end = DateTime(today.year, today.month, today.day);
    return end.difference(start).inDays.clamp(0, 100000).toInt();
  }

  DateTime? _effectiveBirthDate() {
    final hatchDate = DateTime.tryParse(bird['hatchDate']?.toString() ?? '');
    if (hatchDate != null) return hatchDate;
    final sourceDate = DateTime.tryParse(bird['sourceDate']?.toString() ?? '');
    final estimatedDays = (bird['estimatedAgeDays'] as num?)?.toInt();
    if (sourceDate == null || estimatedDays == null) return null;
    return sourceDate.subtract(Duration(days: estimatedDays));
  }

  String _ageGroup() {
    final birthDate = _effectiveBirthDate();
    if (birthDate == null) {
      return bird['ageGroup']?.toString() ?? 'Unknown';
    }
    final youngAt = (bird['chickToYoungDays'] as num?)?.toInt();
    final adultAt = (bird['adultAgeMonths'] as num?)?.toInt();
    if (adultAt != null && _ageInCompletedMonths(birthDate) >= adultAt) {
      return 'Adult';
    }
    if (youngAt != null && _ageInDays(birthDate) >= youngAt) return 'Young';
    return 'Chick';
  }

  String _currentAge() {
    final birthDate = _effectiveBirthDate();
    if (birthDate == null) return '';
    final months = _ageInCompletedMonths(birthDate);
    if (months >= 12) {
      final years = months ~/ 12;
      final remainingMonths = months % 12;
      return remainingMonths == 0
          ? '$years year${years == 1 ? '' : 's'}'
          : '$years year${years == 1 ? '' : 's'}, $remainingMonths month${remainingMonths == 1 ? '' : 's'}';
    }
    if (months > 0) return '$months month${months == 1 ? '' : 's'}';
    final days = _ageInDays(birthDate);
    return '$days day${days == 1 ? '' : 's'}';
  }

  String _estimatedAgeAtAcquisition() {
    final days = (bird['estimatedAgeDays'] as num?)?.toInt();
    if (days == null) return '';
    if (days > 0 && days % 365 == 0) {
      final years = days ~/ 365;
      return '$years year${years == 1 ? '' : 's'}';
    }
    if (days > 0 && days % 30 == 0) {
      final months = days ~/ 30;
      return '$months month${months == 1 ? '' : 's'}';
    }
    return '$days day${days == 1 ? '' : 's'}';
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? '' : dateFormat.format(parsed);
  }

  String _birdLabel(String ringKey, String nameKey) {
    final ring = bird[ringKey]?.toString().trim() ?? '';
    final name = bird[nameKey]?.toString().trim() ?? '';
    if (ring.isEmpty) return '';
    return name.isEmpty ? ring : '$ring ($name)';
  }

  Future<void> _reload() async {
    setState(() => loading = true);
    final refreshed = await DatabaseHelper.instance.getBirdById(
      bird['id'].toString(),
    );
    if (!mounted) return;
    setState(() {
      if (refreshed != null) bird = refreshed;
      loading = false;
    });
    await context.read<BirdProvider>().loadBirds();
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => AddBirdScreen(bird: bird)),
    );
    if (!mounted) return;
    if (changed == 'deleted') {
      Navigator.pop(context, true);
      return;
    }
    if (changed == true) await _reload();
  }

  Future<String?> _selectDestinationCage() async {
    final cages = await DatabaseHelper.instance.getCages();
    if (!mounted) return null;
    final available = cages
        .where((cage) => cage['id']?.toString() != bird['cageId']?.toString())
        .toList();
    if (available.isEmpty) {
      _message('No other active cage is available.');
      return null;
    }

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Select New Cage'),
        children: available.map((cage) {
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
  }

  Future<void> _changeCage() async {
    final birdId = bird['id'].toString();
    final pairInfo =
        await DatabaseHelper.instance.getActivePairMoveInfo(birdId);
    if (!mounted) return;

    String action = 'single';
    if (pairInfo != null) {
      final partnerRing = pairInfo['partnerRingNumber']?.toString() ?? 'Bird';
      final partnerName = pairInfo['partnerName']?.toString().trim() ?? '';
      final partner = partnerName.isEmpty
          ? partnerRing
          : '$partnerRing ($partnerName)';
      final currentCage =
          pairInfo['cageIdentifier']?.toString() ?? 'the current cage';
      final activeClutches =
          (pairInfo['activeClutchCount'] as num?)?.toInt() ?? 0;
      final chicks = (pairInfo['chicksInNest'] as num?)?.toInt() ?? 0;

      final selectedAction = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('This bird is paired'),
          content: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: bird['ringNumber']?.toString() ?? 'This bird',
                  style: TextStyle(
                    color: birdGenderTextColor(bird['gender']?.toString()),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ' is paired with '),
                TextSpan(
                  text: partner,
                  style: TextStyle(
                    color: birdGenderTextColor(
                      pairInfo['partnerGender']?.toString(),
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: ' in $currentCage.\n\n'),
                if (activeClutches > 0 || chicks > 0)
                  TextSpan(
                    text: 'Warning: this pair has $activeClutches active '
                        'clutch(es) and $chicks chick(s) in the nest.\n\n',
                  ),
                const TextSpan(text: 'Choose how to move the bird.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'unpair'),
              child: const Text('Unpair & Move This Bird'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'pair'),
              child: const Text('Move Whole Pair'),
            ),
          ],
        ),
      );
      if (selectedAction == null || !mounted) return;
      action = selectedAction;
    }

    final destination = await _selectDestinationCage();
    if (destination == null || !mounted) return;

    try {
      if (pairInfo == null) {
        await DatabaseHelper.instance.assignBirdToCage(birdId, destination);
      } else if (action == 'pair') {
        await DatabaseHelper.instance.moveWholePairToCage(
          pairId: pairInfo['pairId'].toString(),
          cageId: destination,
        );
      } else {
        await DatabaseHelper.instance.unpairAndMoveBird(
          pairId: pairInfo['pairId'].toString(),
          birdId: birdId,
          cageId: destination,
        );
      }
      if (mounted) await _reload();
    } catch (error) {
      _message(error.toString().replaceFirst('Bad state: ', ''));
    }
  }


  Future<void> _createPair() async {
    if (bird['pairId'] != null) {
      _message('This bird already belongs to a pair');
      return;
    }
    final cageId = bird['cageId']?.toString();
    if (cageId == null || cageId.isEmpty) {
      _message('Assign this bird to a cage first');
      return;
    }
    final gender = bird['gender']?.toString();
    if (gender != 'Male' && gender != 'Female') {
      _message('Set Male or Female before creating a pair');
      return;
    }

    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePairScreen(
          cageId: cageId,
          preselectedBirdId: bird['id'].toString(),
        ),
      ),
    );
    if (!mounted || created != true) return;
    await _reload();
  }



  Future<void> _removeBird() async {
    var reason = 'Died';
    var saleDate = DateTime.now();
    var ringRemoved = false;
    final notesController = TextEditingController();
    final buyerController = TextEditingController(
      text: bird['reservedBuyer']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: bird['reservedPrice']?.toString() ?? '',
    );
    final overrideReasonController = TextEditingController();
    final isNotForSale =
        (bird['saleStatus']?.toString() ?? 'Not for Sale') == 'Not for Sale';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selling = reason == 'Sold';
          return AlertDialog(
            title: Text(selling ? 'Sell Bird' : 'Remove Bird'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: const [
                      DropdownMenuItem(value: 'Sold', child: Text('Sold')),
                      DropdownMenuItem(value: 'Died', child: Text('Died')),
                      DropdownMenuItem(
                        value: 'Flew Away',
                        child: Text('Flew Away'),
                      ),
                      DropdownMenuItem(value: 'Gifted', child: Text('Gifted')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => reason = value);
                      }
                    },
                  ),
                  if (selling) ...[
                    const SizedBox(height: 12),
                    if (isNotForSale)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AviaryColors.hatchOneDay,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'This bird has a sale warning. Confirm why you are overriding it.',
                        ),
                      ),
                    if (isNotForSale) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: overrideReasonController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Reason for selling this bird *',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: buyerController,
                      decoration: const InputDecoration(labelText: 'Buyer Name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Sold Price *'),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showAviaryDatePicker(
                          context: dialogContext,
                          initialDate: saleDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => saleDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Sale Date',
                          suffixIcon: Icon(Icons.unfold_more),
                        ),
                        child: Text(dateFormat.format(saleDate)),
                      ),
                    ),
                  ],
                  if ((bird['ringNumber']?.toString().trim() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: ringRemoved,
                      onChanged: (value) => setDialogState(
                        () => ringRemoved = value ?? false,
                      ),
                      title: const Text('Ring removed from bird'),
                      subtitle: const Text(
                        'Check this only if the physical ring was removed. It will become available for reuse.',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (selling) {
                    if (buyerController.text.trim().isEmpty) {
                      _message('Buyer name is required');
                      return;
                    }
                    final price = double.tryParse(priceController.text.trim());
                    if (price == null || price <= 0) {
                      _message('Enter a valid sold price');
                      return;
                    }
                    if (isNotForSale &&
                        overrideReasonController.text.trim().isEmpty) {
                      _message('Reason is required to override this sale warning');
                      return;
                    }
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: Text(selling ? 'Confirm Sale' : 'Remove'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      if (reason == 'Sold') {
        final override = overrideReasonController.text.trim();
        final notes = notesController.text.trim();
        await DatabaseHelper.instance.updateBirdSaleStatus(
          birdId: bird['id'].toString(),
          status: 'Sold',
          buyer: buyerController.text,
          price: double.parse(priceController.text.trim()),
          date: saleDate,
          releaseRing: ringRemoved,
          notes: [
            if (override.isNotEmpty) 'Sale override reason: $override',
            if (notes.isNotEmpty) notes,
          ].join('\n'),
        );
      } else {
        await DatabaseHelper.instance.markBirdRemoved(
          birdId: bird['id'].toString(),
          reason: reason,
          notes: notesController.text,
          releaseRing: ringRemoved,
        );
      }
      if (!mounted) return;
      await context.read<BirdProvider>().loadBirds();
      if (!mounted) return;
      Navigator.pop(context, true);
    }

    notesController.dispose();
    buyerController.dispose();
    priceController.dispose();
    overrideReasonController.dispose();
  }

  Future<void> _releaseRing() async {
    final currentRing = bird['ringNumber']?.toString().trim() ?? '';
    if (currentRing.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Ring?'),
        content: Text(
          'Remove ring $currentRing from this bird? The number will become available for another bird. The old ring stays in Bird History.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove Ring'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DatabaseHelper.instance.releaseBirdRing(bird['id'].toString());
      if (mounted) await _reload();
    } catch (error) {
      _message(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _detail(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  List<Widget> _sourceDetails() {
    final source = bird['source']?.toString() ?? '';
    final rows = <Widget>[];
    final date = _date(bird['sourceDate']);
    if (date.isNotEmpty) rows.add(_detail('Date Brought', date));
    final estimatedAtAcquisition = _estimatedAgeAtAcquisition();
    if (estimatedAtAcquisition.isNotEmpty) {
      rows.add(_detail('Age When Brought', estimatedAtAcquisition));
    }

    if (source == 'Purchase') {
      rows.add(_detail('Seller', bird['sourcePerson']?.toString() ?? ''));
      rows.add(_detail('Price', bird['purchasePrice']?.toString() ?? ''));
    } else if (source == 'Gift') {
      rows.add(_detail('Gifted By', bird['sourcePerson']?.toString() ?? ''));
    } else if (source == 'Caught') {
      rows.add(_detail('Caught From', bird['sourcePlace']?.toString() ?? ''));
    } else if (source == 'Rescued') {
      rows.add(_detail('Rescued From', bird['sourcePlace']?.toString() ?? ''));
    } else if (source == 'Other') {
      rows.add(_detail('Details', bird['sourceDetails']?.toString() ?? ''));
    }
    rows.add(_detail('Notes', bird['notes']?.toString() ?? ''));
    return rows;
  }

  String _ageDisplay() {
    final current = _currentAge().replaceAll(',', '');
    final group = _ageGroup();
    if (current.isEmpty) return group == 'Unknown' ? 'Not available' : group;
    return '$current ($group)';
  }

  Future<void> _openRelatedBird(dynamic id) async {
    final birdId = id?.toString();
    if (birdId == null || birdId.isEmpty) return;
    final related = await DatabaseHelper.instance.getBirdById(birdId);
    if (!mounted || related == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: related)),
    );
    if (mounted) await _reload();
  }

  Future<void> _openOffspring() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BirdOffspringScreen(
          birdId: bird['id'].toString(),
          birdLabel: bird['ringNumber']?.toString() ?? 'Bird',
          birdGender: bird['gender']?.toString(),
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Widget _sectionCard(String title, List<Widget> children, {Color? color}) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _relatedRow({
    required String label,
    required String value,
    required dynamic birdId,
    String? gender,
  }) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        value,
        style: TextStyle(
          color: birdGenderTextColor(gender),
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openRelatedBird(birdId),
    );
  }

  Widget _parentsRow() {
    final male = _birdLabel('parentMaleRingNumber', 'parentMaleName');
    final female = _birdLabel('parentFemaleRingNumber', 'parentFemaleName');
    if (male.isEmpty && female.isEmpty) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text('Parents', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Not linked'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Parents', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (male.isNotEmpty)
                TextButton(
                  onPressed: () => _openRelatedBird(bird['parentMaleBirdId']),
                  style: TextButton.styleFrom(
                    foregroundColor: birdGenderTextColor(
                      bird['parentMaleGender']?.toString(),
                    ),
                  ),
                  child: Text(male),
                ),
              if (male.isNotEmpty && female.isNotEmpty) const Text(' × '),
              if (female.isNotEmpty)
                TextButton(
                  onPressed: () => _openRelatedBird(bird['parentFemaleBirdId']),
                  style: TextButton.styleFrom(
                    foregroundColor: birdGenderTextColor(
                      bird['parentFemaleGender']?.toString(),
                    ),
                  ),
                  child: Text(female),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = bird['name']?.toString().trim() ?? '';
    final ringRaw = bird['ringNumber']?.toString().trim() ?? '';
    final ring = ringRaw.isEmpty ? 'No ring' : ringRaw;
    final active = bird['active'] != 0;
    final ageGroup = _ageGroup();
    final tint = bird['pairId'] != null
        ? AviaryColors.paired
        : ageGroup == 'Chick'
            ? AviaryColors.chick
            : Colors.white;
    final partner = bird['pairId'] == null
        ? ''
        : _birdLabel('partnerRingNumber', 'partnerName');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          name.isEmpty ? ring : '$ring — $name',
          style: TextStyle(
            color: birdGenderTextColor(bird['gender']?.toString()),
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                children: [
                  if (!active) ...[
                    Card(
                      color: AviaryColors.hatchOneDay,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ((bird['saleStatus']?.toString() ?? '') == 'Sold' ||
                                            (bird['removalReason']?.toString().toLowerCase() ?? '') == 'sold')
                                        ? 'SOLD'
                                        : (bird['removalReason']?.toString().trim().isNotEmpty ?? false)
                                            ? bird['removalReason'].toString().toUpperCase()
                                            : 'REMOVED',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (_date(bird['removedAt']).isNotEmpty)
                                    Text(
                                      ((bird['saleStatus']?.toString() ?? '') == 'Sold' ||
                                              (bird['removalReason']?.toString().toLowerCase() ?? '') == 'sold')
                                          ? 'Sold: ${_date(bird['removedAt'])}'
                                          : 'Removed: ${_date(bird['removedAt'])}',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  if ((bird['saleStatus']?.toString() ?? '') == 'Sold' &&
                                      bird['soldPrice'] != null)
                                    Text(
                                      'Sale share: ${bird['soldPrice']}',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Card(
                    color: tint,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? ring : '$ring  ·  $name',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: birdGenderTextColor(
                                    bird['gender']?.toString(),
                                  ),
                                ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const AviaryIcon(AviaryIconType.cage, size: 18),
                              const SizedBox(width: 7),
                              Text(
                                aviaryCageLabel(
                                  bird['cageIdentifier'],
                                  emptyLabel: 'No current cage',
                                ),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          if ((bird['saleStatus']?.toString() ?? 'Not for Sale') != 'Not for Sale') ...[
                            const SizedBox(height: 7),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(bird['saleStatus'].toString()),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _sectionCard('Genetics', [
                    _detail('Species', bird['speciesName']?.toString() ?? ''),
                    _detail('Mutation', bird['mutation']?.toString() ?? ''),
                    _detail('Gender', bird['gender']?.toString() ?? ''),
                    _detail(
                      'Eye Color',
                      (bird['eyeColor']?.toString().trim() ?? '').isEmpty
                          ? ''
                          : '${bird['eyeColor']} eyes',
                    ),
                    _detail('Chick Down', bird['downColor']?.toString() ?? ''),
                  ]),
                  const SizedBox(height: 10),
                  _sectionCard('Age', [
                    _detail('Age', _ageDisplay()),
                    _detail('Hatch Date', _date(bird['hatchDate'])),
                  ]),
                  const SizedBox(height: 10),
                  _sectionCard('Relations', [
                    _parentsRow(),
                    if (partner.isNotEmpty)
                      _relatedRow(
                        label: 'Pair',
                        value: partner,
                        birdId: bird['partnerBirdId'],
                        gender: bird['partnerGender']?.toString(),
                      )
                    else
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('Pair', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('Not currently paired'),
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const AviaryIcon(AviaryIconType.chick),
                      title: const Text(
                        'Offspring',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('All offspring across every spouse'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openOffspring,
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text(
                        'Source',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(bird['source']?.toString() ?? 'Not set'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      children: _sourceDetails(),
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _changeCage,
                      icon: const AviaryIcon(AviaryIconType.cage),
                      label: const Text('Change Cage'),
                    ),
                    if (bird['pairId'] == null) ...[
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: _createPair,
                        icon: const AviaryIcon(AviaryIconType.pair),
                        label: const Text('Create Pair'),
                      ),
                    ],
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _removeBird,
                      icon: const Icon(Icons.person_remove_outlined),
                      label: const Text('Remove / Sell Bird'),
                    ),
                  ],
                  if (!active && ringRaw.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _releaseRing,
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Remove Ring'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FamilyTreeScreen(
                            initialBirdId: bird['id'].toString(),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('View Family Tree'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HistoryScreen(
                            birdId: bird['id'].toString(),
                            birdLabel: name.isEmpty ? ring : '$ring — $name',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history_outlined),
                    label: const Text('View Bird History'),
                  ),
                ],
              ),
            ),
    );
  }
}
