import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../../ui/list_grid_toggle.dart';
import 'cage_details_screen.dart';

class CagesScreen extends StatefulWidget {
  const CagesScreen({super.key});

  @override
  State<CagesScreen> createState() => _CagesScreenState();
}

class _CagesScreenState extends State<CagesScreen> {
  Future<List<Map<String, dynamic>>>? cages;
  bool gridView = false;

  @override
  void initState() {
    super.initState();
    _refreshCages();
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('cages_grid_view') ?? false;
    if (!mounted) return;
    setState(() => gridView = saved);
  }

  Future<void> _setGridView(bool value) async {
    setState(() => gridView = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cages_grid_view', value);
  }

  void _refreshCages() {
    setState(() {
      cages = DatabaseHelper.instance.getCages();
    });
  }

  int _naturalCompare(String left, String right) {
    final pattern = RegExp(r'(\d+|\D+)');
    final a = pattern
        .allMatches(left.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    final b = pattern
        .allMatches(right.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    final length = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final an = int.tryParse(a[i]);
      final bn = int.tryParse(b[i]);
      final result = an != null && bn != null
          ? an.compareTo(bn)
          : a[i].compareTo(b[i]);
      if (result != 0) return result;
    }
    return a.length.compareTo(b.length);
  }

  Future<void> _openCage(Map<String, dynamic> cage) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CageDetailsScreen(cageId: cage['id'].toString()),
      ),
    );
    if (mounted) _refreshCages();
  }

  Widget _cageCard(Map<String, dynamic> cage, {required bool compact}) {
    final isSeries = cage['identityMode'] == 'series';
    final physicalName = isSeries ? cage['physicalName']?.toString() ?? '' : '';
    final birdCount = (cage['birdCount'] as num?)?.toInt() ?? 0;
    final mergedCount = (cage['mergedCount'] as num?)?.toInt() ?? 0;
    final details = [
      if (physicalName.isNotEmpty) physicalName,
      cage['type']?.toString() ?? '',
      if ((cage['location']?.toString() ?? '').isNotEmpty)
        cage['location'].toString(),
      '$birdCount bird${birdCount == 1 ? '' : 's'}',
    ].where((value) => value.trim().isNotEmpty).join(' · ');

    final cardColor = mergedCount > 0
        ? AviaryColors.hatchFiveDays.withValues(alpha: .35)
        : null;

    if (!compact) {
      return Card(
        color: cardColor,
        child: ListTile(
          onTap: () => _openCage(cage),
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
          subtitle: Text(details),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
    }

    return Card(
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openCage(cage),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 19,
                    child: AviaryIcon(AviaryIconType.cage, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cage['identifier']?.toString() ?? 'Cage',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                details,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (mergedCount > 0) ...[
                const SizedBox(height: 6),
                const Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('Merged'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
          final cageList = [...?snapshot.data]
            ..sort((a, b) => _naturalCompare(
                  a['identifier']?.toString() ?? '',
                  b['identifier']?.toString() ?? '',
                ));
          if (cageList.isEmpty) {
            return const Center(
              child: Text(
                'No cages added yet',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AviaryListGridToggle(
                    gridView: gridView,
                    onChanged: _setGridView,
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _refreshCages();
                    await cages;
                  },
                  child: gridView
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 800
                                ? 3
                                : constraints.maxWidth < 360
                                    ? 1
                                    : 2;
                            return GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                12,
                                8,
                                12,
                                24 + MediaQuery.paddingOf(context).bottom,
                              ),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                mainAxisExtent: 150,
                              ),
                              itemCount: cageList.length,
                              itemBuilder: (context, index) =>
                                  _cageCard(cageList[index], compact: true),
                            );
                          },
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            12,
                            8,
                            12,
                            24 + MediaQuery.paddingOf(context).bottom,
                          ),
                          itemCount: cageList.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _cageCard(cageList[index], compact: false),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
