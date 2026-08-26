import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../breeding/pair_details_screen.dart';

class DashboardEggPairsScreen extends StatefulWidget {
  const DashboardEggPairsScreen({super.key});

  @override
  State<DashboardEggPairsScreen> createState() => _DashboardEggPairsScreenState();
}

class _DashboardEggPairsScreenState extends State<DashboardEggPairsScreen> {
  List<Map<String, dynamic>> _pairs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getPairsWithIncubatingEggs();
    if (!mounted) return;
    setState(() {
      _pairs = rows;
      _loading = false;
    });
  }

  String _birdLabel(Map<String, dynamic> pair, String prefix) {
    final ring = pair['${prefix}RingNumber']?.toString().trim() ?? '';
    final name = pair['${prefix}Name']?.toString().trim() ?? '';
    if (ring.isEmpty) return name.isEmpty ? 'No ring' : name;
    return name.isEmpty ? ring : '$ring — $name';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pairs With Eggs')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _pairs.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 180),
                        Center(child: Text('No pairs have eggs to incubate.')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                      itemCount: _pairs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final pair = _pairs[index];
                        final eggs = (pair['activeEggCount'] as num?)?.toInt() ?? 0;
                        final cage = pair['cageIdentifier']?.toString() ?? 'No cage';
                        final id = pair['identifier']?.toString() ?? 'Pair';
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: AviaryIcon(AviaryIconType.egg),
                            ),
                            title: Text(
                              '$cage — $id',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: _birdLabel(pair, 'male'),
                                    style: TextStyle(
                                      color: birdGenderTextColor('Male'),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const TextSpan(text: '  ×  '),
                                  TextSpan(
                                    text: _birdLabel(pair, 'female'),
                                    style: TextStyle(
                                      color: birdGenderTextColor('Female'),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(text: '\n$eggs egg${eggs == 1 ? '' : 's'} incubating'),
                                ],
                              ),
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PairDetailsScreen(
                                    pairId: pair['id'].toString(),
                                  ),
                                ),
                              );
                              if (mounted) await _load();
                            },
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
