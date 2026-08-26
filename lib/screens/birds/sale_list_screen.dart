import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import 'bird_details_screen.dart';

class SaleListScreen extends StatefulWidget {
  const SaleListScreen({super.key});

  @override
  State<SaleListScreen> createState() => _SaleListScreenState();
}

class _SaleListScreenState extends State<SaleListScreen> {
  List<Map<String, dynamic>> _birds = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getSaleListBirds();
    if (!mounted) return;
    setState(() {
      _birds = rows;
      _loading = false;
    });
  }

  String _label(Map<String, dynamic> bird) {
    final ring = bird['ringNumber']?.toString().trim() ?? '';
    final name = bird['name']?.toString().trim() ?? '';
    if (ring.isEmpty) return name.isEmpty ? 'No ring' : name;
    return name.isEmpty ? ring : '$ring — $name';
  }

  Future<void> _remove(Map<String, dynamic> bird) async {
    await DatabaseHelper.instance.updateBirdSaleStatus(
      birdId: bird['id'].toString(),
      status: 'Not for Sale',
    );
    if (mounted) await _load();
  }

  Future<void> _addBirds() async {
    final all = await DatabaseHelper.instance.getBirds();
    if (!mounted) return;
    final candidates = all.where((bird) {
      return bird['active'] != 0 &&
          bird['pairId'] == null &&
          (bird['saleStatus']?.toString() ?? 'Not for Sale') == 'Not for Sale';
    }).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No birds available to add to the sale list.')),
      );
      return;
    }

    final selected = <String>{};
    final add = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * .78,
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    'Add Birds to Sale List',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final bird = candidates[index];
                      final id = bird['id'].toString();
                      return CheckboxListTile(
                        value: selected.contains(id),
                        onChanged: (value) => setSheetState(() {
                          if (value == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        }),
                        title: Text(
                          _label(bird),
                          style: TextStyle(
                            color: birdGenderTextColor(bird['gender']?.toString()),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${bird['speciesName'] ?? ''}${bird['ageGroup'] == null ? '' : ' · ${bird['ageGroup']}'}',
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(sheetContext, true),
                      child: Text('ADD ${selected.length}'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || add != true) return;
    for (final id in selected) {
      await DatabaseHelper.instance.updateBirdSaleStatus(
        birdId: id,
        status: 'Available',
      );
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('For Sale'),
        actions: [
          IconButton(
            tooltip: 'Add birds to sale list',
            onPressed: _addBirds,
            icon: const Icon(Icons.playlist_add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _birds.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 180),
                        Center(child: Text('No birds are currently for sale.')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                      itemCount: _birds.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final bird = _birds[index];
                        return Card(
                          child: ListTile(
                            onTap: () async {
                              final fresh = await DatabaseHelper.instance
                                  .getBirdById(bird['id'].toString());
                              if (!mounted || fresh == null) return;
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BirdDetailsScreen(bird: fresh),
                                ),
                              );
                              if (mounted) await _load();
                            },
                            title: Text(
                              _label(bird),
                              style: TextStyle(
                                color: birdGenderTextColor(bird['gender']?.toString()),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${bird['ageGroup'] ?? 'Unknown'} · ${bird['saleStatus'] ?? 'Available'}'
                              '${bird['cageIdentifier'] == null ? '' : ' · ${bird['cageIdentifier']}'}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Mark Not for Sale',
                              onPressed: () => _remove(bird),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBirds,
        icon: const Icon(Icons.add),
        label: const Text('Add Birds'),
      ),
    );
  }
}
