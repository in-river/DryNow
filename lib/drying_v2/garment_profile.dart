enum FiberKind { cotton, polyester, blend }

class GarmentProfile {
  const GarmentProfile({
    required this.id,
    required this.fiberKind,
    required this.dryMassKg,
    required this.effectiveAreaM2,
    required this.initialMoistureRatio,
    required this.criticalMoistureRatio,
    required this.targetMoistureRatio,
    required this.fallingRateConstantPerSecond,
    this.cottonFraction,
    this.polyesterFraction,
  });

  final String id;
  final FiberKind fiberKind;
  final double dryMassKg;
  final double effectiveAreaM2;
  final double initialMoistureRatio;
  final double criticalMoistureRatio;
  final double targetMoistureRatio;
  final double fallingRateConstantPerSecond;
  final double? cottonFraction;
  final double? polyesterFraction;
}
