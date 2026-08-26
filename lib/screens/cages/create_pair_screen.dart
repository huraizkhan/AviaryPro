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

      // Fast path: when the cage has exactly one available male and one
      // available female of the same species, select both automatically.
      if (initialMaleId == null &&
          initialFemaleId == null &&
          males.length == 1 &&
          females.length == 1 &&
          males.first['speciesId'] == females.first['speciesId']) {
        initialMaleId = males.first['id'].toString();
        initialFemaleId = females.first['id'].toString();
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

  Map<String, dynamic>? _birdById(String? id) {
    if (id == null) return null;
    for (final bird in [...maleBirds, ...femaleBirds]) {
      if (bird['id']?.toString() == id) return bird;
    }
    return null;
  }

  String _birdTitle(Map<String, dynamic> bird) {
    final ring = bird['ringNumber']?.toString().trim() ?? '';
    final name = bird['name']?.toString().trim() ?? '';
    if (name.isEmpty) return ring.isEmpty ? 'No ring' : ring;
    if (ring.isEmpty) return name;
    return '$ring — $name';
  }

  bool _compatibleWithOpposite(Map<String, dynamic> bird, String gender) {
    final opposite = gender == 'Male'
        ? _birdById(selectedFemaleId)
        : _birdById(selectedMaleId);
    return opposite == null || opposite['speciesId'] == bird['speciesId'];
  }

  void _select(Map<String, dynamic> bird, String gender) {
    if (isSaving || !_compatibleWithOpposite(bird, gender)) return;
    final id = bird['id'].toString();
    setState(() {
      if (gender == 'Male') {
        selectedMaleId = selectedMaleId == id ? null : id;
      } else {
        selectedFemaleId = selectedFemaleId == id ? null : id;
      }
    });
  }

  Future<void> createPair() async {
    if (selectedMaleId == null || selectedFemaleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select one male and one female')),
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

  Widget _birdCard(Map<String, dynamic> bird, String gender) {
    final id = bird['id'].toString();
    final selected = gender == 'Male'
        ? selectedMaleId == id
        : selectedFemaleId == id;
    final compatible = _compatibleWithOpposite(bird, gender);
    final genderColor = birdGenderTextColor(gender);
    final species = bird['speciesName']?.toString().trim() ?? '';
    final mutation = bird['mutation']?.toString().trim() ?? '';
    final cage = bird['cageIdentifier']?.toString().trim() ?? '';

    return Card(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : aviaryCardSurface(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: compatible ? () => _select(bird, gender) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Opacity(
            opacity: compatible ? 1 : .42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _birdTitle(bird),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: genderColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    Chip(
                      label: Text(gender),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (species.isNotEmpty)
                      Chip(
                        label: Text(species),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (mutation.isNotEmpty)
                      Chip(
                        label: Text(mutation),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (cage.isNotEmpty)
                      Chip(
                        label: Text(aviaryCageLabel(cage)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _genderSection(
    String title,
    String gender,
    List<Map<String, dynamic>> birds,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AviaryIcon(
              AviaryIconType.bird,
              color: birdGenderTextColor(gender),
            ),
            const SizedBox(width: 8),
            Text(
              '$title (${birds.length})',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: birds.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (_, index) => _birdCard(birds[index], gender),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreatePair = selectedMaleId != null && selectedFemaleId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Create Pair')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
              children: [
                if (maleBirds.isEmpty || femaleBirds.isEmpty)
                  Card(
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'This cage does not have an available male and female bird.',
                      ),
                    ),
                  )
                else ...[
                  _genderSection('Male birds', 'Male', maleBirds),
                  const SizedBox(height: 16),
                  _genderSection('Female birds', 'Female', femaleBirds),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: canCreatePair && !isSaving ? createPair : null,
          icon: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AviaryIcon(AviaryIconType.pair, color: Colors.white),
          label: Text(isSaving ? 'SAVING...' : 'CREATE PAIR'),
        ),
      ),
    );
  }
}
