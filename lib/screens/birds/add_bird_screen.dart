import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../providers/bird_provider.dart';
import '../../ui/aviary_design.dart';
import '../../widgets/aviary_date_picker.dart';

class AddBirdScreen extends StatefulWidget {
  final Map<String, dynamic>? bird;
  final String? initialCageId;

  const AddBirdScreen({
    super.key,
    this.bird,
    this.initialCageId,
  });

  bool get isEditing => bird != null;

  @override
  State<AddBirdScreen> createState() => _AddBirdScreenState();
}

class _AddBirdScreenState extends State<AddBirdScreen> {
  static const _sourceOptions = <String>[
    'Purchase',
    'Bred',
    'Gift',
    'Caught',
    'Rescued',
    'Other',
  ];

  String _sourceLabel(String source) => switch (source) {
        'Purchase' => 'Purchased',
        'Bred' => 'Bred / Hatched here',
        'Gift' => 'Gifted',
        'Caught' => 'Caught',
        'Rescued' => 'Rescued',
        _ => 'Other',
      };

  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();
  final _dateFormat = DateFormat('dd-MMM-yy');

  final ringController = TextEditingController();
  final nameController = TextEditingController();
  final mutationController = TextEditingController();
  final priceController = TextEditingController();
  final sourcePersonController = TextEditingController();
  final sourcePlaceController = TextEditingController();
  final sourceDetailsController = TextEditingController();
  final notesController = TextEditingController();
  final estimatedAgeController = TextEditingController();

  List<Map<String, dynamic>> speciesList = [];
  List<Map<String, dynamic>> parentPairs = [];
  List<Map<String, dynamic>> cages = [];
  List<String> availableRings = [];
  List<String> managedMutations = [];
  List<String> managedNames = [];
  bool hasConfiguredRingRange = false;

  String gender = 'Unknown';
  String eyeColor = 'Unknown';
  String downColor = 'Unknown';
  String? selectedSpeciesId;
  String? selectedSource;
  String? selectedAgeGroup;
  String? selectedParentPairId;
  String? selectedCageId;
  String estimatedAgeUnit = 'Months';
  DateTime? hatchDate;
  DateTime? sourceDate;

  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadFormData();
  }

  @override
  void dispose() {
    ringController.dispose();
    nameController.dispose();
    mutationController.dispose();
    priceController.dispose();
    sourcePersonController.dispose();
    sourcePlaceController.dispose();
    sourceDetailsController.dispose();
    notesController.dispose();
    estimatedAgeController.dispose();
    super.dispose();
  }

  Future<void> _loadFormData() async {
    try {
      final species = await DatabaseHelper.instance.getSpecies();
      final pairs = await _loadActiveParentPairs();
      final cageRows = await DatabaseHelper.instance.getCages();

      if (!mounted) return;

      setState(() {
        speciesList = species;
        parentPairs = pairs;
        cages = cageRows;
        _populateExistingBird();
        if (!widget.isEditing && widget.initialCageId != null) {
          selectedCageId = widget.initialCageId;
        }
        isLoading = false;
      });
      await _loadManagedChoices();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      _showMessage('Bird form data could not be loaded');
    }
  }

  Future<void> _loadManagedChoices() async {
    final speciesId = selectedSpeciesId;
    if (speciesId == null) {
      if (mounted) {
        setState(() {
          availableRings = [];
          managedMutations = [];
          managedNames = [];
          hasConfiguredRingRange = false;
        });
      }
      return;
    }
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getAvailableRingNumbers(
        speciesId,
        excludeBirdId: widget.bird?['id']?.toString(),
      ),
      DatabaseHelper.instance.getManagedBirdValues(
        kind: 'Mutation',
        speciesId: speciesId,
      ),
      DatabaseHelper.instance.getManagedBirdValues(kind: 'Name'),
      DatabaseHelper.instance.getRingRanges(speciesId: speciesId),
    ]);
    if (!mounted) return;
    final rings = List<String>.from(results[0] as List<String>);
    final mutations = (results[1] as List<Map<String, dynamic>>)
        .map((row) => row['value'].toString())
        .toList();
    final names = (results[2] as List<Map<String, dynamic>>)
        .map((row) => row['value'].toString())
        .toList();
    final currentRing = ringController.text.trim();
    final currentMutation = mutationController.text.trim();
    final currentName = nameController.text.trim();
    if (currentRing.isNotEmpty && !rings.contains(currentRing)) rings.add(currentRing);
    if (currentMutation.isNotEmpty && !mutations.contains(currentMutation)) {
      mutations.add(currentMutation);
    }
    if (currentName.isNotEmpty && !names.contains(currentName)) names.add(currentName);
    rings.sort();
    mutations.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    setState(() {
      availableRings = rings;
      managedMutations = mutations;
      managedNames = names;
      hasConfiguredRingRange = (results[3] as List).isNotEmpty;
    });
  }

  Future<List<Map<String, dynamic>>> _loadActiveParentPairs() async {
    final db = await DatabaseHelper.instance.database;

    return db.rawQuery('''
      SELECT
        p.id,
        p.endedAt,
        CASE WHEN p.endedAt IS NULL
          THEN COALESCE(male.cageId, female.cageId)
          ELSE NULL
        END AS cageId,
        CASE WHEN p.endedAt IS NULL THEN c.identifier ELSE NULL END
          AS cageIdentifier,
        male.ringNumber AS maleRingNumber,
        male.name AS maleName,
        male.gender AS maleGender,
        male.speciesId AS maleSpeciesId,
        female.ringNumber AS femaleRingNumber,
        female.name AS femaleName,
        female.gender AS femaleGender,
        female.speciesId AS femaleSpeciesId,
        CASE WHEN p.endedAt IS NULL THEN 'Active' ELSE 'Historical' END AS pairStatus
      FROM pairs p
      INNER JOIN birds male ON male.id = p.maleBirdId
      INNER JOIN birds female ON female.id = p.femaleBirdId
      LEFT JOIN cages c
        ON p.endedAt IS NULL
        AND c.id = COALESCE(male.cageId, female.cageId)
      ORDER BY
        CASE WHEN p.endedAt IS NULL THEN 0 ELSE 1 END,
        p.createdAt DESC,
        male.ringNumber ASC
    ''');
  }


  void _populateExistingBird() {
    final bird = widget.bird;
    if (bird == null) return;

    ringController.text = bird['ringNumber']?.toString() ?? '';
    nameController.text = bird['name']?.toString() ?? '';
    mutationController.text = bird['mutation']?.toString() ?? '';
    priceController.text = bird['purchasePrice']?.toString() ?? '';
    sourcePersonController.text = bird['sourcePerson']?.toString() ?? '';
    sourcePlaceController.text = bird['sourcePlace']?.toString() ?? '';
    sourceDetailsController.text = bird['sourceDetails']?.toString() ?? '';
    notesController.text = bird['notes']?.toString() ?? '';

    final savedGender = bird['gender']?.toString();
    gender = const ['Male', 'Female', 'Unknown'].contains(savedGender)
        ? savedGender!
        : 'Unknown';
    final savedEyeColor = bird['eyeColor']?.toString();
    eyeColor = const ['Black', 'Red', 'Unknown'].contains(savedEyeColor)
        ? savedEyeColor!
        : 'Unknown';
    final savedDownColor = bird['downColor']?.toString();
    downColor = const ['White', 'Yellow', 'Unknown'].contains(savedDownColor)
        ? savedDownColor!
        : 'Unknown';

    selectedSpeciesId = bird['speciesId']?.toString();
    selectedSource = bird['source']?.toString();
    selectedAgeGroup = bird['ageGroup']?.toString();
    selectedParentPairId = bird['parentPairId']?.toString();
    selectedCageId = bird['cageId']?.toString();
    hatchDate = DateTime.tryParse(bird['hatchDate']?.toString() ?? '');
    sourceDate = DateTime.tryParse(bird['sourceDate']?.toString() ?? '');
    final savedEstimatedDays = (bird['estimatedAgeDays'] as num?)?.toInt();
    if (savedEstimatedDays != null && savedEstimatedDays > 0) {
      if (savedEstimatedDays % 365 == 0) {
        estimatedAgeUnit = 'Years';
        estimatedAgeController.text = '${savedEstimatedDays ~/ 365}';
      } else if (savedEstimatedDays % 30 == 0) {
        estimatedAgeUnit = 'Months';
        estimatedAgeController.text = '${savedEstimatedDays ~/ 30}';
      } else {
        estimatedAgeUnit = 'Days';
        estimatedAgeController.text = '$savedEstimatedDays';
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool get _birdIsPresent =>
      !widget.isEditing || (widget.bird?['active'] as num?)?.toInt() != 0;

  bool get _ringRequired => _birdIsPresent;
  bool get _cageRequired => _birdIsPresent;

  Map<String, dynamic>? get _selectedSpecies {
    for (final species in speciesList) {
      if (species['id'] == selectedSpeciesId) {
        return species;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> get _activeParentPairs => parentPairs
      .where((pair) => pair['endedAt'] == null)
      .toList();

  List<Map<String, dynamic>> get _previousParentPairs => parentPairs
      .where((pair) => pair['endedAt'] != null)
      .toList();

  List<Map<String, dynamic>> get _parentPairDropdownItems {
    final items = [..._activeParentPairs];
    if (selectedParentPairId != null &&
        !items.any((pair) => pair['id'].toString() == selectedParentPairId)) {
      for (final pair in _previousParentPairs) {
        if (pair['id'].toString() == selectedParentPairId) {
          items.add(pair);
          break;
        }
      }
    }
    return items;
  }

  Future<void> _selectPreviousPair() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Previous Pairs'),
        children: _previousParentPairs.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No previous pairs are available.'),
                ),
              ]
            : _previousParentPairs
                .map(
                  (pair) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(
                      dialogContext,
                      pair['id'].toString(),
                    ),
                    child: _pairLabelWidget(pair),
                  ),
                )
                .toList(),
      ),
    );
    if (!mounted || selected == null) return;
    _selectParentPair(selected);
  }

  String _birdLabel(Map<String, dynamic> pair, String prefix) {
    final ring = pair['${prefix}RingNumber']?.toString() ?? '';
    final name = pair['${prefix}Name']?.toString().trim() ?? '';

    return name.isEmpty ? ring : '$ring ($name)';
  }

  Color? _genderTextColor(String? gender) =>
      birdGenderTextColor(gender);

  Widget _pairLabelWidget(Map<String, dynamic> pair) {
    final cage = pair['cageIdentifier']?.toString() ?? 'No cage';
    final male = _birdLabel(pair, 'male');
    final female = _birdLabel(pair, 'female');
    final isPrevious = pair['endedAt'] != null;

    return Text.rich(
      TextSpan(
        children: [
          if (!isPrevious) TextSpan(text: '$cage — '),
          TextSpan(
            text: male,
            style: TextStyle(
              color: _genderTextColor(pair['maleGender']?.toString()),
              fontWeight: FontWeight.w600,
            ),
          ),
          const TextSpan(text: ' × '),
          TextSpan(
            text: female,
            style: TextStyle(
              color: _genderTextColor(pair['femaleGender']?.toString()),
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: isPrevious ? ' · Previous Pair' : ' · Active'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _selectParentPair(String? pairId) {
    setState(() {
      selectedParentPairId = pairId;

      if (pairId == null) return;

      final pair = parentPairs.firstWhere(
        (item) => item['id'] == pairId,
      );

      final maleSpeciesId = pair['maleSpeciesId']?.toString();
      final femaleSpeciesId = pair['femaleSpeciesId']?.toString();

      if (maleSpeciesId != null && maleSpeciesId == femaleSpeciesId) {
        selectedSpeciesId = maleSpeciesId;
      }
      if (pair['endedAt'] == null) {
        selectedCageId ??= pair['cageId']?.toString();
      }
    });
  }

  int _ageInCompletedMonths(DateTime birthDate) {
    final today = DateTime.now();
    var months = (today.year - birthDate.year) * 12;
    months += today.month - birthDate.month;
    if (today.day < birthDate.day) months--;
    return months < 0 ? 0 : months;
  }

  int _ageInDays(DateTime birthDate) {
    final today = DateTime.now();
    final start = DateTime(birthDate.year, birthDate.month, birthDate.day);
    final end = DateTime(today.year, today.month, today.day);
    final days = end.difference(start).inDays;
    return days < 0 ? 0 : days;
  }

  int? _estimatedAgeDaysValue() {
    final value = int.tryParse(estimatedAgeController.text.trim());
    if (value == null || value < 0) return null;
    return switch (estimatedAgeUnit) {
      'Years' => value * 365,
      'Months' => value * 30,
      _ => value,
    };
  }

  DateTime? _effectiveBirthDate() {
    if (hatchDate != null) return hatchDate;
    final days = _estimatedAgeDaysValue();
    if (sourceDate == null || days == null) return null;
    return sourceDate!.subtract(Duration(days: days));
  }

  String _calculatedAgeGroup() {
    final species = _selectedSpecies;
    final birthDate = _effectiveBirthDate();
    if (birthDate == null || species == null) return 'Not available';

    final ageInDays = _ageInDays(birthDate);
    final ageInMonths = _ageInCompletedMonths(birthDate);
    final chickToYoungDays = (species['chickToYoungDays'] as num?)?.toInt();
    final adultAgeMonths = (species['adultAgeMonths'] as num?)?.toInt();

    if (adultAgeMonths != null && ageInMonths >= adultAgeMonths) {
      return 'Adult';
    }
    if (chickToYoungDays != null && ageInDays >= chickToYoungDays) {
      return 'Young';
    }
    return 'Chick';
  }

  Future<void> _pickDate({
    required DateTime? currentValue,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final selectedDate = await showAviaryDatePicker(
      context: context,
      initialDate: currentValue ?? DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
    );

    if (!mounted || selectedDate == null) return;

    onSelected(selectedDate);
  }

  Widget _buildDateField({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onSelected,
    bool required = false,
  }) {
    return FormField<DateTime>(
      key: ValueKey('$label-${value?.toIso8601String()}'),
      initialValue: value,
      validator: (_) {
        if (required && value == null) {
          return '$label is required';
        }
        return null;
      },
      builder: (field) {
        return InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: isSaving
              ? null
              : () async {
                  await _pickDate(
                    currentValue: value,
                    onSelected: (date) {
                      onSelected(date);
                      field.didChange(date);
                    },
                  );
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
              border: const OutlineInputBorder(),
              errorText: field.errorText,
              suffixIcon: const Icon(Icons.unfold_more),
            ),
            child: Text(
              value == null ? 'Select date' : _dateFormat.format(value),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEstimatedAgeField() {
    Widget ageField() => TextFormField(
          controller: estimatedAgeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Estimated Age When Brought *',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final age = int.tryParse(value?.trim() ?? '');
            if (age == null || age < 0) return 'Enter a valid age';
            return null;
          },
          onChanged: (_) => setState(() {}),
        );

    Widget unitField() => DropdownButtonFormField<String>(
          initialValue: estimatedAgeUnit,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Unit',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Days', child: Text('Days')),
            DropdownMenuItem(value: 'Months', child: Text('Months')),
            DropdownMenuItem(value: 'Years', child: Text('Years')),
          ],
          onChanged: isSaving
              ? null
              : (value) => setState(() {
                    if (value != null) estimatedAgeUnit = value;
                  }),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 390) {
              return Column(
                children: [
                  ageField(),
                  const SizedBox(height: 10),
                  unitField(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: ageField()),
                const SizedBox(width: 10),
                SizedBox(width: 120, child: unitField()),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Current Calculated Age Group',
            border: OutlineInputBorder(),
          ),
          child: Text(_calculatedAgeGroup()),
        ),
      ],
    );
  }

  List<Widget> _buildSourceFields() {
    switch (selectedSource) {
      case 'Purchase':
        return [
          _buildEstimatedAgeField(),
          const SizedBox(height: 15),
          TextFormField(
            controller: priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Purchase Price *',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final price = double.tryParse(value?.trim() ?? '');

              if (value == null || value.trim().isEmpty) {
                return 'Purchase Price is required';
              }

              if (price == null || price < 0) {
                return 'Enter a valid price';
              }

              return null;
            },
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: sourcePersonController,
            decoration: const InputDecoration(
              labelText: 'Seller',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 15),
          _buildDateField(
            label: 'Purchase Date',
            value: sourceDate,
            required: true,
            onSelected: (date) {
              setState(() {
                sourceDate = date;
              });
            },
          ),
        ];

      case 'Bred':
        return [
          DropdownButtonFormField<String>(
            initialValue: selectedParentPairId,
            decoration: const InputDecoration(
              labelText: 'Parent Pair *',
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
            items: _parentPairDropdownItems.map((pair) {
              return DropdownMenuItem<String>(
                value: pair['id'].toString(),
                child: _pairLabelWidget(pair),
              );
            }).toList(),
            validator: (value) {
              if (value == null) {
                return 'Parent Pair is required';
              }
              return null;
            },
            onChanged: isSaving ? null : _selectParentPair,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: isSaving ? null : _selectPreviousPair,
              icon: const Icon(Icons.history),
              label: const Text('Previous Pairs'),
            ),
          ),
          if (_activeParentPairs.isEmpty && _previousParentPairs.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'No parent pair is available. Create the pair first.',
              style: TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 15),
          _buildDateField(
            label: 'Date of Birth / Hatch Date',
            value: hatchDate,
            required: true,
            onSelected: (date) {
              setState(() {
                hatchDate = date;
              });
            },
          ),
          const SizedBox(height: 15),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Calculated Age Group',
              border: OutlineInputBorder(),
            ),
            child: Text(_calculatedAgeGroup()),
          ),
        ];

      case 'Gift':
        return [
          _buildEstimatedAgeField(),
          const SizedBox(height: 15),
          TextFormField(
            controller: sourcePersonController,
            decoration: const InputDecoration(
              labelText: 'Gifted By *',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Gifted By is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 15),
          _buildDateField(
            label: 'Received Date',
            value: sourceDate,
            required: true,
            onSelected: (date) {
              setState(() {
                sourceDate = date;
              });
            },
          ),
        ];

      case 'Caught':
        return [
          _buildEstimatedAgeField(),
          const SizedBox(height: 15),
          TextFormField(
            controller: sourcePlaceController,
            decoration: const InputDecoration(
              labelText: 'Caught From / Place *',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Place is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 15),
          _buildDateField(
            label: 'Caught Date',
            value: sourceDate,
            required: true,
            onSelected: (date) {
              setState(() {
                sourceDate = date;
              });
            },
          ),
        ];

      case 'Rescued':
        return [
          _buildEstimatedAgeField(),
          const SizedBox(height: 15),
          TextFormField(
            controller: sourcePlaceController,
            decoration: const InputDecoration(
              labelText: 'Rescued From / Place *',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Place is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 15),
          _buildDateField(
            label: 'Rescue Date',
            value: sourceDate,
            required: true,
            onSelected: (date) {
              setState(() {
                sourceDate = date;
              });
            },
          ),
        ];

      case 'Other':
        return [
          _buildEstimatedAgeField(),
          const SizedBox(height: 15),
          TextFormField(
            controller: sourceDetailsController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Source Details *',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Source Details are required';
              }
              return null;
            },
          ),
          const SizedBox(height: 15),
          _buildDateField(
            label: 'Source Date',
            value: sourceDate,
            required: true,
            onSelected: (date) {
              setState(() {
                sourceDate = date;
              });
            },
          ),
        ];

      default:
        return [];
    }
  }

  Future<void> _saveBird() async {
    if (isSaving || !_formKey.currentState!.validate()) return;

    setState(() {
      isSaving = true;
    });

    final ringNumber = ringController.text.trim();
    final speciesId = selectedSpeciesId;
    final birdProvider = context.read<BirdProvider>();

    try {
      final duplicate = ringNumber.isNotEmpty &&
          speciesId != null &&
          await DatabaseHelper.instance.birdRingNumberExists(
            ringNumber,
            speciesId: speciesId,
            excludeBirdId: widget.bird?['id']?.toString(),
          );

      if (!mounted) return;

      if (duplicate) {
        setState(() => isSaving = false);
        _showMessage('This ring number is already used for this species');
        return;
      }

      final isBred = selectedSource == 'Bred';
      final saleStatus = widget.isEditing
          ? (widget.bird!['saleStatus']?.toString() ?? 'Not for Sale')
          : isBred
              ? 'Available'
              : 'Not for Sale';

      final values = <String, dynamic>{
        'ringNumber': ringNumber,
        'name': nameController.text.trim(),
        'gender': gender,
        'mutation': mutationController.text.trim(),
        'eyeColor': eyeColor == 'Unknown' ? null : eyeColor,
        'downColor': downColor == 'Unknown' ? null : downColor,
        'hatchDate': isBred ? hatchDate?.toIso8601String() : null,
        'speciesId': selectedSpeciesId,
        'ageGroup': _calculatedAgeGroup() == 'Not available'
            ? selectedAgeGroup
            : _calculatedAgeGroup(),
        'estimatedAgeDays': isBred ? null : _estimatedAgeDaysValue(),
        'source': selectedSource,
        'sourceDate': isBred
            ? hatchDate?.toIso8601String()
            : sourceDate?.toIso8601String(),
        'sourcePerson': selectedSource == 'Purchase' || selectedSource == 'Gift'
            ? sourcePersonController.text.trim()
            : null,
        'sourcePlace': selectedSource == 'Caught' || selectedSource == 'Rescued'
            ? sourcePlaceController.text.trim()
            : null,
        'sourceDetails': selectedSource == 'Other'
            ? sourceDetailsController.text.trim()
            : null,
        'parentPairId': isBred ? selectedParentPairId : null,
        'purchasePrice': selectedSource == 'Purchase'
            ? double.tryParse(priceController.text.trim())
            : null,
        'saleStatus': saleStatus,
        'notes': notesController.text.trim(),
        'cageId': selectedCageId,
      };

      if (widget.isEditing) {
        await DatabaseHelper.instance.updateBird(
          widget.bird!['id'].toString(),
          values,
        );
        await birdProvider.loadBirds();
      } else {
        await birdProvider.addBird({
          'id': _uuid.v4(),
          ...values,
          'active': 1,
        });
      }

      if (!mounted) return;

      _showMessage(widget.isEditing ? 'Bird Updated' : 'Bird Saved');
      Navigator.pop(context, true);
    } on DatabaseException catch (error) {
      if (!mounted) return;

      _showMessage(
        error.isUniqueConstraintError()
            ? 'This ring number is already used for this species'
            : 'Bird could not be saved',
      );
    } on StateError catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;

      _showMessage('Bird could not be saved');
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteBird() async {
    if (!widget.isEditing || isSaving) return;
    try {
      final birdId = widget.bird!['id'].toString();
      final impact = await DatabaseHelper.instance.getBirdDeleteImpact(birdId);
      if (!mounted) return;
      final confirmationController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete this bird permanently?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This deletes the bird and all linked history.\n\n'
                'Events: ${impact['events']}\n'
                'Finance records: ${impact['finance']}\n'
                'Pairs: ${impact['pairs']}\n'
                'Clutches: ${impact['clutches']}\n'
                'Offspring links: ${impact['offspring']}',
              ),
              const SizedBox(height: 14),
              const Text('Type DELETE to continue.'),
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

      setState(() => isSaving = true);
      await DatabaseHelper.instance.deleteBirdCompletely(birdId);
      if (!mounted) return;
      await context.read<BirdProvider>().loadBirds();
      if (!mounted) return;
      Navigator.pop(context, 'deleted');
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Bird' : 'Add Bird'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedSource,
                    decoration: const InputDecoration(
                      labelText: 'Source *',
                      helperText: 'Choose how this bird entered your aviary first.',
                      border: OutlineInputBorder(),
                    ),
                    items: _sourceOptions.map((source) {
                      return DropdownMenuItem<String>(
                        value: source,
                        child: Text(_sourceLabel(source)),
                      );
                    }).toList(),
                    validator: (value) =>
                        value == null ? 'Source is required' : null,
                    onChanged: isSaving
                        ? null
                        : (value) => setState(() => selectedSource = value),
                  ),
                  if (selectedSource != null) ...[
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                    key: ValueKey(selectedSpeciesId),
                    initialValue: selectedSpeciesId,
                    decoration: const InputDecoration(
                      labelText: 'Species *',
                      border: OutlineInputBorder(),
                    ),
                    items: speciesList.map((species) {
                      return DropdownMenuItem<String>(
                        value: species['id'].toString(),
                        child: Text(species['name'].toString()),
                      );
                    }).toList(),
                    validator: (value) =>
                        value == null ? 'Species is required' : null,
                    onChanged: isSaving
                        ? null
                        : (value) async {
                            setState(() {
                              selectedSpeciesId = value;
                              ringController.clear();
                              mutationController.clear();
                            });
                            await _loadManagedChoices();
                          },
                  ),
                  if (speciesList.isEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'No species is available. Add a species in Settings first.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'ring_${selectedSpeciesId}_${ringController.text}_$hasConfiguredRingRange',
                    ),
                    initialValue: ringController.text.trim().isEmpty
                        ? null
                        : ringController.text.trim(),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _ringRequired ? 'Ring Number *' : 'Ring Number',
                      helperText: selectedSpeciesId == null
                          ? 'Choose species first.'
                          : !hasConfiguredRingRange
                              ? 'Configure rings in Settings > Ring Management first.'
                              : availableRings.isEmpty
                                  ? 'No available configured rings for this species.'
                                  : 'Only available configured rings are shown.',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      if (!_ringRequired)
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('No ring'),
                        ),
                      ...availableRings.map(
                        (ring) => DropdownMenuItem<String>(
                          value: ring,
                          child: Text(ring),
                        ),
                      ),
                    ],
                    validator: (value) {
                      if (_ringRequired && !hasConfiguredRingRange) {
                        final existing = widget.isEditing &&
                            ringController.text.trim().isNotEmpty;
                        if (!existing) {
                          return 'Configure a ring range for this species';
                        }
                      }
                      if (_ringRequired &&
                          (value == null || value.trim().isEmpty)) {
                        return 'Ring Number is required';
                      }
                      return null;
                    },
                    onChanged: isSaving || !hasConfiguredRingRange
                        ? null
                        : (value) => setState(
                              () => ringController.text = value ?? '',
                            ),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    key: ValueKey('name_${nameController.text}_${managedNames.length}'),
                    initialValue: nameController.text.trim().isEmpty
                        ? ''
                        : nameController.text.trim(),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Bird Name',
                      helperText: managedNames.isEmpty
                          ? 'Add names in Settings > Bird Name Management.'
                          : 'Choose a managed bird name.',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('No name'),
                      ),
                      ...managedNames.map(
                        (name) => DropdownMenuItem<String>(
                          value: name,
                          child: Text(name),
                        ),
                      ),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => setState(
                              () => nameController.text = value ?? '',
                            ),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    initialValue: gender,
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                      DropdownMenuItem(value: 'Unknown', child: Text('Unknown')),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) {
                            if (value != null) setState(() => gender = value);
                          },
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    key: ValueKey('cage_$selectedCageId'),
                    initialValue: selectedCageId,
                    decoration: InputDecoration(
                      labelText: _cageRequired ? 'Cage *' : 'Cage',
                      helperText: _cageRequired
                          ? 'Every active bird must belong to a cage.'
                          : 'Previous birds can remain without a cage.',
                    ),
                    isExpanded: true,
                    items: cages.map((cage) {
                      return DropdownMenuItem<String>(
                        value: cage['id'].toString(),
                        child: Text(cage['identifier']?.toString() ?? 'Cage'),
                      );
                    }).toList(),
                    validator: (value) =>
                        _cageRequired && value == null ? 'Cage is required' : null,
                    onChanged: isSaving
                        ? null
                        : (value) => setState(() => selectedCageId = value),
                  ),
                  if (cages.isEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'No cage is available. Add a cage before adding birds.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'mutation_${mutationController.text}_${managedMutations.length}',
                    ),
                    initialValue: mutationController.text.trim().isEmpty
                        ? ''
                        : mutationController.text.trim(),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Mutation',
                      helperText: managedMutations.isEmpty
                          ? 'Add mutations in Settings > Mutation Management.'
                          : 'Choose a managed mutation.',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('No mutation'),
                      ),
                      ...managedMutations.map(
                        (mutation) => DropdownMenuItem<String>(
                          value: mutation,
                          child: Text(mutation),
                        ),
                      ),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => setState(
                              () => mutationController.text = value ?? '',
                            ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: eyeColor,
                          decoration: const InputDecoration(
                            labelText: 'Eye Color',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Unknown', child: Text('Unknown')),
                            DropdownMenuItem(value: 'Black', child: Text('Black eyes')),
                            DropdownMenuItem(value: 'Red', child: Text('Red eyes')),
                          ],
                          onChanged: isSaving
                              ? null
                              : (value) => setState(() => eyeColor = value ?? 'Unknown'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: downColor,
                          decoration: const InputDecoration(
                            labelText: 'Chick Down',
                            helperText: 'Useful before full feathering.',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Unknown', child: Text('Unknown')),
                            DropdownMenuItem(value: 'White', child: Text('White')),
                            DropdownMenuItem(value: 'Yellow', child: Text('Yellow')),
                          ],
                          onChanged: isSaving
                              ? null
                              : (value) => setState(() => downColor = value ?? 'Unknown'),
                        ),
                      ),
                    ],
                  ),
                  if (selectedSource != null) ...[
                    const SizedBox(height: 15),
                    ..._buildSourceFields(),
                  ],
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: notesController,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 30),
                  FilledButton.icon(
                    onPressed: isSaving ? null : _saveBird,
                    icon: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      isSaving
                          ? 'SAVING...'
                          : widget.isEditing
                              ? 'UPDATE'
                              : 'SAVE',
                    ),
                  ),
                  if (widget.isEditing) ...[
                    const SizedBox(height: 44),
                    Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          textStyle: const TextStyle(fontSize: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: isSaving ? null : _deleteBird,
                        icon: const Icon(Icons.delete_outline, size: 17),
                        label: const Text('Delete Record'),
                      ),
                    ),
                  ],
                  ],
                ],
              ),
            ),
    );
  }
}
