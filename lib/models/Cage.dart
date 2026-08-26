// ignore_for_file: file_names
class Cage {
  final String id;
  final String cageName;
  final String cageType;
  final String? location;
  final String? notes;
  final bool active;

  Cage({
    required this.id,
    required this.cageName,
    required this.cageType,
    this.location,
    this.notes,
    this.active = true,
  });
}