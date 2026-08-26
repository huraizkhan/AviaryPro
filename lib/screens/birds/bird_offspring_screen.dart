import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import 'bird_details_screen.dart';

class BirdOffspringScreen extends StatefulWidget {
  const BirdOffspringScreen({
    super.key,
    required this.birdId,
    required this.birdLabel,
    this.birdGender,
  });

  final String birdId;
  final String birdLabel;
  final String? birdGender;

  @override
  State<BirdOffspringScreen> createState() => _BirdOffspringScreenState();
}

class _BirdOffspringScreenState extends State<BirdOffspringScreen> {
  final _dateFormat = DateFormat('dd-MMM-yy');
  List<Map<String, dynamic>> _offspring = const [];
  bool _loading = true;
  String _view = 'present';
  String? _spouseId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getOffspringForBird(widget.birdId);
    if (!mounted) return;
    setState(() {
      _offspring = rows;
      _loading = false;
      if (_spouseId != null &&
          !_offspring.any((row) => row['spouseBirdId']?.toString() == _spouseId)) {
        _spouseId = null;
      }
    });
  }

  DateTime? _effectiveBirthDate(Map<String, dynamic> bird) {
    final hatch = DateTime.tryParse(bird['hatchDate']?.toString() ?? '');
    if (hatch != null) return hatch;
    final sourceDate = DateTime.tryParse(bird['sourceDate']?.toString() ?? '');
    final estimated = (bird['estimatedAgeDays'] as num?)?.toInt();
    if (sourceDate == null || estimated == null) return null;
    return sourceDate.subtract(Duration(days: estimated));
  }

  int _completedMonths(DateTime birth) {
    final today = DateTime.now();
    var months = (today.year - birth.year) * 12 + today.month - birth.month;
    if (today.day < birth.day) months--;
    return months < 0 ? 0 : months;
  }

  String _age(Map<String, dynamic> bird) {
    final birth = _effectiveBirthDate(bird);
    if (birth == null) return bird['ageGroup']?.toString() ?? 'Unknown';
    final months = _completedMonths(birth);
    final days = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ).difference(DateTime(birth.year, birth.month, birth.day)).inDays;
    final adultAt = (bird['adultAgeMonths'] as num?)?.toInt();
    final youngAt = (bird['chickToYoungDays'] as num?)?.toInt();
    final group = adultAt != null && months >= adultAt
        ? 'Adult'
        : youngAt != null && days >= youngAt
            ? 'Young'
            : 'Chick';
    if (months >= 12) {
      final years = months ~/ 12;
      final rest = months % 12;
      return '$years year${years == 1 ? '' : 's'}'
          '${rest == 0 ? '' : ' $rest month${rest == 1 ? '' : 's'}'} ($group)';
    }
    return '$months month${months == 1 ? '' : 's'} ($group)';
  }

  List<Map<String, dynamic>> get _visible {
    return _offspring.where((row) {
      final present = row['currentStatus']?.toString() == 'Present';
      if (_view == 'present' && !present) return false;
      if (_view == 'removed' && present) return false;
      if (_spouseId != null && row['spouseBirdId']?.toString() != _spouseId) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Map<String, String>> get _spouses {
    final seen = <String>{};
    final result = <Map<String, String>>[];
    for (final row in _offspring) {
      final id = row['spouseBirdId']?.toString();
      if (id == null || id.isEmpty || !seen.add(id)) continue;
      final ring = row['spouseRingNumber']?.toString() ?? 'Bird';
      final name = row['spouseName']?.toString().trim() ?? '';
      result.add({
        'id': id,
        'label': name.isEmpty ? ring : '$ring — $name',
        'gender': row['spouseGender']?.toString() ?? 'Unknown',
      });
    }
    return result;
  }

  Future<void> _openBird(Map<String, dynamic> row) async {
    final bird = await DatabaseHelper.instance.getBirdById(row['id'].toString());
    if (!mounted || bird == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: bird)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final present = _offspring.where((row) => row['currentStatus'] == 'Present').length;
    final removed = _offspring.length - present;
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: widget.birdLabel,
                style: TextStyle(
                  color: birdGenderTextColor(widget.birdGender),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const TextSpan(text: ' Offspring'),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                children: [
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'present',
                        label: Text('Present ($present)'),
                      ),
                      ButtonSegment(
                        value: 'removed',
                        label: Text('Removed ($removed)'),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (selection) {
                      setState(() => _view = selection.first);
                    },
                  ),
                  if (_spouses.length > 1) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: _spouseId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Spouse',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All spouses'),
                        ),
                        ..._spouses.map(
                          (spouse) => DropdownMenuItem<String?>(
                            value: spouse['id'],
                            child: Text(
                              spouse['label']!,
                              style: TextStyle(
                                color: birdGenderTextColor(spouse['gender']),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _spouseId = value),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_visible.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No offspring match this view.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._visible.map((child) {
                      final ring = child['ringNumber']?.toString() ?? 'No ring';
                      final name = child['name']?.toString().trim() ?? '';
                      final status = child['currentStatus']?.toString() ?? 'Removed';
                      final spouseRing = child['spouseRingNumber']?.toString() ?? 'Bird';
                      final spouseName = child['spouseName']?.toString().trim() ?? '';
                      final spouse = spouseName.isEmpty
                          ? spouseRing
                          : '$spouseRing — $spouseName';
                      final hatch = DateTime.tryParse(child['hatchDate']?.toString() ?? '');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          color: status == 'Present'
                              ? AviaryColors.birds.withValues(alpha: .10)
                              : Colors.grey.withValues(alpha: .10),
                          child: ListTile(
                            leading: const AviaryIcon(AviaryIconType.bird),
                            title: Text(
                              name.isEmpty ? ring : '$ring — $name',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: birdGenderTextColor(
                                  child['gender']?.toString(),
                                ),
                              ),
                            ),
                            subtitle: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                children: [
                                  TextSpan(text: '$status · ${_age(child)}\nWith '),
                                  TextSpan(
                                    text: spouse,
                                    style: TextStyle(
                                      color: birdGenderTextColor(
                                        child['spouseGender']?.toString(),
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (hatch != null)
                                    TextSpan(
                                      text: ' · ${_dateFormat.format(hatch)}',
                                    ),
                                ],
                              ),
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
