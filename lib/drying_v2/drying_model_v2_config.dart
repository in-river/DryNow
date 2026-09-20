import 'garment_profile.dart';

class DryingModelV2Config {
  const DryingModelV2Config({
    required this.hmNaturalMs,
    required this.hmForcedMaxMs,
    required this.windScaleMs,
    this.integrationStep = const Duration(minutes: 5),
    this.numericEpsilon = 1e-10,
  });

  static const parameterSetId = 'literature-prototype-phase1';
  static const prototypeRelativeHumidityPct = 95.0;
  static const cottonXeqAt95Pct = 0.1367;
  static const polyesterXeqAt95Pct = 0.0059;

  final double hmNaturalMs;
  final double hmForcedMaxMs;
  final double windScaleMs;
  final Duration integrationStep;
  final double numericEpsilon;

  double prototypeEquilibriumMoistureRatio(
    FiberKind fiberKind,
    double relativeHumidityPct,
  ) {
    if ((relativeHumidityPct - prototypeRelativeHumidityPct).abs() >
        numericEpsilon) {
      throw ArgumentError.value(
        relativeHumidityPct,
        'relativeHumidityPct',
        '文献prototypeは95%RHだけを既定値として扱います。',
      );
    }
    return switch (fiberKind) {
      FiberKind.cotton => cottonXeqAt95Pct,
      FiberKind.polyester => polyesterXeqAt95Pct,
      FiberKind.blend => throw ArgumentError(
        'Phase 1 prototype requires an explicit Xeq for blends.',
      ),
    };
  }
}
