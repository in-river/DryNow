import 'dart:math' as math;

import '../models/weather.dart';
import 'drying_model_v2_config.dart';
import 'equilibrium_moisture_model.dart';
import 'forecast_drying_result_v2.dart';
import 'forecast_step_cursor.dart';
import 'garment_profile.dart';
import 'moisture_state.dart';

typedef ConstantDryingCondition = ({
  double airTemperatureC,
  double relativeHumidityPct,
  double windSpeedMs,
});

typedef ForecastEquilibriumMoistureFixture =
    double Function(ConstantDryingCondition condition, FiberKind fiberKind);

class DryingEstimatorV2 {
  DryingEstimatorV2({required this.config}) {
    _validateConfig();
  }

  static const _waterVaporGasConstant = 461.5;
  static const _minimumTemperatureC = -80.0;
  static const _maximumTemperatureC = 70.0;
  static const _maximumSteps = 1000000;

  final DryingModelV2Config config;

  DryingEstimateV2 estimate({
    required GarmentProfile profile,
    required ConstantDryingCondition condition,
    double? equilibriumMoistureRatio,
  }) {
    _validateProfile(profile);
    _validateCondition(condition);
    final xeq =
        equilibriumMoistureRatio ??
        config.prototypeEquilibriumMoistureRatio(
          profile.fiberKind,
          condition.relativeHumidityPct,
        );
    _validateEquilibriumMoistureRatio(xeq);

    final physics = _dryingPhysics(profile, condition);
    final initialPhase = _phaseFor(
      profile.initialMoistureRatio,
      profile.criticalMoistureRatio,
    );
    final initialState = MoistureState(
      elapsed: Duration.zero,
      moistureRatio: profile.initialMoistureRatio,
      removedWaterKg: 0,
      phase: initialPhase,
    );

    // 一定条件で平衡含水率が実用終点以上なら、終点へは数学的に到達しない。
    if (xeq >= profile.targetMoistureRatio) {
      return (
        status: DryingPredictionStatus.equilibriumLimited,
        duration: null,
        finalState: initialState,
        trace: const [],
      );
    }

    if (physics.constantRatePerSecond <= config.numericEpsilon) {
      final step = config.integrationStep;
      final stalled = MoistureState(
        elapsed: step,
        moistureRatio: profile.initialMoistureRatio,
        removedWaterKg: 0,
        phase: DryingPhase.equilibriumStalled,
      );
      return (
        status: DryingPredictionStatus.equilibriumLimited,
        duration: null,
        finalState: stalled,
        trace: [
          DryingStepResult(
            startElapsed: Duration.zero,
            endElapsed: step,
            xBefore: profile.initialMoistureRatio,
            xAfter: profile.initialMoistureRatio,
            xeq: xeq,
            xc: profile.criticalMoistureRatio,
            phaseBefore: initialPhase,
            phaseAfter: DryingPhase.equilibriumStalled,
            dryingRatePerSecond: 0,
            vaporDensityDifferenceKgM3: physics.vaporDensityDifferenceKgM3,
            massTransferVelocityMs: physics.massTransferVelocityMs,
            removedWaterKg: 0,
            cumulativeRemovedWaterKg: 0,
          ),
        ],
      );
    }

    final trace = <DryingStepResult>[];
    var x = profile.initialMoistureRatio;
    var elapsedSeconds = 0.0;
    var cumulativeRemovedWaterKg = 0.0;
    final stepSeconds = _seconds(config.integrationStep);

    for (var step = 0; step < _maximumSteps; step++) {
      final advanced = _advanceMoisture(
        profile: profile,
        condition: condition,
        xeq: xeq,
        x: x,
        elapsedSeconds: elapsedSeconds,
        cumulativeRemovedWaterKg: cumulativeRemovedWaterKg,
        maximumSeconds: stepSeconds,
        stallWhenTargetBlocked: false,
      );
      trace.addAll(advanced.trace);
      x = advanced.x;
      elapsedSeconds = advanced.elapsedSeconds;
      cumulativeRemovedWaterKg = advanced.cumulativeRemovedWaterKg;
      if (advanced.completed) {
        final duration = _durationFromSeconds(elapsedSeconds);
        return (
          status: DryingPredictionStatus.completed,
          duration: duration,
          finalState: MoistureState(
            elapsed: duration,
            moistureRatio: x,
            removedWaterKg: cumulativeRemovedWaterKg,
            phase: DryingPhase.completed,
          ),
          trace: List.unmodifiable(trace),
        );
      }
    }
    throw StateError('乾燥計算が安全上限ステップ数を超えました。');
  }

  ForecastDryingEstimateV2 estimateForecast({
    required ForecastSeries series,
    required GarmentProfile profile,
    required DateTime startTimeUtc,
    required ForecastEquilibriumMoistureFixture
    equilibriumMoistureRatioForCondition,
  }) => _estimateForecastCore(
    series: series,
    profile: profile,
    startTimeUtc: startTimeUtc,
    resolveXeq: (condition) => _XeqResolution.supported(
      equilibriumMoistureRatioForCondition(condition, profile.fiberKind),
    ),
    classifyEquilibriumLimit: false,
    parameterSetId: null,
  );

  ForecastDryingEstimateV2 estimateForecastWithEquilibriumModel({
    required ForecastSeries series,
    required GarmentProfile profile,
    required DateTime startTimeUtc,
    required EquilibriumMoistureModel equilibriumMoistureModel,
  }) => _estimateForecastCore(
    series: series,
    profile: profile,
    startTimeUtc: startTimeUtc,
    resolveXeq: (condition) {
      final result = equilibriumMoistureModel.equilibriumMoistureRatio(
        temperatureC: condition.airTemperatureC,
        relativeHumidityPct: condition.relativeHumidityPct,
        material: profile.fiberKind,
        cottonFraction: profile.cottonFraction,
        polyesterFraction: profile.polyesterFraction,
      );
      return result.isSupported
          ? _XeqResolution.supported(result.value!)
          : _XeqResolution.unsupported(result.reason!);
    },
    classifyEquilibriumLimit: true,
    parameterSetId: equilibriumMoistureModel.metadata.parameterSetId,
  );

  ForecastDryingEstimateV2 _estimateForecastCore({
    required ForecastSeries series,
    required GarmentProfile profile,
    required DateTime startTimeUtc,
    required _XeqResolution Function(ConstantDryingCondition condition)
    resolveXeq,
    required bool classifyEquilibriumLimit,
    required String? parameterSetId,
  }) {
    _validateProfile(profile);
    final normalizedStartUtc = startTimeUtc.toUtc();
    final initialState = MoistureState(
      elapsed: Duration.zero,
      moistureRatio: profile.initialMoistureRatio,
      removedWaterKg: 0,
      phase: _phaseFor(
        profile.initialMoistureRatio,
        profile.criticalMoistureRatio,
      ),
    );
    final possibleForecastEnd = series.forecasts.isEmpty
        ? null
        : series.forecasts.last.forecastTimeUtc.toUtc();

    ForecastStepCursor cursor;
    try {
      cursor = ForecastStepCursor(
        series: series,
        startTimeUtc: startTimeUtc,
        integrationStep: config.integrationStep,
      );
    } on FormatException {
      return _insufficientForecastResult(
        startTimeUtc: normalizedStartUtc,
        forecastEndUtc: possibleForecastEnd,
        finalState: initialState,
        parameterSetId: parameterSetId,
      );
    }

    final trace = <ForecastDryingStepResult>[];
    var x = profile.initialMoistureRatio;
    var elapsedSeconds = 0.0;
    var cumulativeRemovedWaterKg = 0.0;
    var numberOfSteps = 0;
    var hadTargetReachableCondition = false;

    try {
      while (cursor.hasNext) {
        final forecastStep = cursor.next();
        final condition = (
          airTemperatureC: forecastStep.temperatureC,
          relativeHumidityPct: forecastStep.relativeHumidityPct,
          windSpeedMs: forecastStep.windSpeedMs,
        );
        _validateCondition(condition);
        final resolution = resolveXeq(condition);
        if (!resolution.isSupported) {
          return _insufficientForecastResult(
            startTimeUtc: normalizedStartUtc,
            forecastEndUtc: cursor.forecastEndUtc,
            finalState: MoistureState(
              elapsed: _durationFromSeconds(elapsedSeconds),
              moistureRatio: x,
              removedWaterKg: cumulativeRemovedWaterKg,
              phase: trace.isEmpty ? initialState.phase : trace.last.phaseAfter,
            ),
            numberOfSteps: numberOfSteps,
            trace: trace,
            parameterSetId: parameterSetId,
            issue: ForecastDryingIssueV2(
              timeUtc: forecastStep.startTimeUtc,
              temperatureC: condition.airTemperatureC,
              relativeHumidityPct: condition.relativeHumidityPct,
              material: profile.fiberKind.name,
              reason: resolution.reason!,
            ),
          );
        }
        final xeq = resolution.value!;
        _validateEquilibriumMoistureRatio(xeq);
        if (xeq < profile.targetMoistureRatio) {
          hadTargetReachableCondition = true;
        }

        final advanced = _advanceMoisture(
          profile: profile,
          condition: condition,
          xeq: xeq,
          x: x,
          elapsedSeconds: elapsedSeconds,
          cumulativeRemovedWaterKg: cumulativeRemovedWaterKg,
          maximumSeconds: _seconds(
            forecastStep.endTimeUtc.difference(forecastStep.startTimeUtc),
          ),
          stallWhenTargetBlocked: !classifyEquilibriumLimit,
        );
        numberOfSteps++;
        for (final moistureStep in advanced.trace) {
          trace.add(
            ForecastDryingStepResult(
              startTimeUtc: normalizedStartUtc.add(moistureStep.startElapsed),
              endTimeUtc: normalizedStartUtc.add(moistureStep.endElapsed),
              temperatureC: condition.airTemperatureC,
              relativeHumidityPct: condition.relativeHumidityPct,
              windSpeedMs: condition.windSpeedMs,
              xBefore: moistureStep.xBefore,
              xAfter: moistureStep.xAfter,
              xeq: moistureStep.xeq,
              phaseBefore: moistureStep.phaseBefore,
              phaseAfter: moistureStep.phaseAfter,
              dryingRatePerSecond: moistureStep.dryingRatePerSecond,
              massTransferVelocityMs: moistureStep.massTransferVelocityMs,
              vaporDensityDifferenceKgM3:
                  moistureStep.vaporDensityDifferenceKgM3,
            ),
          );
        }
        x = advanced.x;
        elapsedSeconds = advanced.elapsedSeconds;
        cumulativeRemovedWaterKg = advanced.cumulativeRemovedWaterKg;

        if (advanced.completed) {
          final duration = _durationFromSeconds(elapsedSeconds);
          return ForecastDryingEstimateV2(
            status: DryingPredictionStatus.completed,
            startTimeUtc: normalizedStartUtc,
            completionTimeUtc: normalizedStartUtc.add(duration),
            duration: duration,
            finalState: MoistureState(
              elapsed: duration,
              moistureRatio: x,
              removedWaterKg: cumulativeRemovedWaterKg,
              phase: DryingPhase.completed,
            ),
            numberOfSteps: numberOfSteps,
            forecastEndUtc: cursor.forecastEndUtc,
            trace: List.unmodifiable(trace),
            parameterSetId: parameterSetId,
          );
        }
      }
    } on FormatException {
      return _insufficientForecastResult(
        startTimeUtc: normalizedStartUtc,
        forecastEndUtc: cursor.forecastEndUtc,
        finalState: MoistureState(
          elapsed: _durationFromSeconds(elapsedSeconds),
          moistureRatio: x,
          removedWaterKg: cumulativeRemovedWaterKg,
          phase: trace.isEmpty ? initialState.phase : trace.last.phaseAfter,
        ),
        numberOfSteps: numberOfSteps,
        trace: trace,
        parameterSetId: parameterSetId,
      );
    } on ArgumentError {
      return _insufficientForecastResult(
        startTimeUtc: normalizedStartUtc,
        forecastEndUtc: cursor.forecastEndUtc,
        finalState: MoistureState(
          elapsed: _durationFromSeconds(elapsedSeconds),
          moistureRatio: x,
          removedWaterKg: cumulativeRemovedWaterKg,
          phase: trace.isEmpty ? initialState.phase : trace.last.phaseAfter,
        ),
        numberOfSteps: numberOfSteps,
        trace: trace,
        parameterSetId: parameterSetId,
      );
    }

    final elapsed = cursor.forecastEndUtc.difference(normalizedStartUtc);
    return ForecastDryingEstimateV2(
      status: classifyEquilibriumLimit && !hadTargetReachableCondition
          ? DryingPredictionStatus.equilibriumLimited
          : DryingPredictionStatus.notCompletedWithinForecast,
      startTimeUtc: normalizedStartUtc,
      completionTimeUtc: null,
      duration: null,
      finalState: MoistureState(
        elapsed: elapsed,
        moistureRatio: x,
        removedWaterKg: cumulativeRemovedWaterKg,
        phase: trace.isEmpty ? initialState.phase : trace.last.phaseAfter,
      ),
      numberOfSteps: numberOfSteps,
      forecastEndUtc: cursor.forecastEndUtc,
      trace: List.unmodifiable(trace),
      parameterSetId: parameterSetId,
    );
  }

  ForecastDryingEstimateV2 _insufficientForecastResult({
    required DateTime startTimeUtc,
    required DateTime? forecastEndUtc,
    required MoistureState finalState,
    int numberOfSteps = 0,
    List<ForecastDryingStepResult> trace = const [],
    String? parameterSetId,
    ForecastDryingIssueV2? issue,
  }) => ForecastDryingEstimateV2(
    status: DryingPredictionStatus.insufficientData,
    startTimeUtc: startTimeUtc,
    completionTimeUtc: null,
    duration: null,
    finalState: finalState,
    numberOfSteps: numberOfSteps,
    forecastEndUtc: forecastEndUtc,
    trace: List.unmodifiable(trace),
    parameterSetId: parameterSetId,
    issue: issue,
  );

  _MoistureAdvance _advanceMoisture({
    required GarmentProfile profile,
    required ConstantDryingCondition condition,
    required double xeq,
    required double x,
    required double elapsedSeconds,
    required double cumulativeRemovedWaterKg,
    required double maximumSeconds,
    required bool stallWhenTargetBlocked,
  }) {
    final physics = _dryingPhysics(profile, condition);
    final trace = <DryingStepResult>[];
    var currentX = x;
    var currentElapsedSeconds = elapsedSeconds;
    var cumulativeRemoved = cumulativeRemovedWaterKg;

    if ((stallWhenTargetBlocked && xeq >= profile.targetMoistureRatio) ||
        xeq >= currentX - config.numericEpsilon ||
        physics.constantRatePerSecond <= config.numericEpsilon) {
      final phaseBefore = _phaseFor(currentX, profile.criticalMoistureRatio);
      final endSeconds = currentElapsedSeconds + maximumSeconds;
      trace.add(
        DryingStepResult(
          startElapsed: _durationFromSeconds(currentElapsedSeconds),
          endElapsed: _durationFromSeconds(endSeconds),
          xBefore: currentX,
          xAfter: currentX,
          xeq: xeq,
          xc: profile.criticalMoistureRatio,
          phaseBefore: phaseBefore,
          phaseAfter: DryingPhase.equilibriumStalled,
          dryingRatePerSecond: 0,
          vaporDensityDifferenceKgM3: physics.vaporDensityDifferenceKgM3,
          massTransferVelocityMs: physics.massTransferVelocityMs,
          removedWaterKg: 0,
          cumulativeRemovedWaterKg: cumulativeRemoved,
        ),
      );
      return _MoistureAdvance(
        x: currentX,
        elapsedSeconds: endSeconds,
        cumulativeRemovedWaterKg: cumulativeRemoved,
        completed: false,
        trace: trace,
      );
    }

    var remainingSeconds = maximumSeconds;
    while (remainingSeconds > config.numericEpsilon) {
      if (xeq >= currentX - config.numericEpsilon) {
        final phaseBefore = _phaseFor(currentX, profile.criticalMoistureRatio);
        final endSeconds = currentElapsedSeconds + remainingSeconds;
        trace.add(
          DryingStepResult(
            startElapsed: _durationFromSeconds(currentElapsedSeconds),
            endElapsed: _durationFromSeconds(endSeconds),
            xBefore: currentX,
            xAfter: currentX,
            xeq: xeq,
            xc: profile.criticalMoistureRatio,
            phaseBefore: phaseBefore,
            phaseAfter: DryingPhase.equilibriumStalled,
            dryingRatePerSecond: 0,
            vaporDensityDifferenceKgM3: physics.vaporDensityDifferenceKgM3,
            massTransferVelocityMs: physics.massTransferVelocityMs,
            removedWaterKg: 0,
            cumulativeRemovedWaterKg: cumulativeRemoved,
          ),
        );
        currentElapsedSeconds = endSeconds;
        remainingSeconds = 0;
        break;
      }
      final phaseBefore = _phaseFor(currentX, profile.criticalMoistureRatio);
      final xBefore = currentX;
      final startSeconds = currentElapsedSeconds;
      late double segmentSeconds;
      late DryingPhase phaseAfter;
      var completed = false;

      if (phaseBefore == DryingPhase.constantRate) {
        final boundary = math.max(profile.criticalMoistureRatio, xeq);
        final secondsToBoundary =
            (currentX - boundary) / physics.constantRatePerSecond;
        if (secondsToBoundary <= remainingSeconds) {
          segmentSeconds = math.max(0, secondsToBoundary);
          currentX = boundary;
          phaseAfter = boundary > profile.criticalMoistureRatio
              ? DryingPhase.equilibriumStalled
              : DryingPhase.fallingRate;
        } else {
          segmentSeconds = remainingSeconds;
          currentX -= physics.constantRatePerSecond * segmentSeconds;
          phaseAfter = DryingPhase.constantRate;
        }
      } else {
        final k2 = profile.fallingRateConstantPerSecond;
        if (xeq >= profile.targetMoistureRatio) {
          segmentSeconds = remainingSeconds;
          currentX = xeq + (currentX - xeq) * math.exp(-k2 * segmentSeconds);
          if (currentX < xeq) currentX = xeq;
          phaseAfter = currentX <= xeq + config.numericEpsilon
              ? DryingPhase.equilibriumStalled
              : DryingPhase.fallingRate;
        } else {
          final ratio = (profile.targetMoistureRatio - xeq) / (currentX - xeq);
          final secondsToTarget = -math.log(ratio) / k2;
          if (secondsToTarget <= remainingSeconds) {
            segmentSeconds = math.max(0, secondsToTarget);
            currentX = profile.targetMoistureRatio;
            phaseAfter = DryingPhase.completed;
            completed = true;
          } else {
            segmentSeconds = remainingSeconds;
            currentX = xeq + (currentX - xeq) * math.exp(-k2 * segmentSeconds);
            if (currentX < xeq) currentX = xeq;
            phaseAfter = DryingPhase.fallingRate;
          }
        }
      }

      if (segmentSeconds <= config.numericEpsilon) {
        if (phaseAfter == DryingPhase.fallingRate) {
          currentX = profile.criticalMoistureRatio;
          continue;
        }
        throw StateError('乾燥状態を進められません。');
      }

      currentElapsedSeconds += segmentSeconds;
      remainingSeconds -= segmentSeconds;
      final removedWaterKg = (xBefore - currentX) * profile.dryMassKg;
      cumulativeRemoved += removedWaterKg;
      trace.add(
        DryingStepResult(
          startElapsed: _durationFromSeconds(startSeconds),
          endElapsed: _durationFromSeconds(currentElapsedSeconds),
          xBefore: xBefore,
          xAfter: currentX,
          xeq: xeq,
          xc: profile.criticalMoistureRatio,
          phaseBefore: phaseBefore,
          phaseAfter: phaseAfter,
          dryingRatePerSecond: (xBefore - currentX) / segmentSeconds,
          vaporDensityDifferenceKgM3: physics.vaporDensityDifferenceKgM3,
          massTransferVelocityMs: physics.massTransferVelocityMs,
          removedWaterKg: removedWaterKg,
          cumulativeRemovedWaterKg: cumulativeRemoved,
        ),
      );

      if (completed) {
        return _MoistureAdvance(
          x: currentX,
          elapsedSeconds: currentElapsedSeconds,
          cumulativeRemovedWaterKg: cumulativeRemoved,
          completed: true,
          trace: trace,
        );
      }
    }
    return _MoistureAdvance(
      x: currentX,
      elapsedSeconds: currentElapsedSeconds,
      cumulativeRemovedWaterKg: cumulativeRemoved,
      completed: false,
      trace: trace,
    );
  }

  ({
    double massTransferVelocityMs,
    double vaporDensityDifferenceKgM3,
    double constantRatePerSecond,
  })
  _dryingPhysics(GarmentProfile profile, ConstantDryingCondition condition) {
    final hm = _massTransferVelocity(condition.windSpeedMs);
    final deltaRho = _vaporDensityDifference(condition);
    final constantRate =
        profile.effectiveAreaM2 / profile.dryMassKg * hm * deltaRho;
    if (!constantRate.isFinite || constantRate < 0) {
      throw StateError('恒率乾燥速度が不正です。');
    }
    return (
      massTransferVelocityMs: hm,
      vaporDensityDifferenceKgM3: deltaRho,
      constantRatePerSecond: constantRate,
    );
  }

  DryingPhase _phaseFor(double x, double xc) =>
      x > xc ? DryingPhase.constantRate : DryingPhase.fallingRate;

  double _massTransferVelocity(double windSpeedMs) =>
      config.hmNaturalMs +
      config.hmForcedMaxMs * (1 - math.exp(-windSpeedMs / config.windScaleMs));

  double _vaporDensityDifference(ConstantDryingCondition condition) {
    final temperatureK = condition.airTemperatureC + 273.15;
    final saturationPressure = _saturationVaporPressurePa(
      condition.airTemperatureC,
    );
    final airPressure =
        condition.relativeHumidityPct / 100 * saturationPressure;
    final saturatedDensity =
        saturationPressure / (_waterVaporGasConstant * temperatureK);
    final airDensity = airPressure / (_waterVaporGasConstant * temperatureK);
    return math.max(0, saturatedDensity - airDensity);
  }

  double _saturationVaporPressurePa(double temperatureC) =>
      610.94 * math.exp(17.625 * temperatureC / (temperatureC + 243.04));

  double _seconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerSecond;

  Duration _durationFromSeconds(double seconds) => Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );

  void _validateConfig() {
    _requirePositive(config.hmNaturalMs, 'hmNaturalMs');
    _requireNonnegative(config.hmForcedMaxMs, 'hmForcedMaxMs');
    _requirePositive(config.windScaleMs, 'windScaleMs');
    _requirePositive(config.numericEpsilon, 'numericEpsilon');
    if (config.integrationStep <= Duration.zero) {
      throw ArgumentError.value(
        config.integrationStep,
        'integrationStep',
        '正の時間が必要です。',
      );
    }
  }

  void _validateProfile(GarmentProfile profile) {
    if (profile.id.isEmpty) {
      throw ArgumentError.value(profile.id, 'profile.id', '空文字は使えません。');
    }
    _requirePositive(profile.dryMassKg, 'dryMassKg');
    _requirePositive(profile.effectiveAreaM2, 'effectiveAreaM2');
    _requirePositive(profile.initialMoistureRatio, 'initialMoistureRatio');
    _requirePositive(profile.criticalMoistureRatio, 'criticalMoistureRatio');
    _requireNonnegative(profile.targetMoistureRatio, 'targetMoistureRatio');
    _requirePositive(
      profile.fallingRateConstantPerSecond,
      'fallingRateConstantPerSecond',
    );
    if (profile.initialMoistureRatio <= profile.criticalMoistureRatio) {
      throw ArgumentError('X0はXcより大きい必要があります。');
    }
    if (profile.criticalMoistureRatio <= profile.targetMoistureRatio) {
      throw ArgumentError('XcはXtargetより大きい必要があります。');
    }
    if (profile.fiberKind == FiberKind.blend) {
      final cotton = profile.cottonFraction;
      final polyester = profile.polyesterFraction;
      if (cotton == null ||
          polyester == null ||
          !cotton.isFinite ||
          !polyester.isFinite ||
          cotton < 0 ||
          polyester < 0 ||
          (cotton + polyester - 1).abs() > 1e-9) {
        throw ArgumentError(
          'Blend fractions must be finite, nonnegative, and sum to 1.',
        );
      }
    }
  }

  void _validateCondition(ConstantDryingCondition condition) {
    final temperature = condition.airTemperatureC;
    if (!temperature.isFinite ||
        temperature < _minimumTemperatureC ||
        temperature > _maximumTemperatureC) {
      throw ArgumentError.value(
        temperature,
        'airTemperatureC',
        '$_minimumTemperatureC〜$_maximumTemperatureC℃が必要です。',
      );
    }
    final humidity = condition.relativeHumidityPct;
    if (!humidity.isFinite || humidity < 0 || humidity > 100) {
      throw ArgumentError.value(
        humidity,
        'relativeHumidityPct',
        '0〜100%が必要です。',
      );
    }
    _requireNonnegative(condition.windSpeedMs, 'windSpeedMs');
  }

  void _validateEquilibriumMoistureRatio(double value) {
    _requireNonnegative(value, 'equilibriumMoistureRatio');
  }

  void _requirePositive(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, '有限な正の値が必要です。');
    }
  }

  void _requireNonnegative(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(value, name, '有限な0以上の値が必要です。');
    }
  }
}

final class _MoistureAdvance {
  const _MoistureAdvance({
    required this.x,
    required this.elapsedSeconds,
    required this.cumulativeRemovedWaterKg,
    required this.completed,
    required this.trace,
  });

  final double x;
  final double elapsedSeconds;
  final double cumulativeRemovedWaterKg;
  final bool completed;
  final List<DryingStepResult> trace;
}

final class _XeqResolution {
  const _XeqResolution.supported(this.value)
    : isSupported = true,
      reason = null;

  const _XeqResolution.unsupported(this.reason)
    : isSupported = false,
      value = null;

  final bool isSupported;
  final double? value;
  final String? reason;
}
