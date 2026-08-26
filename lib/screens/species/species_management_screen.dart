import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';

class SpeciesManagementScreen extends StatefulWidget {
  const SpeciesManagementScreen({super.key});

  @override
  State<SpeciesManagementScreen> createState() =>
      _SpeciesManagementScreenState();
}

class _SpeciesManagementScreenState extends State<SpeciesManagementScreen> {
  List<Map<String, dynamic>> species = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getAllSpecies();
    if (!mounted) return;
    setState(() {
      species = rows;
      loading = false;
    });
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SpeciesEditScreen(species: item),
      ),
    );
    if (!mounted || changed != true) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Species Management')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AviaryColors.breeding.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'These values calculate bird stages, clutch grouping and expected hatch dates automatically.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...species.map((item) {
                    final active = item['active'] != 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: ListTile(
                          onTap: () => _edit(item),
                          leading: CircleAvatar(
                            backgroundColor:
                                AviaryColors.breeding.withValues(alpha: .14),
                            child: AviaryIcon(
                              AviaryIconType.bird,
                              color: AviaryColors.breeding,
                            ),
                          ),
                          title: Text(item['name']?.toString() ?? 'Species'),
                          subtitle: Text(
                            'Chick → Young: ${item['chickToYoungDays'] ?? '-'} days\n'
                            'Young → Adult: ${item['adultAgeMonths'] ?? '-'} months · '
                            'Hatch: ${item['incubationDays'] ?? '-'} days · '
                            'Clutch: ${item['clutchWindowDays'] ?? 15} days',
                          ),
                          isThreeLine: true,
                          trailing: Switch(
                            value: active,
                            onChanged: (value) async {
                              await DatabaseHelper.instance.setSpeciesActive(
                                item['id'].toString(),
                                value,
                              );
                              await _load();
                            },
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('Species'),
      ),
    );
  }
}

class SpeciesEditScreen extends StatefulWidget {
  final Map<String, dynamic>? species;

  const SpeciesEditScreen({
    super.key,
    this.species,
  });

  @override
  State<SpeciesEditScreen> createState() => _SpeciesEditScreenState();
}

class _SpeciesEditScreenState extends State<SpeciesEditScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController youngController;
  late final TextEditingController adultController;
  late final TextEditingController incubationController;
  late final TextEditingController clutchWindowController;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.species;
    nameController = TextEditingController(text: item?['name']?.toString());
    youngController = TextEditingController(
      text: item?['chickToYoungDays']?.toString() ?? '',
    );
    adultController = TextEditingController(
      text: item?['adultAgeMonths']?.toString() ?? '',
    );
    incubationController = TextEditingController(
      text: item?['incubationDays']?.toString() ?? '',
    );
    clutchWindowController = TextEditingController(
      text: item?['clutchWindowDays']?.toString() ?? '15',
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    youngController.dispose();
    adultController.dispose();
    incubationController.dispose();
    clutchWindowController.dispose();
    super.dispose();
  }

  int? _int(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : int.tryParse(trimmed);
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate() || saving) return;
    setState(() => saving = true);

    final values = {
      'name': nameController.text.trim(),
      'chickToYoungDays': _int(youngController.text),
      'adultAgeMonths': _int(adultController.text),
      'incubationDays': _int(incubationController.text),
      'clutchWindowDays': _int(clutchWindowController.text) ?? 15,
      'active': widget.species?['active'] ?? 1,
    };

    try {
      if (widget.species == null) {
        await DatabaseHelper.instance.insertSpecies({
          'id': const Uuid().v4(),
          ...values,
        });
      } else {
        await DatabaseHelper.instance.updateSpecies(
          widget.species!['id'].toString(),
          values,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save species: $error')),
      );
    }
  }

  Future<void> _deleteSpecies() async {
    final item = widget.species;
    if (item == null || saving) return;
    final id = item['id'].toString();
    try {
      final birdCount = await DatabaseHelper.instance.getSpeciesBirdCount(id);
      if (!mounted) return;
      final confirmationController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete this species permanently?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Linked bird records: $birdCount'),
              const SizedBox(height: 10),
              const Text(
                'A species linked to birds cannot be deleted. Type DELETE to continue.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmationController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Confirmation'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(
                dialogContext,
                confirmationController.text.trim().toUpperCase() == 'DELETE',
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      confirmationController.dispose();
      if (confirmed != true || !mounted) return;
      setState(() => saving = true);
      await DatabaseHelper.instance.deleteSpeciesCompletely(id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  String? _positiveValidator(String? value, {bool required = false}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? 'Required' : null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed <= 0) return 'Enter a positive number';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.species == null ? 'Add Species' : 'Edit Species'),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Species Name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Species name is required'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: youngController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Chick becomes Young (days)',
                helperText: 'Example: 60 means the chick becomes Young after 60 days.',
              ),
              validator: (value) => _positiveValidator(value),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: adultController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Young becomes Adult (months)',
              ),
              validator: (value) => _positiveValidator(value),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: incubationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Egg Incubation (days)',
              ),
              validator: (value) => _positiveValidator(value),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: clutchWindowController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Clutch Laying Window (days)',
              ),
              validator: (value) => _positiveValidator(value, required: true),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(saving ? 'SAVING...' : 'SAVE SPECIES'),
            ),
            if (widget.species != null) ...[
              const SizedBox(height: 44),
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    textStyle: const TextStyle(fontSize: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: saving ? null : _deleteSpecies,
                  icon: const Icon(Icons.delete_outline, size: 17),
                  label: const Text('Delete Record'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
