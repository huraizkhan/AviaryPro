import 'package:flutter/material.dart';

import '../../database/database_helper.dart';

class ManagedBirdValuesScreen extends StatefulWidget {
  const ManagedBirdValuesScreen({
    super.key,
    required this.kind,
  });

  final String kind;

  @override
  State<ManagedBirdValuesScreen> createState() => _ManagedBirdValuesScreenState();
}

class _ManagedBirdValuesScreenState extends State<ManagedBirdValuesScreen> {
  List<Map<String, dynamic>> _species = const [];
  List<Map<String, dynamic>> _values = const [];
  String? _speciesId;
  bool _loading = true;

  bool get _speciesSpecific => widget.kind == 'Mutation';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final species = await DatabaseHelper.instance.getSpecies();
    final selected = _speciesSpecific
        ? (_speciesId ?? (species.isEmpty ? null : species.first['id'].toString()))
        : null;
    final values = await DatabaseHelper.instance.getManagedBirdValues(
      kind: widget.kind,
      speciesId: selected,
    );
    if (!mounted) return;
    setState(() {
      _species = species;
      _speciesId = selected;
      _values = values.where((row) {
        if (!_speciesSpecific) return row['speciesId'] == null;
        return row['speciesId']?.toString() == selected;
      }).toList();
      _loading = false;
    });
  }

  Future<void> _add() async {
    if (_speciesSpecific && _speciesId == null) return;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add ${widget.kind}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: widget.kind),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Add')),
        ],
      ),
    );
    final value = controller.text.trim();
    controller.dispose();
    if (confirmed != true || value.isEmpty) return;
    try {
      await DatabaseHelper.instance.addManagedBirdValue(
        kind: widget.kind,
        value: value,
        speciesId: _speciesSpecific ? _speciesId : null,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    await DatabaseHelper.instance.deleteManagedBirdValue(row['id'].toString());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.kind} Management'),
        actions: [IconButton(onPressed: _add, icon: const Icon(Icons.add))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                if (_speciesSpecific) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _speciesId,
                    decoration: const InputDecoration(labelText: 'Species', border: OutlineInputBorder()),
                    items: _species
                        .map((row) => DropdownMenuItem<String>(
                              value: row['id'].toString(),
                              child: Text(row['name'].toString()),
                            ))
                        .toList(),
                    onChanged: (value) async {
                      if (value == null) return;
                      setState(() {
                        _speciesId = value;
                        _loading = true;
                      });
                      await _load();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (_values.isEmpty)
                  Card(
                    child: ListTile(
                      title: Text('No ${widget.kind.toLowerCase()} values yet'),
                      subtitle: const Text('Tap + to add one.'),
                    ),
                  )
                else
                  ..._values.map(
                    (row) => Card(
                      child: ListTile(
                        title: Text(row['value'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                        trailing: IconButton(
                          onPressed: () => _delete(row),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
