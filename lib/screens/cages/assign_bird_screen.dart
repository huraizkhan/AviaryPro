import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';

class AssignBirdScreen extends StatefulWidget {
  final String cageId;

  const AssignBirdScreen({
    super.key,
    required this.cageId,
  });

  @override
  State<AssignBirdScreen> createState() => _AssignBirdScreenState();
}

class _AssignBirdScreenState extends State<AssignBirdScreen> {
  List<Map<String, dynamic>> birds = const [];
  final Set<String> selectedBirds = <String>{};
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    loadBirds();
  }

  Future<void> loadBirds() async {
    final allBirds = await DatabaseHelper.instance.getBirds();
    if (!mounted) return;

    setState(() {
      birds = allBirds
          .where(
            (bird) =>
                bird['active'] != 0 &&
                bird['cageId']?.toString() != widget.cageId &&
                !(bird['nestClutchId'] != null &&
                    bird['leftNestDate'] == null),
          )
          .toList();
      loading = false;
    });
  }

  Future<String?> _choosePairedMoveAction(
    Map<String, dynamic> bird,
    Map<String, dynamic> pairInfo,
  ) {
    final partnerRing = pairInfo['partnerRingNumber']?.toString() ?? 'Bird';
    final partnerName = pairInfo['partnerName']?.toString().trim() ?? '';
    final partner =
        partnerName.isEmpty ? partnerRing : '$partnerRing ($partnerName)';
    final activeClutches =
        (pairInfo['activeClutchCount'] as num?)?.toInt() ?? 0;
    final chicks = (pairInfo['chicksInNest'] as num?)?.toInt() ?? 0;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('This bird is paired'),
        content: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: bird['ringNumber']?.toString() ?? 'This bird',
                style: TextStyle(
                  color: birdGenderTextColor(bird['gender']?.toString()),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: ' is paired with '),
              TextSpan(
                text: partner,
                style: TextStyle(
                  color: birdGenderTextColor(
                    pairInfo['partnerGender']?.toString(),
                  ),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: '.\n\n'),
              if (activeClutches > 0 || chicks > 0)
                TextSpan(
                  text: 'Warning: this pair has $activeClutches active '
                      'clutch(es) and $chicks chick(s) in the nest.\n\n',
                ),
              const TextSpan(
                text: 'Choose how to move the bird into this cage.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('skip'),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('unpair'),
            child: const Text('Unpair & Move This Bird'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('pair'),
            child: const Text('Move Whole Pair'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (selectedBirds.isEmpty || saving) return;
    setState(() => saving = true);
    try {
      final handledPairs = <String>{};
      for (final id in selectedBirds) {
        final bird = birds.firstWhere((item) => item['id'].toString() == id);
        final pairInfo = await DatabaseHelper.instance.getActivePairMoveInfo(id);
        if (!mounted) return;

        if (pairInfo == null) {
          await DatabaseHelper.instance.assignBirdToCage(id, widget.cageId);
          continue;
        }

        final pairId = pairInfo['pairId'].toString();
        if (handledPairs.contains(pairId)) continue;
        final maleId = pairInfo['maleBirdId']?.toString();
        final femaleId = pairInfo['femaleBirdId']?.toString();
        final bothSelected = maleId != null &&
            femaleId != null &&
            selectedBirds.contains(maleId) &&
            selectedBirds.contains(femaleId);

        if (bothSelected) {
          await DatabaseHelper.instance.moveWholePairToCage(
            pairId: pairId,
            cageId: widget.cageId,
          );
          handledPairs.add(pairId);
          continue;
        }

        final action = await _choosePairedMoveAction(bird, pairInfo);
        if (!mounted) return;
        if (action == 'pair') {
          await DatabaseHelper.instance.moveWholePairToCage(
            pairId: pairId,
            cageId: widget.cageId,
          );
          handledPairs.add(pairId);
        } else if (action == 'unpair') {
          await DatabaseHelper.instance.unpairAndMoveBird(
            pairId: pairId,
            birdId: id,
            cageId: widget.cageId,
          );
          handledPairs.add(pairId);
        }
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Move Existing Bird'),
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : birds.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No active birds are available in other cages or without a cage.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 8),
                        itemCount: birds.length,
                        itemBuilder: (context, index) {
                          final bird = birds[index];
                          final id = bird['id'].toString();
                          final ring =
                              bird['ringNumber']?.toString() ?? 'No ring';
                          final name = bird['name']?.toString().trim() ?? '';
                          final species =
                              bird['speciesName']?.toString().trim() ?? '';
                          final currentCage =
                              bird['cageIdentifier']?.toString().trim();
                          final position = currentCage == null ||
                                  currentCage.isEmpty
                              ? 'Currently unassigned'
                              : 'Currently in $currentCage';

                          return CheckboxListTile(
                            value: selectedBirds.contains(id),
                            title: Text(
                              name.isEmpty ? ring : '$ring — $name',
                              style: TextStyle(
                                color: birdGenderTextColor(
                                  bird['gender']?.toString(),
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (species.isNotEmpty) species,
                                position,
                              ].join(' · '),
                            ),
                            onChanged: saving
                                ? null
                                : (value) {
                                    setState(() {
                                      if (value == true) {
                                        selectedBirds.add(id);
                                      } else {
                                        selectedBirds.remove(id);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      selectedBirds.isEmpty || saving ? null : _save,
                  child: Text(
                    saving
                        ? 'MOVING...'
                        : 'MOVE ${selectedBirds.length == 1 ? 'BIRD' : '${selectedBirds.length} BIRDS'}',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
