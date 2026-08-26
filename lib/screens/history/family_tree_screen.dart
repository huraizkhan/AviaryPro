import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../birds/bird_details_screen.dart';
import '../birds/bird_history_summary_screen.dart';

class FamilyTreeScreen extends StatefulWidget {
  final String? initialBirdId;

  const FamilyTreeScreen({super.key, this.initialBirdId});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  bool loading = true;
  List<Map<String, dynamic>> birds = const [];
  Map<String, dynamic>? focus;
  Map<String, dynamic>? father;
  Map<String, dynamic>? mother;
  List<Map<String, dynamic>> spouses = const [];
  List<Map<String, dynamic>> offspring = const [];

  @override
  void initState() {
    super.initState();
    _load(widget.initialBirdId);
  }

  String _label(Map<String, dynamic>? bird, {
    String ringKey = 'ringNumber',
    String nameKey = 'name',
  }) {
    if (bird == null) return 'Unknown';
    final ring = bird[ringKey]?.toString().trim() ?? '';
    final name = bird[nameKey]?.toString().trim() ?? '';
    if (ring.isEmpty && name.isEmpty) return 'No ring';
    if (ring.isEmpty) return name;
    return name.isEmpty ? ring : '$ring — $name';
  }

  String _status(Map<String, dynamic> bird) {
    if (bird['active'] != 0) return '';
    final reason = bird['removalReason']?.toString().trim() ?? '';
    if ((bird['saleStatus']?.toString() ?? '') == 'Sold' ||
        reason.toLowerCase() == 'sold') {
      return 'Sold';
    }
    return reason.isEmpty ? 'Removed' : reason;
  }

  Future<void> _load(String? requestedId) async {
    if (mounted) setState(() => loading = true);
    final all = await DatabaseHelper.instance.getBirds();
    if (!mounted) return;
    if (all.isEmpty) {
      setState(() {
        birds = const [];
        focus = null;
        father = null;
        mother = null;
        spouses = const [];
        offspring = const [];
        loading = false;
      });
      return;
    }

    var id = requestedId;
    if (id == null || !all.any((bird) => bird['id']?.toString() == id)) {
      id = all.first['id'].toString();
    }

    final selected = await DatabaseHelper.instance.getBirdById(id);
    if (selected == null || !mounted) return;

    Map<String, dynamic>? fatherBird;
    Map<String, dynamic>? motherBird;
    final fatherId = selected['parentMaleBirdId']?.toString();
    final motherId = selected['parentFemaleBirdId']?.toString();
    if (fatherId != null && fatherId.isNotEmpty) {
      fatherBird = await DatabaseHelper.instance.getBirdById(fatherId);
    }
    if (motherId != null && motherId.isNotEmpty) {
      motherBird = await DatabaseHelper.instance.getBirdById(motherId);
    }
    final mateRows = await DatabaseHelper.instance.getBirdSpouses(id);
    final childRows = await DatabaseHelper.instance.getOffspringForBird(id);
    if (!mounted) return;

    setState(() {
      birds = all;
      focus = selected;
      father = fatherBird;
      mother = motherBird;
      spouses = mateRows;
      offspring = childRows;
      loading = false;
    });
  }

  Future<void> _chooseBird() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose Bird',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: birds.length,
                  itemBuilder: (_, index) {
                    final bird = birds[index];
                    final status = _status(bird);
                    return ListTile(
                      leading: const AviaryIcon(AviaryIconType.bird),
                      title: Text(
                        _label(bird),
                        style: TextStyle(
                          color: birdGenderTextColor(bird['gender']?.toString()),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${bird['speciesName'] ?? ''}'
                        '${status.isEmpty ? '' : ' · $status'}',
                      ),
                      onTap: () => Navigator.pop(
                        sheetContext,
                        bird['id'].toString(),
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
    if (selected != null) await _load(selected);
  }

  Future<void> _openFocusDetails() async {
    final selected = focus;
    if (selected == null) return;
    await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: selected)),
    );
    if (mounted) await _load(selected['id'].toString());
  }

  Widget _connector({double height = 20}) => Center(
        child: Container(
          width: 2,
          height: height,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      );

  Widget _birdCard(
    Map<String, dynamic>? bird, {
    required String gender,
    required VoidCallback? onTap,
    String? statusOverride,
  }) {
    final color = birdGenderTextColor(gender);
    final status = bird == null
        ? ''
        : (statusOverride?.trim().isNotEmpty ?? false)
            ? statusOverride!.trim()
            : _status(bird);
    final species = bird?['speciesName']?.toString().trim() ?? '';
    final mutation = bird?['mutation']?.toString().trim() ?? '';
    final detail = [species, mutation]
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    gender.toLowerCase() == 'male'
                        ? Icons.male
                        : gender.toLowerCase() == 'female'
                            ? Icons.female
                            : Icons.help_outline,
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _label(bird),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                  if (onTap != null) const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 4),
              Text(
                gender.isEmpty ? 'Unknown' : gender,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  status,
                  style: const TextStyle(
                    color: Colors.deepOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _spouseBird(Map<String, dynamic> spouse) {
    final id = spouse['spouseBirdId']?.toString();
    if (id == null || id.isEmpty) return null;
    return {
      'id': id,
      'ringNumber': spouse['spouseRingNumber'],
      'name': spouse['spouseName'],
      'gender': spouse['spouseGender'],
      'mutation': spouse['spouseMutation'],
      'speciesName': spouse['spouseSpeciesName'],
      'active': spouse['spouseActive'],
      'removalReason': spouse['spouseRemovalReason'],
      'saleStatus': spouse['spouseSaleStatus'],
    };
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final selected = focus;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Tree'),
        actions: [
          if (birds.isNotEmpty)
            IconButton(
              tooltip: 'Choose bird',
              onPressed: _chooseBird,
              icon: const Icon(Icons.search),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : selected == null
              ? const Center(child: Text('No birds found.'))
              : RefreshIndicator(
                  onRefresh: () => _load(selected['id'].toString()),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      AviaryLayout.horizontalPadding(context),
                      12,
                      AviaryLayout.horizontalPadding(context),
                      100,
                    ),
                    children: [
                      Card(
                        color: aviaryCardSurface(
                          context,
                          tint: AviaryColors.history.withValues(alpha: .10),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _openFocusDetails,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor:
                                      AviaryColors.history.withValues(alpha: .16),
                                  child: const AviaryIcon(AviaryIconType.bird),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Selected Bird',
                                        style: TextStyle(
                                          color: AviaryColors.history,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        _label(selected),
                                        style: TextStyle(
                                          color: birdGenderTextColor(
                                            selected['gender']?.toString(),
                                          ),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        '${selected['speciesName'] ?? ''}'
                                        '${_status(selected).isEmpty ? '' : ' · ${_status(selected)}'}',
                                      ),
                                    ],
                                  ),
                                ),
                                if (MediaQuery.sizeOf(context).width < 360)
                                  IconButton(
                                    tooltip: 'Change bird',
                                    onPressed: _chooseBird,
                                    icon: const Icon(Icons.edit_outlined, size: 19),
                                  )
                                else
                                  TextButton.icon(
                                    onPressed: _chooseBird,
                                    icon: const Icon(Icons.edit_outlined, size: 17),
                                    label: const Text('Change'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _sectionTitle('Parents'),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _birdCard(
                              father,
                              gender: 'Male',
                              onTap: father == null
                                  ? null
                                  : () => _load(father!['id'].toString()),
                            ),
                          ),
                          SizedBox(width: AviaryLayout.isCompact(context) ? 6 : 10),
                          Expanded(
                            child: _birdCard(
                              mother,
                              gender: 'Female',
                              onTap: mother == null
                                  ? null
                                  : () => _load(mother!['id'].toString()),
                            ),
                          ),
                        ],
                      ),
                      _connector(),
                      Center(
                        child: SizedBox(
                          width: (MediaQuery.sizeOf(context).width * .62)
                              .clamp(190.0, 430.0)
                              .toDouble(),
                          child: _birdCard(
                            selected,
                            gender: selected['gender']?.toString() ?? 'Unknown',
                            onTap: _openFocusDetails,
                            statusOverride: _status(selected),
                          ),
                        ),
                      ),
                      if (spouses.isNotEmpty) ...[
                        _connector(),
                        _sectionTitle(
                          spouses.first['endedAt'] == null
                              ? 'Current Mate'
                              : 'Previous Mate',
                        ),
                        ...spouses.map((spouse) {
                          final mate = _spouseBird(spouse);
                          final previous = spouse['endedAt'] != null;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _birdCard(
                              mate,
                              gender: spouse['spouseGender']?.toString() ?? 'Unknown',
                              statusOverride: previous ? 'Previous pair' : null,
                              onTap: mate == null
                                  ? null
                                  : () => _load(mate['id'].toString()),
                            ),
                          );
                        }),
                      ],
                      if (offspring.isNotEmpty) ...[
                        _connector(),
                        _sectionTitle('Offspring (${offspring.length})'),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = (constraints.maxWidth - 10) / 2;
                            return Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: offspring.map((child) {
                                return SizedBox(
                                  width: width,
                                  child: _birdCard(
                                    child,
                                    gender:
                                        child['gender']?.toString() ?? 'Unknown',
                                    statusOverride:
                                        child['currentStatus']?.toString() == 'Present'
                                            ? ''
                                            : child['currentStatus']?.toString(),
                                    onTap: () => _load(child['id'].toString()),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ] else ...[
                        _connector(),
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No offspring recorded for this bird.'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BirdHistorySummaryScreen(
                                birdId: selected['id'].toString(),
                                birdLabel: _label(selected),
                                birdGender: selected['gender']?.toString(),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.history),
                        label: const Text('Record History'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
