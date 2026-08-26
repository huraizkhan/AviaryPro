class Bird {
  final String id;
  final String ringNumber;
  final String name;
  final String gender;
  final String mutation;
  final DateTime? hatchDate;
  final String source;
  final double? purchasePrice;
  final bool active;

  Bird({
    required this.id,
    required this.ringNumber,
    required this.name,
    required this.gender,
    required this.mutation,
    this.hatchDate,
    required this.source,
    this.purchasePrice,
    this.active = true,
  });
}