import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';

class BirdHistorySummaryScreen extends StatefulWidget {
  const BirdHistorySummaryScreen({
    super.key,
    required this.birdId,
    required this.birdLabel,
    this.birdGender,
  });

  final String birdId;
  final String birdLabel;
  final String? birdGender;

  @override
  State<BirdHistorySummaryScreen> createState() =>
      _BirdHistorySummaryScreenState();
}

class _BirdHistorySummaryScreenState
    extends State<BirdHistorySummaryScreen> {
  Map<String, int> _summary = const {};
  List<Map<String, dynamic>> _events = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getBirdRelationSummary(widget.birdId),
      DatabaseHelper.instance.getBirdEvents(widget.birdId),
    ]);
    if (!mounted) return;
    setState(() {
      _summary = results[0] as Map<String, int>;
      _events = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Widget _count(String label, int value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 6),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              const TextSpan(text: ' History'),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                children: [
                  Row(
                    children: [
                      _count(
                        'Cage changes',
                        _summary['cageChanges'] ?? 0,
                        Icons.swap_horiz,
                      ),
                      _count(
                        'Spouses',
                        _summary['spouses'] ?? 0,
                        Icons.favorite_outline,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _count(
                        'Clutches',
                        _summary['clutches'] ?? 0,
                        Icons.egg_outlined,
                      ),
                      _count(
                        'Offspring born',
                        _summary['offspring'] ?? 0,
                        Icons.child_care,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Record History',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (_events.isEmpty)
                    const Card(
                      child: ListTile(title: Text('No history events recorded.')),
                    )
                  else
                    ..._events.map((event) {
                      final parsed = DateTime.tryParse(event['eventDate']?.toString() ?? '');
                      final date = parsed == null
                          ? ''
                          : DateFormat('dd-MMM-yy').format(parsed);
                      final details = event['details']?.toString().trim() ?? '';
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(
                            event['eventType']?.toString() ?? 'History',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [date, if (details.isNotEmpty) details].join(' · '),
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
