import 'garment_profile.dart';

abstract interface class EquilibriumMoistureModel {
  EquilibriumMoistureResult equilibriumMoistureRatio({
    required double temperatureC,
    required double relativeHumidityPct,
    required FiberKind material,
    double? cottonFraction,
    double? polyesterFraction,
  });

  EquilibriumMoistureMetadata get metadata;
}

final class EquilibriumMoistureResult {
  const EquilibriumMoistureResult.supported(double this.value)
    : isSupported = true,
      reason = null;

  const EquilibriumMoistureResult.unsupported(String this.reason)
    : isSupported = false,
      value = null;

  final bool isSupported;
  final double? value;
  final String? reason;
}

final class EquilibriumMoistureNode {
  const EquilibriumMoistureNode({
    required this.relativeHumidityPct,
    required this.moistureRatioDryBasis,
  });

  final double relativeHumidityPct;
  final double moistureRatioDryBasis;
}

final class EquilibriumMoistureMetadata {
  const EquilibriumMoistureMetadata({
    required this.parameterSetId,
    required this.source,
    required this.materials,
    required this.relativeHumidityNodesPct,
    required this.basis,
    required this.temperatureCondition,
    required this.isPrototype,
    required this.blendAssumption,
  });

  final String parameterSetId;
  final String source;
  final List<FiberKind> materials;
  final List<double> relativeHumidityNodesPct;
  final String basis;
  final String temperatureCondition;
  final bool isPrototype;
  final String blendAssumption;
}

final class TabulatedEquilibriumMoistureModel
    implements EquilibriumMoistureModel {
  const TabulatedEquilibriumMoistureModel();

  static const parameterSetId = 'literature-xeq-prototype-v1';
  static const source =
      'Martí et al. (2021), Polymers 13(17), Table 1, '
      'doi:10.3390/polym13173010';

  static const cottonNodes = <EquilibriumMoistureNode>[
    EquilibriumMoistureNode(
      relativeHumidityPct: 65,
      moistureRatioDryBasis: 0.049,
    ),
    EquilibriumMoistureNode(
      relativeHumidityPct: 95,
      moistureRatioDryBasis: 0.1367,
    ),
  ];

  static const polyesterNodes = <EquilibriumMoistureNode>[
    EquilibriumMoistureNode(
      relativeHumidityPct: 65,
      moistureRatioDryBasis: 0.005,
    ),
    EquilibriumMoistureNode(
      relativeHumidityPct: 95,
      moistureRatioDryBasis: 0.0059,
    ),
  ];

  @override
  EquilibriumMoistureMetadata get metadata => const EquilibriumMoistureMetadata(
    parameterSetId: parameterSetId,
    source: source,
    materials: [FiberKind.cotton, FiberKind.polyester, FiberKind.blend],
    relativeHumidityNodesPct: [65, 95],
    basis: 'kg-water/kg-dry (dry basis)',
    temperatureCondition:
        '25°C DVS source condition; Phase 3 applies no temperature correction',
    isPrototype: true,
    blendAssumption:
        'Prototype mass-fraction weighted average of cotton and polyester',
  );

  @override
  EquilibriumMoistureResult equilibriumMoistureRatio({
    required double temperatureC,
    required double relativeHumidityPct,
    required FiberKind material,
    double? cottonFraction,
    double? polyesterFraction,
  }) {
    if (!temperatureC.isFinite ||
        !relativeHumidityPct.isFinite ||
        relativeHumidityPct < 0 ||
        relativeHumidityPct > 100) {
      throw ArgumentError('Temperature and RH must be finite, and RH 0–100%.');
    }
    if (relativeHumidityPct < 65 || relativeHumidityPct > 95) {
      return EquilibriumMoistureResult.unsupported(
        'RH $relativeHumidityPct% is outside documented nodes 65–95%.',
      );
    }

    final cotton = _interpolate(cottonNodes, relativeHumidityPct);
    final polyester = _interpolate(polyesterNodes, relativeHumidityPct);
    return switch (material) {
      FiberKind.cotton => EquilibriumMoistureResult.supported(cotton),
      FiberKind.polyester => EquilibriumMoistureResult.supported(polyester),
      FiberKind.blend => _blend(
        cotton,
        polyester,
        cottonFraction,
        polyesterFraction,
      ),
    };
  }

  EquilibriumMoistureResult _blend(
    double cotton,
    double polyester,
    double? cottonFraction,
    double? polyesterFraction,
  ) {
    if (cottonFraction == null || polyesterFraction == null) {
      throw ArgumentError('Blend requires cotton and polyester fractions.');
    }
    if (!cottonFraction.isFinite ||
        !polyesterFraction.isFinite ||
        cottonFraction < 0 ||
        polyesterFraction < 0 ||
        (cottonFraction + polyesterFraction - 1).abs() > 1e-9) {
      throw ArgumentError(
        'Blend fractions must be finite, nonnegative, and sum to 1.',
      );
    }
    return EquilibriumMoistureResult.supported(
      cottonFraction * cotton + polyesterFraction * polyester,
    );
  }

  double _interpolate(List<EquilibriumMoistureNode> nodes, double rh) {
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      if (rh == node.relativeHumidityPct) {
        return node.moistureRatioDryBasis;
      }
      if (index == 0 || rh > node.relativeHumidityPct) continue;
      final lower = nodes[index - 1];
      final fraction =
          (rh - lower.relativeHumidityPct) /
          (node.relativeHumidityPct - lower.relativeHumidityPct);
      return lower.moistureRatioDryBasis +
          fraction * (node.moistureRatioDryBasis - lower.moistureRatioDryBasis);
    }
    throw StateError('Interpolation requires RH within documented nodes.');
  }
}
