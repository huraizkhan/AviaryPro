import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import 'add_egg_screen.dart';
import 'clutch_details_screen.dart';
import 'completed_clutches_screen.dart';
import 'pair_offspring_screen.dart';

class PairDetailsScreen extends StatefulWidget {
  const PairDetailsScreen({
    super.key,
    required this.pairId,
  });

  final String pairId;

  @override
  State<PairDetailsScreen> createState() => _PairDetailsScreenState();
}

class _PairDetailsScreenState extends State<PairDetailsScreen> {
  final dateFormat = DateFormat('dd-MMM-yy');
  Map<String, dynamic>? pair;
  List<Map<String, dynamic>> clutches = const [];
  List<Map<String, dynamic>> pairSessions = const [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getBreedingPairById(widget.pairId),
      DatabaseHelper.instance.getClutchesForPair(widget.pairId),
      DatabaseHelper.instance.getPairSessions(widget.pairId),
    ]);
    if (!mounted) return;
    setState(() {
      pair = results[0] as Map<String, dynamic>?;
      clutches = results[1] as List<Map<String, dynamic>>;
      pairSessions = results[2] as List<Map<String, dynamic>>;
      isLoading = false;
    });
  }

  String _birdLabel(String prefix) {
    final ring = pair?['${prefix}RingNumber']?.toString() ?? 'No ring';
    final name = pair?['${prefix}Name']?.toString().trim() ?? '';
    return name.isEmpty ? ring : '$ring ($name)';
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? 'Not set' : dateFormat.format(date);
  }

  Future<void> _addEgg() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEggScreen(pairId: widget.pairId),
      ),
    );
    if (!mounted || changed != true) return;
    await _loadData();
  }

  Future<void> _makePairActive() async {
    await DatabaseHelper.instance.makePairActive(widget.pairId);
    if (!mounted) return;
    await _loadData();
  }

  Future<void> _openClutch(Map<String, dynamic> clutch) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClutchDetailsScreen(clutchId: clutch['id'].toString()),
      ),
    );
    if (mounted) await _loadData();
  }

  Future<void> _openOffspring() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PairOffspringScreen(pairId: widget.pairId),
      ),
    );
    if (mounted) await _loadData();
  }

  Future<void> _openCompletedClutches() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompletedClutchesScreen(pairId: widget.pairId),
      ),
    );
    if (mounted) await _loadData();
  }

  Color _clutchTint(Map<String, dynamic> clutch) {
    final activeEggs = (clutch['activeEggs'] as num?)?.toInt() ?? 0;
    final chicks = (clutch['chicksInNest'] as num?)?.toInt() ?? 0;
    final next = DateTime.tryParse(
      clutch['nextExpectedHatchDate']?.toString() ?? '',
    );
    final tint = aviaryBreedingTint(
      activeEggs: activeEggs,
      chicksInNest: chicks,
      unresolvedEggs: activeEggs,
      nextHatchDate: next,
    );
    return tint == Colors.transparent ? Colors.white : tint;
  }

  Widget _countColumn(String label, Object value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            '$value',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _activeClutchCard(Map<String, dynamic> clutch) {
    final eggs = (clutch['activeEggs'] as num?)?.toInt() ?? 0;
    final expected = (clutch['expectedEggs'] as num?)?.toInt();
    final chicks = (clutch['chicksInNest'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: _clutchTint(clutch),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openClutch(clutch),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white.withValues(alpha: .74),
                      child: const AviaryIcon(AviaryIconType.egg),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'First egg: ${_formatDate(clutch['firstEggDate'])}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                const Divider(height: 22),
                Row(
                  children: [
                    _countColumn('Eggs', eggs),
                    _countColumn('Expected', expected ?? '—'),
                    _countColumn('Chicks', chicks),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pair Records',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const AviaryIcon(AviaryIconType.bird),
            title: const Text(
              'Offspring',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Open the offspring window'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openOffspring,
          ),
        ),
        Card(
          child: ListTile(
            leading: const AviaryIcon(AviaryIconType.egg),
            title: const Text(
              'Completed Clutches',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Open the completed clutches window'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openCompletedClutches,
          ),
        ),
      ],
    );
  }

  Widget _pairingPeriodsSection() {
    if (pairSessions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pairing Periods (${pairSessions.length})',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        ...pairSessions.map((session) {
          final endedAt = session['endedAt'];
          final endText = endedAt == null
              ? ' — Present'
              : ' — ${_formatDate(endedAt)}';
          final cageText = session['cageIdentifier'] == null
              ? ''
              : '\n${session['cageIdentifier']}';
          final reasonText = session['endReason'] == null
              ? ''
              : ' · ${session['endReason']}';
          return Card(
            child: ListTile(
              leading: Icon(
                endedAt == null ? Icons.favorite : Icons.history,
                color: endedAt == null ? Colors.red : null,
              ),
              title: Text(
                endedAt == null ? 'Current pairing' : 'Previous pairing',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_formatDate(session['startedAt'])}'
                '$endText$cageText$reasonText',
              ),
              isThreeLine: session['cageIdentifier'] != null,
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (pair == null) {
      return const Scaffold(body: Center(child: Text('Pair not found')));
    }

    final activeClutches =
        clutches.where((clutch) => clutch['status'] == 'Active').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(pair!['identifier']?.toString() ?? 'Pair Details'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          children: [
            Card(
              color: AviaryColors.paired,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const AviaryIcon(
                          AviaryIconType.pair,
                          color: Color(0xFFB6453F),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '${pair!['cageIdentifier'] ?? 'No cage'} → '
                            '${pair!['identifier'] ?? 'Pair'}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Male: '),
                          TextSpan(
                            text: _birdLabel('male'),
                            style: TextStyle(
                              color: birdGenderTextColor(
                                pair!['maleGender']?.toString(),
                              ),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Female: '),
                          TextSpan(
                            text: _birdLabel('female'),
                            style: TextStyle(
                              color: birdGenderTextColor(
                                pair!['femaleGender']?.toString(),
                              ),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Text('Species: ${pair!['speciesName'] ?? 'Not set'}'),
                    Text(
                      'Egg hatch rule: ${pair!['incubationDays'] ?? 'Not set'} days',
                    ),
                    Text(
                      'Clutch window: ${pair!['clutchWindowDays'] ?? 15} days',
                    ),
                    Text('Pair created: ${_formatDate(pair!['createdAt'])}'),
                    Text(
                      'Breeding status: ${pair!['breedingStatus'] ?? 'Inactive'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (pair!['breedingStatus'] != 'Active' &&
                        pair!['endedAt'] == null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _makePairActive,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Make Pair Active'),
                      ),
                    ],
                    if ((pair!['notes']?.toString().trim() ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Notes: ${pair!['notes']}'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _addEgg,
              icon: const AviaryIcon(
                AviaryIconType.egg,
                color: Colors.white,
              ),
              label: const Text('ADD EGG'),
            ),
            const SizedBox(height: 22),
            Text(
              'Active Clutches (${activeClutches.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (activeClutches.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No active clutch. Adding the next egg will create one automatically.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ...activeClutches.map(_activeClutchCard),
            const SizedBox(height: 18),
            _recordsSection(),
            const SizedBox(height: 22),
            _pairingPeriodsSection(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEgg,
        icon: const Icon(Icons.add),
        label: const Text('Egg'),
      ),
    );
  }
}
