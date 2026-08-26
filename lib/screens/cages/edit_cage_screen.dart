import 'package:flutter/material.dart';

import '../../database/database_helper.dart';

class EditCageScreen extends StatefulWidget {
  const EditCageScreen({
    super.key,
    required this.cageId,
  });

  final String cageId;

  @override
  State<EditCageScreen> createState() => _EditCageScreenState();
}

class _EditCageScreenState extends State<EditCageScreen> {
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final locationController = TextEditingController();
  final notesController = TextEditingController();

  Map<String, dynamic>? cage;
  List<Map<String, dynamic>> otherCages = const [];
  Set<String> selectedMergeLinks = <String>{};
  String cageType = 'Breeding Cage';
  bool loading = true;
  bool saving = false;

  bool get isSeries => cage?['identityMode']?.toString() == 'series';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    nameController.dispose();
    locationController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        DatabaseHelper.instance.getCageById(widget.cageId),
        DatabaseHelper.instance.getCages(),
        DatabaseHelper.instance.getCageMergeLinkIds(widget.cageId),
      ]);
      final loadedCage = results[0] as Map<String, dynamic>?;
      if (loadedCage == null) {
        throw StateError('Cage could not be found.');
      }
      final cages = (results[1] as List<Map<String, dynamic>>)
          .where((item) =>
              item['id']?.toString() != widget.cageId &&
              loadedCage['identityMode'] == 'series' &&
              item['identityMode'] == 'series' &&
              item['physicalCageId']?.toString() ==
                  loadedCage['physicalCageId']?.toString())
          .toList();
      final links = results[2] as Set<String>;

      nameController.text = loadedCage['identityMode'] == 'series'
          ? loadedCage['physicalName']?.toString() ?? ''
          : loadedCage['identifier']?.toString() ?? '';
      locationController.text = loadedCage['location']?.toString() ?? '';
      notesController.text = loadedCage['notes']?.toString() ?? '';

      if (!mounted) return;
      setState(() {
        cage = loadedCage;
        otherCages = cages;
        selectedMergeLinks = links;
        cageType = loadedCage['type']?.toString().trim().isNotEmpty == true
            ? loadedCage['type'].toString()
            : 'Breeding Cage';
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => loading = false);
      _message(error);
    }
  }

  String _errorText(Object error) {
    return error.toString().replaceFirst('Bad state: ', '');
  }

  void _message(Object message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_errorText(message))),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || saving || cage == null) return;
    setState(() => saving = true);
    try {
      final name = nameController.text.trim();
      if (!isSeries) {
        final duplicate = await DatabaseHelper.instance.cageIdentifierExists(
          name,
          excludeCageId: widget.cageId,
        );
        if (duplicate) throw StateError('This cage name already exists.');
      }

      await DatabaseHelper.instance.updateCage(widget.cageId, {
        if (isSeries) 'physicalName': name else 'identifier': name,
        'type': cageType,
        'location': locationController.text.trim(),
        'notes': notesController.text.trim(),
      });
      await DatabaseHelper.instance.setCageMergeLinks(
        widget.cageId,
        selectedMergeLinks,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _delete() async {
    if (saving) return;
    try {
      final impact =
          await DatabaseHelper.instance.getCageDeleteImpact(widget.cageId);
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeleteCageConfirmationDialog(impact: impact),
      );
      if (confirmed != true || !mounted) return;
      // Let the confirmation dialog finish closing before changing or popping
      // the route underneath it.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;

      setState(() => saving = true);
      await DatabaseHelper.instance.deleteCageCompletely(widget.cageId);
      if (!mounted) return;
      Navigator.of(context).pop('deleted');
    } catch (error) {
      _message(error);
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Cage')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Cage')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            TextFormField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: isSeries ? 'Whole Cage Name *' : 'Cage / Area Name *',
                helperText: isSeries
                    ? 'Shown below this numbered cage portion.'
                    : null,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Name is required'
                  : null,
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 14),
            TextFormField(
              controller: locationController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: notesController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 24),
            if (isSeries) ...[
              Text(
                'Merge grouping',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Select portions that should appear together as a group in the merge selection. Only portions of this whole cage are available.',
              ),
              const SizedBox(height: 8),
              if (otherCages.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('This whole cage has no other active portions.'),
                  ),
                )
              else
                ...otherCages.map((other) {
                  final id = other['id'].toString();
                  final physicalName = other['identityMode'] == 'series'
                      ? other['physicalName']?.toString() ?? ''
                      : '';
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selectedMergeLinks.contains(id),
                    title: Text(other['identifier']?.toString() ?? 'Cage'),
                    subtitle: physicalName.isEmpty ? null : Text(physicalName),
                    onChanged: saving
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                selectedMergeLinks.add(id);
                              } else {
                                selectedMergeLinks.remove(id);
                              }
                            });
                          },
                  );
                }),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(saving ? 'SAVING...' : 'SAVE CHANGES'),
            ),
            const SizedBox(height: 44),
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                  textStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: saving ? null : _delete,
                icon: const Icon(Icons.delete_outline, size: 17),
                label: const Text('Delete Record'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteCageConfirmationDialog extends StatefulWidget {
  const _DeleteCageConfirmationDialog({required this.impact});

  final Map<String, int> impact;

  @override
  State<_DeleteCageConfirmationDialog> createState() =>
      _DeleteCageConfirmationDialogState();
}

class _DeleteCageConfirmationDialogState
    extends State<_DeleteCageConfirmationDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _canDelete = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateDeleteState);
  }

  void _updateDeleteState() {
    final next = _controller.text.trim().toUpperCase() == 'DELETE';
    if (next != _canDelete && mounted) {
      setState(() => _canDelete = next);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updateDeleteState)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete this cage permanently?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deleting any portion deletes the entire physical cage and all '
              'of its portions. Bird records are never deleted.\n\n'
              'Physical portions: ${widget.impact['portions']}\n'
              'Current birds that must be moved first: ${widget.impact['birds']}\n'
              'Merge links to clear: ${widget.impact['mergeLinks']}\n'
              'Merged cage references to clear: ${widget.impact['mergedCages']}',
            ),
            const SizedBox(height: 14),
            const Text('Type DELETE to continue.'),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Confirmation'),
              onSubmitted: (_) {
                if (_canDelete) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed:
              _canDelete ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

