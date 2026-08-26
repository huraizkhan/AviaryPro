import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../widgets/aviary_date_picker.dart';

class StartClutchScreen extends StatefulWidget {
  final String pairId;
  final String pairLabel;

  const StartClutchScreen({
    super.key,
    required this.pairId,
    required this.pairLabel,
  });

  @override
  State<StartClutchScreen> createState() => _StartClutchScreenState();
}

class _StartClutchScreenState extends State<StartClutchScreen> {
  final notesController = TextEditingController();
  final dateFormat = DateFormat('dd-MMM-yy');
  DateTime startedAt = DateTime.now();
  bool isSaving = false;

  @override
  void dispose() {
    notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showAviaryDatePicker(
      context: context,
      initialDate: startedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    setState(() => startedAt = date);
  }

  Future<void> _save() async {
    if (isSaving) return;
    setState(() => isSaving = true);

    try {
      await DatabaseHelper.instance.startClutch(
        id: const Uuid().v4(),
        pairId: widget.pairId,
        startedAt: startedAt,
        notes: notesController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Bad state: ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Start Clutch')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.pairLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: isSaving ? null : _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Clutch start date',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.unfold_more),
              ),
              child: Text(dateFormat.format(startedAt)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: isSaving ? null : _save,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.egg),
            label: Text(isSaving ? 'STARTING...' : 'START CLUTCH'),
          ),
        ],
      ),
    );
  }
}
