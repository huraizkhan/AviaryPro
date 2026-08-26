import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import 'clutch_details_screen.dart';

class CompletedClutchesScreen extends StatefulWidget {
  const CompletedClutchesScreen({
    super.key,
    required this.pairId,
  });

  final String pairId;

  @override
  State<CompletedClutchesScreen> createState() =>
      _CompletedClutchesScreenState();
}

class _CompletedClutchesScreenState extends State<CompletedClutchesScreen> {
  final _dateFormat = DateFormat('dd-MMM-yy');
  Map<String, dynamic>? _pair;
  List<Map<String, dynamic>> _clutches = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getBreedingPairById(widget.pairId),
      DatabaseHelper.instance.getClutchesForPair(widget.pairId),
    ]);
    if (!mounted) return;
    final all = results[1] as List<Map<String, dynamic>>;
    setState(() {
      _pair = results[0] as Map<String, dynamic>?;
      _clutches = all
          .where((clutch) => clutch['status']?.toString() != 'Active')
          .toList();
      _loading = false;
    });
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? 'Not set' : _dateFormat.format(date);
  }

  Future<void> _openClutch(Map<String, dynamic> clutch) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClutchDetailsScreen(clutchId: clutch['id'].toString()),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_pair?['identifier'] ?? 'Pair'} Completed Clutches'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                children: [
                  if (_clutches.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'No completed clutch yet.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._clutches.map((clutch) {
                      final eggs =
                          (clutch['totalEggs'] as num?)?.toInt() ?? 0;
                      final hatched =
                          (clutch['hatchedEggs'] as num?)?.toInt() ?? 0;
                      final chicks =
                          (clutch['chicksInNest'] as num?)?.toInt() ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 8,
                            ),
                            leading: const CircleAvatar(
                              child: AviaryIcon(AviaryIconType.egg),
                            ),
                            title: Text(
                              'Clutch ${clutch['clutchNumber'] ?? '?'}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '$eggs eggs · $hatched hatched · $chicks chicks\n'
                              'First egg: ${_formatDate(clutch['firstEggDate'])}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openClutch(clutch),
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
