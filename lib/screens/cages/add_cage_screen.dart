import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';

class AddCageScreen extends StatefulWidget {
  const AddCageScreen({super.key});

  @override
  State<AddCageScreen> createState() => _AddCageScreenState();
}

class _AddCageScreenState extends State<AddCageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  final physicalNameController = TextEditingController();
  final customNameController = TextEditingController();
  final portionsController = TextEditingController(text: '1');
  final locationController = TextEditingController();
  final notesController = TextEditingController();

  String identityMode = 'series';
  String cageType = 'Breeding Cage';
  bool saving = false;

  @override
  void dispose() {
    physicalNameController.dispose();
    customNameController.dispose();
    portionsController.dispose();
    locationController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> saveCage() async {
    if (!_formKey.currentState!.validate() || saving) return;
    setState(() => saving = true);

    try {
      if (identityMode == 'named') {
        final name = customNameController.text.trim();
        final duplicate = await DatabaseHelper.instance.cageIdentifierExists(name);
        if (duplicate) {
          throw StateError('This cage name already exists.');
        }
        final id = _uuid.v4();
        await DatabaseHelper.instance.insertCageConfiguration([
          {
            'id': id,
            'identifier': name,
            'type': cageType,
            'location': locationController.text.trim(),
            'notes': notesController.text.trim(),
            'identityMode': 'named',
            'physicalCageId': id,
            'physicalName': name,
            'portionIndex': 1,
          },
        ]);
      } else {
        final physicalId = _uuid.v4();
        final portionCount = int.parse(portionsController.text.trim());
        final physicalName = physicalNameController.text.trim();
        final rows = <Map<String, dynamic>>[];
        for (var index = 1; index <= portionCount; index++) {
          rows.add({
            'id': _uuid.v4(),
            'identifier': 'Pending Cage $index',
            'type': cageType,
            'location': locationController.text.trim(),
            'notes': notesController.text.trim(),
            'identityMode': 'series',
            'physicalCageId': physicalId,
            'physicalName': physicalName,
            'portionIndex': index,
          });
        }
        await DatabaseHelper.instance.insertCageConfiguration(rows);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            identityMode == 'series'
                ? 'Cage portions added to the numbered series'
                : 'Named cage saved',
          ),
        ),
      );
      Navigator.pop(context, true);
    } on DatabaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.isUniqueConstraintError()
                ? 'This cage name already exists'
                : 'Cage could not be saved',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Cage')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'series',
                  icon: Icon(Icons.format_list_numbered),
                  label: Text('Numbered Series'),
                ),
                ButtonSegment(
                  value: 'named',
                  icon: Icon(Icons.badge_outlined),
                  label: Text('Custom Name'),
                ),
              ],
              selected: {identityMode},
              onSelectionChanged: saving
                  ? null
                  : (selection) => setState(() => identityMode = selection.first),
            ),
            const SizedBox(height: 18),
            if (identityMode == 'series') ...[
              TextFormField(
                controller: physicalNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Whole Cage Name *',
                  helperText: 'Shown below each numbered cage portion.',
                ),
                validator: (value) {
                  if (identityMode == 'series' &&
                      (value == null || value.trim().isEmpty)) {
                    return 'Whole cage name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: portionsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Number of Portions *',
                  helperText: 'The app continues the Cage1, Cage2… series.',
                ),
                validator: (value) {
                  if (identityMode != 'series') return null;
                  final count = int.tryParse(value?.trim() ?? '');
                  if (count == null || count < 1 || count > 100) {
                    return 'Enter a number from 1 to 100';
                  }
                  return null;
                },
              ),
            ] else
              TextFormField(
                controller: customNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Cage / Area Name *',
                  helperText: 'For example: Hall or Flying Cage.',
                ),
                validator: (value) {
                  if (identityMode == 'named' &&
                      (value == null || value.trim().isEmpty)) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              initialValue: cageType,
              decoration: const InputDecoration(labelText: 'Cage Type'),
              items: const [
                DropdownMenuItem(
                  value: 'Breeding Cage',
                  child: Text('Breeding Cage'),
                ),
                DropdownMenuItem(
                  value: 'Flight Cage',
                  child: Text('Flight Cage'),
                ),
                DropdownMenuItem(
                  value: 'Hospital Cage',
                  child: Text('Hospital Cage'),
                ),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => cageType = value);
                    },
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: locationController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: notesController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: saving ? null : saveCage,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(saving ? 'SAVING...' : 'SAVE'),
            ),
          ],
        ),
      ),
    );
  }
}
