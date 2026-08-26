import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../birds/bird_details_screen.dart';

class PairOffspringScreen extends StatefulWidget {
  const PairOffspringScreen({
    super.key,
    required this.pairId,
  });

  final String pairId;

  @override
  State<PairOffspringScreen> createState() => _PairOffspringScreenState();
}

class _PairOffspringScreenState extends State<PairOffspringScreen> {
  final _dateFormat = DateFormat('dd-MMM-yy');
  Map<String, dynamic>? _pair;
  List<Map<String, dynamic>> _offspring = const [];
  String _view = 'current';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getBreedingPairById(widget.pairId),
      DatabaseHelper.instance.getOffspringForPair(widget.pairId),
    ]);
    if (!mounted) return;
    setState(() {
      _pair = results[0] as Map<String, dynamic>?;
      _offspring = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? 'Not set' : _dateFormat.format(date);
  }

  int _ageInCompletedMonths(DateTime birthDate) {
    final today = DateTime.now();
    var months = (today.year - birthDate.year) * 12;
    months += today.month - birthDate.month;
    if (today.day < birthDate.day) months--;
    return months < 0 ? 0 : months;
  }

  String _ageGroup(Map<String, dynamic> bird) {
    final hatchDate = DateTime.tryParse(bird['hatchDate']?.toString() ?? '');
    if (hatchDate == null) {
      return bird['ageGroup']?.toString() ?? 'Unknown';
    }
    final adultMonths = (bird['adultAgeMonths'] as num?)?.toInt();
    if (adultMonths != null &&
        adultMonths > 0 &&
        _ageInCompletedMonths(hatchDate) >= adultMonths) {
      return 'Adult';
    }
    final chickToYoungDays = (bird['chickToYoungDays'] as num?)?.toInt();
    final days = DateTime.now().difference(hatchDate).inDays;
    if (chickToYoungDays != null &&
        chickToYoungDays > 0 &&
        days >= chickToYoungDays) {
      return 'Young';
    }
    return 'Chick';
  }

  Color _tint(Map<String, dynamic> child) {
    return switch (child['currentStatus']?.toString()) {
      'Present' => AviaryColors.birds.withValues(alpha: .10),
      'Deceased' => Colors.red.withValues(alpha: .10),
      _ => Colors.grey.withValues(alpha: .12),
    };
  }

  List<Map<String, dynamic>> get _visible {
    if (_view == 'all') return _offspring;
    return _offspring
        .where((child) => child['currentStatus']?.toString() == 'Present')
        .toList();
  }

  Widget _countChip(String label, int count) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label: $count'),
    );
  }

  Future<void> _openBird(Map<String, dynamic> child) async {
    final bird =
        await DatabaseHelper.instance.getBirdById(child['id'].toString());
    if (!mounted || bird == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: bird)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final current = _offspring
        .where((child) => child['currentStatus']?.toString() == 'Present')
        .toList();
    int countAge(String age) =>
        current.where((child) => _ageGroup(child) == age).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_pair?['identifier'] ?? 'Pair'} Offspring',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'current',
                          label: Text('Current Offspring'),
                        ),
                        ButtonSegment(
                          value: 'all',
                          label: Text('All Offspring'),
                        ),
                      ],
                      selected: {_view},
                      onSelectionChanged: (selection) {
                        setState(() => _view = selection.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _countChip('Present', current.length),
                      _countChip('Chick', countAge('Chick')),
                      _countChip('Young', countAge('Young')),
                      _countChip('Adult', countAge('Adult')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_visible.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          _view == 'current'
                              ? 'No offspring from this pair are currently in the aviary.'
                              : 'No offspring have been linked to this pair yet.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._visible.map((child) {
                      final ring =
                          child['ringNumber']?.toString() ?? 'No ring';
                      final name = child['name']?.toString().trim() ?? '';
                      final status =
                          child['currentStatus']?.toString() ?? 'Removed';
                      final age = _ageGroup(child);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          color: aviaryCardSurface(context, tint: _tint(child)),
                          child: ListTile(
                            leading: const AviaryIcon(AviaryIconType.bird),
                            title: Text(
                              name.isEmpty ? ring : '$ring — $name',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: birdGenderTextColor(
                                  child['gender']?.toString(),
                                ),
                              ),
                            ),
                            subtitle: Text(
                              '$status · $age\n'
                              '${child['cageIdentifier'] ?? 'No current cage'} · '
                              'Hatched ${_formatDate(child['hatchDate'])}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openBird(child),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
