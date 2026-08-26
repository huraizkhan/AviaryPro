import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../cages/create_pair_screen.dart';

class SelectCageForPairScreen extends StatefulWidget {
  const SelectCageForPairScreen({super.key});

  @override
  State<SelectCageForPairScreen> createState() =>
      _SelectCageForPairScreenState();
}

class _SelectCageForPairScreenState extends State<SelectCageForPairScreen> {
  List<Map<String, dynamic>> cages = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCages();
  }

  Future<void> _loadCages() async {
    try {
      final cageRows = await DatabaseHelper.instance.getCages();
      final enriched = <Map<String, dynamic>>[];
      for (final cage in cageRows) {
        final available = await DatabaseHelper.instance
            .getAvailableBirdsForPair(cage['id'].toString());
        final maleCount = available.where((bird) {
          return bird['gender']?.toString().toLowerCase() == 'male';
        }).length;
        final femaleCount = available.where((bird) {
          return bird['gender']?.toString().toLowerCase() == 'female';
        }).length;
        enriched.add({
          ...cage,
          'maleCount': maleCount,
          'femaleCount': femaleCount,
        });
      }
      if (!mounted) return;
      setState(() {
        cages = enriched;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cages could not be loaded')),
      );
    }
  }

  Future<void> _openCage(Map<String, dynamic> cage) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePairScreen(cageId: cage['id'].toString()),
      ),
    );
    if (!mounted) return;
    if (result == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Cage')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : cages.isEmpty
              ? const Center(child: Text('No cages added yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: cages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final cage = cages[index];
                    final maleCount = cage['maleCount'] as int;
                    final femaleCount = cage['femaleCount'] as int;
                    final canCreate = maleCount > 0 && femaleCount > 0;
                    return Card(
                      color: canCreate
                          ? AviaryColors.cages.withValues(alpha: .10)
                          : Theme.of(context).disabledColor.withValues(alpha: .06),
                      child: ListTile(
                        enabled: canCreate,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Colors.white.withValues(alpha: .78),
                          child: const AviaryIcon(
                            AviaryIconType.cage,
                            color: AviaryColors.cages,
                          ),
                        ),
                        title: Text(
                          cage['identifier']?.toString() ?? 'Cage',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '$maleCount available males · $femaleCount available females',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: canCreate ? () => _openCage(cage) : null,
                      ),
                    );
                  },
                ),
    );
  }
}
