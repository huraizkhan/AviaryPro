import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../birds/bird_details_screen.dart';

class PreviousBirdsScreen extends StatefulWidget {
  const PreviousBirdsScreen({super.key});

  @override
  State<PreviousBirdsScreen> createState() => _PreviousBirdsScreenState();
}

class _PreviousBirdsScreenState extends State<PreviousBirdsScreen> {
  List<Map<String, dynamic>> _birds = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final birds = await DatabaseHelper.instance.getBirds();
    if (!mounted) return;
    setState(() {
      _birds = birds.where((bird) => bird['active'] == 0).toList()
        ..sort((a, b) {
          final aDate = DateTime.tryParse(a['removedAt']?.toString() ?? '');
          final bDate = DateTime.tryParse(b['removedAt']?.toString() ?? '');
          return (bDate ?? DateTime(1900)).compareTo(aDate ?? DateTime(1900));
        });
      _loading = false;
    });
  }

  Future<void> _open(Map<String, dynamic> bird) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: bird)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Previous Birds (${_birds.length})')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _birds.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 180),
                        Center(child: Text('No previous birds.')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                      itemCount: _birds.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final bird = _birds[index];
                        final ring = bird['ringNumber']?.toString().trim() ?? '';
                        final name = bird['name']?.toString().trim() ?? '';
                        final gender = bird['gender']?.toString() ?? 'Unknown';
                        final reason = bird['removalReason']?.toString().trim() ??
                            bird['saleStatus']?.toString().trim() ??
                            'Removed';
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: AviaryIcon(AviaryIconType.bird),
                            ),
                            title: Text(
                              name.isEmpty
                                  ? (ring.isEmpty ? 'No ring' : ring)
                                  : '${ring.isEmpty ? 'No ring' : ring} — $name',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: birdGenderTextColor(gender),
                              ),
                            ),
                            subtitle: Text(
                              '${bird['speciesName'] ?? ''} · $reason${ring.isEmpty ? ' · Ring removed' : ''}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(bird),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
