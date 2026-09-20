import 'moisture_state.dart';

final class ForecastDryingIssueV2 {
  const ForecastDryingIssueV2({
    required this.timeUtc,
    required this.temperatureC,
    required this.relativeHumidityPct,
    required this.material,
    required this.reason,
  });

  final DateTime timeUtc;
  final double temperatureC;
  final double relativeHumidityPct;
  final String material;
  final String reason;
}

final class ForecastDryingStepResult {
  const ForecastDryingStepResult({
    required this.startTimeUtc,
    required this.endTimeUtc,
    required this.temperatureC,
    required this.relativeHumidityPct,
    required this.windSpeedMs,
    required this.xBefore,
    required this.xAfter,
    required this.xeq,
    required this.phaseBefore,
    required this.phaseAfter,
    required this.dryingRatePerSecond,
    required this.massTransferVelocityMs,
    required this.vaporDensityDifferenceKgM3,
  });

  final DateTime startTimeUtc;
  final DateTime endTimeUtc;
  final double temperatureC;
  final double relativeHumidityPct;
  final double windSpeedMs;
  final double xBefore;
  final double xAfter;
  final double xeq;
  final DryingPhase phaseBefore;
  final DryingPhase phaseAfter;
  final double dryingRatePerSecond;
  final double massTransferVelocityMs;
  final double vaporDensityDifferenceKgM3;
}

final class ForecastDryingEstimateV2 {
  const ForecastDryingEstimateV2({
    required this.status,
    required this.startTimeUtc,
    required this.completionTimeUtc,
    required this.duration,
    required this.finalState,
    required this.numberOfSteps,
    required this.forecastEndUtc,
    required this.trace,
    this.parameterSetId,
    this.issue,
  });

  final DryingPredictionStatus status;
  final DateTime startTimeUtc;
  final DateTime? completionTimeUtc;
  final Duration? duration;
  final MoistureState finalState;
  final int numberOfSteps;
  final DateTime? forecastEndUtc;
  final List<ForecastDryingStepResult> trace;
  final String? parameterSetId;
  final ForecastDryingIssueV2? issue;
}
