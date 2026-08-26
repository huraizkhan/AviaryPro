import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../birds/bird_details_screen.dart';

class RingManagementScreen extends StatefulWidget {
  const RingManagementScreen({super.key});

  @override
  State<RingManagementScreen> createState() => _RingManagementScreenState();
}

class _RingManagementScreenState extends State<RingManagementScreen> {
  List<Map<String, dynamic>> _species = const [];
  List<Map<String, dynamic>> _ranges = const [];
  List<Map<String, dynamic>> _rings = const [];
  String? _speciesId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final species = await DatabaseHelper.instance.getSpecies();
    final selected = _speciesId ?? (species.isEmpty ? null : species.first['id'].toString());
    final ranges = selected == null
        ? <Map<String, dynamic>>[]
        : await DatabaseHelper.instance.getRingRanges(speciesId: selected);
    final rings = selected == null
        ? <Map<String, dynamic>>[]
        : await DatabaseHelper.instance.getRingAssignments(selected);
    if (!mounted) return;
    setState(() {
      _species = species;
      _speciesId = selected;
      _ranges = ranges;
      _rings = rings;
      _loading = false;
    });
  }

  Future<void> _selectSpecies(String? value) async {
    if (value == null || value == _speciesId) return;
    setState(() {
      _speciesId = value;
      _loading = true;
    });
    await _load();
  }

  Future<void> _addRange() async {
    if (_speciesId == null) return;
    final start = TextEditingController();
    final end = TextEditingController();
    final padding = TextEditingController(text: '3');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Ring Range'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: start,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Start number', hintText: '1'),
            ),
            TextField(
              controller: end,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'End number', hintText: '100'),
            ),
            TextField(
              controller: padding,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Digits',
                helperText: '3 makes 1 display as 001',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Add')),
        ],
      ),
    );
    if (confirmed != true) {
      start.dispose();
      end.dispose();
      padding.dispose();
      return;
    }
    try {
      await DatabaseHelper.instance.addRingRange(
        speciesId: _speciesId!,
        startNumber: int.parse(start.text.trim()),
        endNumber: int.parse(end.text.trim()),
        padding: int.tryParse(padding.text.trim()) ?? 3,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    } finally {
      start.dispose();
      end.dispose();
      padding.dispose();
    }
  }

  Future<void> _deleteRange(Map<String, dynamic> range) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete ring range?'),
        content: const Text('Existing bird rings will stay assigned. Only this allowed range will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseHelper.instance.deleteRingRange(range['id'].toString());
    await _load();
  }

  Future<void> _openBird(Map<String, dynamic> ring) async {
    final id = ring['birdId']?.toString();
    if (id == null || id.isEmpty) return;
    final bird = await DatabaseHelper.instance.getBirdById(id);
    if (!mounted || bird == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: bird)),
    );
    if (mounted) await _load();
  }

  Color _ringColor(Map<String, dynamic> ring) {
    if ((ring['allotted'] as num?)?.toInt() != 1) return Colors.grey;
    return birdGenderTextColor(ring['gender']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ring Management'),
        actions: [
          IconButton(onPressed: _speciesId == null ? null : _addRange, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 36),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _speciesId,
                  decoration: const InputDecoration(labelText: 'Species', border: OutlineInputBorder()),
                  items: _species
                      .map((row) => DropdownMenuItem<String>(
                            value: row['id'].toString(),
                            child: Text(row['name'].toString()),
                          ))
                      .toList(),
                  onChanged: _selectSpecies,
                ),
                const SizedBox(height: 12),
                if (_ranges.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('No ring range configured'),
                      subtitle: Text('Add a range such as 001–100 for this species.'),
                    ),
                  )
                else ...[
                  const Text('Allowed ranges', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  ..._ranges.map((range) {
                    final digits = (range['padding'] as num?)?.toInt() ?? 3;
                    final start = (range['startNumber'] as num).toInt().toString().padLeft(digits, '0');
                    final end = (range['endNumber'] as num).toInt().toString().padLeft(digits, '0');
                    return Card(
                      child: ListTile(
                        title: Text('$start – $end', style: const TextStyle(fontWeight: FontWeight.w800)),
                        trailing: IconButton(
                          tooltip: 'Delete range',
                          onPressed: () => _deleteRange(range),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  const Text('Rings', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: _rings.map((ring) {
                      final allotted = (ring['allotted'] as num?)?.toInt() == 1;
                      final color = _ringColor(ring);
                      return ActionChip(
                        onPressed: allotted ? () => _openBird(ring) : null,
                        avatar: Icon(allotted ? Icons.person : Icons.circle_outlined, size: 16, color: color),
                        label: Text(
                          '${ring['ringNumber']} · ${allotted ? 'Allotted' : 'Available'}',
                          style: TextStyle(color: color, fontWeight: FontWeight.w800),
                        ),
                        tooltip: allotted ? 'Allotted' : 'Available',
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  const Text('Blue = Male · Pink = Female · Neutral = Unknown · Grey = Available'),
                ],
              ],
            ),
    );
  }
}
