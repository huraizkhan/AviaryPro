import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import 'cage_details_screen.dart';

class CagesScreen extends StatefulWidget {
  const CagesScreen({super.key});

  @override
  State<CagesScreen> createState() => _CagesScreenState();
}

class _CagesScreenState extends State<CagesScreen> {
  Future<List<Map<String, dynamic>>>? cages;

  @override
  void initState() {
    super.initState();
    _refreshCages();
  }

  void _refreshCages() {
    setState(() {
      cages = DatabaseHelper.instance.getCages();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cages')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: cages,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load cages: ${snapshot.error}'));
          }
          final cageList = snapshot.data ?? const <Map<String, dynamic>>[];
          if (cageList.isEmpty) {
            return const Center(
              child: Text(
                'No cages added yet',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              _refreshCages();
              await cages;
            },
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: cageList.length,
              itemBuilder: (context, index) {
                final cage = cageList[index];
                final isSeries = cage['identityMode'] == 'series';
                final physicalName = isSeries
                    ? cage['physicalName']?.toString() ?? ''
                    : '';
                final birdCount = (cage['birdCount'] as num?)?.toInt() ?? 0;
                final mergedCount = (cage['mergedCount'] as num?)?.toInt() ?? 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    color: mergedCount > 0
                        ? AviaryColors.hatchFiveDays.withValues(alpha: .35)
                        : null,
                    child: ListTile(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CageDetailsScreen(
                              cageId: cage['id'].toString(),
                            ),
                          ),
                        );
                        if (mounted) _refreshCages();
                      },
                      leading: const CircleAvatar(
                        child: AviaryIcon(AviaryIconType.cage),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              cage['identifier']?.toString() ?? 'Cage',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (mergedCount > 0)
                            const Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text('Merged'),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        [
                          if (physicalName.isNotEmpty) physicalName,
                          cage['type']?.toString() ?? '',
                          if ((cage['location']?.toString() ?? '').isNotEmpty)
                            cage['location'].toString(),
                          '$birdCount bird${birdCount == 1 ? '' : 's'}',
                        ].where((value) => value.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
