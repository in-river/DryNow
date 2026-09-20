enum DryingPhase { constantRate, fallingRate, equilibriumStalled, completed }

enum DryingPredictionStatus {
  completed,
  equilibriumLimited,
  notCompletedWithinForecast,
  insufficientData,
}

class MoistureState {
  const MoistureState({
    required this.elapsed,
    required this.moistureRatio,
    required this.removedWaterKg,
    required this.phase,
  });

  final Duration elapsed;
  final double moistureRatio;
  final double removedWaterKg;
  final DryingPhase phase;
}

class DryingStepResult {
  const DryingStepResult({
    required this.startElapsed,
    required this.endElapsed,
    required this.xBefore,
    required this.xAfter,
    required this.xeq,
    required this.xc,
    required this.phaseBefore,
    required this.phaseAfter,
    required this.dryingRatePerSecond,
    required this.vaporDensityDifferenceKgM3,
    required this.massTransferVelocityMs,
    required this.removedWaterKg,
    required this.cumulativeRemovedWaterKg,
  });

  final Duration startElapsed;
  final Duration endElapsed;
  final double xBefore;
  final double xAfter;
  final double xeq;
  final double xc;
  final DryingPhase phaseBefore;
  final DryingPhase phaseAfter;
  final double dryingRatePerSecond;
  final double vaporDensityDifferenceKgM3;
  final double massTransferVelocityMs;
  final double removedWaterKg;
  final double cumulativeRemovedWaterKg;
}

typedef DryingEstimateV2 = ({
  DryingPredictionStatus status,
  Duration? duration,
  MoistureState finalState,
  List<DryingStepResult> trace,
});
