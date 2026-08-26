import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import 'add_egg_screen.dart';

class SelectActiveClutchScreen extends StatefulWidget {
  const SelectActiveClutchScreen({super.key});

  @override
  State<SelectActiveClutchScreen> createState() =>
      _SelectActiveClutchScreenState();
}

class _SelectActiveClutchScreenState extends State<SelectActiveClutchScreen> {
  List<Map<String, dynamic>> pairs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final rows = await DatabaseHelper.instance.getBreedingPairs(
      activeOnly: true,
    );
    if (!mounted) return;
    setState(() {
      pairs = rows;
      isLoading = false;
    });
  }

  String _bird(Map<String, dynamic> pair, String prefix) {
    final ring = pair['${prefix}RingNumber']?.toString() ?? 'No ring';
    final name = pair['${prefix}Name']?.toString().trim() ?? '';
    return name.isEmpty ? ring : '$ring ($name)';
  }

  Future<void> _open(Map<String, dynamic> pair) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEggScreen(
          clutchId: pair['activeClutchId'].toString(),
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Active Clutch')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : pairs.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No active clutch exists. Start a clutch from a pair first.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: pairs.length,
                  itemBuilder: (context, index) {
                    final pair = pairs[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.egg)),
                        title: Text(
                          '${pair['cageIdentifier'] ?? 'No cage'}  →  '
                          '${pair['identifier'] ?? 'Pair'}',
                        ),
                        subtitle: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: _bird(pair, 'male'),
                                style: TextStyle(
                                  color: birdGenderTextColor(
                                    pair['maleGender']?.toString(),
                                  ),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const TextSpan(text: ' × '),
                              TextSpan(
                                text: _bird(pair, 'female'),
                                style: TextStyle(
                                  color: birdGenderTextColor(
                                    pair['femaleGender']?.toString(),
                                  ),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(pair),
                      ),
                    );
                  },
                ),
    );
  }
}
