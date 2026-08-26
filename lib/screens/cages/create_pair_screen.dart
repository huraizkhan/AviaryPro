import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';

class CreatePairScreen extends StatefulWidget {
  final String cageId;
  final String? preselectedBirdId;

  const CreatePairScreen({
    super.key,
    required this.cageId,
    this.preselectedBirdId,
  });

  @override
  State<CreatePairScreen> createState() => _CreatePairScreenState();
}

class _CreatePairScreenState extends State<CreatePairScreen> {
  final Uuid uuid = const Uuid();
  List<Map<String, dynamic>> maleBirds = [];
  List<Map<String, dynamic>> femaleBirds = [];
  String? selectedMaleId;
  String? selectedFemaleId;
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    loadBirds();
  }

  Future<void> loadBirds() async {
    try {
      final birds = await DatabaseHelper.instance
          .getAvailableBirdsForPair(widget.cageId);
      if (!mounted) return;
      final males = birds.where((bird) {
        return bird['gender']?.toString().trim().toLowerCase() == 'male';
      }).toList();
      final females = birds.where((bird) {
        return bird['gender']?.toString().trim().toLowerCase() == 'female';
      }).toList();
      String? initialMaleId;
      String? initialFemaleId;
      for (final bird in birds) {
        if (bird['id']?.toString() != widget.preselectedBirdId) continue;
        final gender = bird['gender']?.toString().toLowerCase();
        if (gender == 'male') initialMaleId = bird['id'].toString();
        if (gender == 'female') initialFemaleId = bird['id'].toString();
      }
      setState(() {
        maleBirds = males;
        femaleBirds = females;
        selectedMaleId = initialMaleId;
        selectedFemaleId = initialFemaleId;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load birds: $error')),
      );
    }
  }

  String birdName(Map<String, dynamic> bird) {
    final ringNumber = bird['ringNumber']?.toString() ?? 'No ring';
    final name = bird['name']?.toString().trim() ?? '';
    return name.isEmpty ? ringNumber : '$ringNumber — $name';
  }

  Future<void> createPair() async {
    if (selectedMaleId == null || selectedFemaleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select both birds')),
      );
      return;
    }
    setState(() => isSaving = true);
    try {
      await DatabaseHelper.instance.createPair(
        id: uuid.v4(),
        maleBirdId: selectedMaleId!,
        femaleBirdId: selectedFemaleId!,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Widget _selectionCard({
    required String title,
    required Color color,
    required List<Map<String, dynamic>> birds,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AviaryIcon(AviaryIconType.bird, color: color),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: value,
            decoration: InputDecoration(labelText: 'Select $title'),
            isExpanded: true,
            items: birds.map((bird) {
              return DropdownMenuItem<String>(
                value: bird['id'].toString(),
                child: Text(
                  birdName(bird),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: birdGenderTextColor(bird['gender']?.toString()),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }).toList(),
            onChanged: isSaving ? null : onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreatePair = maleBirds.isNotEmpty && femaleBirds.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Create Pair')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _selectionCard(
                  title: 'Male Bird',
                  color: const Color(0xFF4879C9),
                  birds: maleBirds,
                  value: selectedMaleId,
                  onChanged: (value) => setState(() => selectedMaleId = value),
                ),
                const SizedBox(height: 14),
                _selectionCard(
                  title: 'Female Bird',
                  color: const Color(0xFFD45B8C),
                  birds: femaleBirds,
                  value: selectedFemaleId,
                  onChanged: (value) => setState(() => selectedFemaleId = value),
                ),
                const SizedBox(height: 18),
                if (!canCreatePair)
                  const Card(
                    color: AviaryColors.hatchFiveDays,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'This cage does not have an available male and female bird.',
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: canCreatePair && !isSaving ? createPair : null,
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const AviaryIcon(
                          AviaryIconType.pair,
                          color: Colors.white,
                        ),
                  label: Text(isSaving ? 'SAVING...' : 'CREATE PAIR'),
                ),
              ],
            ),
    );
  }
}
