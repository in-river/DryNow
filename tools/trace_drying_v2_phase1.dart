// ignore_for_file: avoid_print

import 'package:weather_app/drying_v2/drying_estimator_v2.dart';
import 'package:weather_app/drying_v2/drying_model_v2_config.dart';
import 'package:weather_app/drying_v2/garment_profile.dart';
import 'package:weather_app/drying_v2/moisture_state.dart';

const _sanityParameterSetId = 'sanity-check-phase1';

const _config = DryingModelV2Config(
  hmNaturalMs: 0.001,
  hmForcedMaxMs: 0.001,
  windScaleMs: 0.5,
);

const _cottonTest = GarmentProfile(
  id: 'cottonTest',
  fiberKind: FiberKind.cotton,
  dryMassKg: 0.1,
  effectiveAreaM2: 0.4,
  initialMoistureRatio: 0.8,
  criticalMoistureRatio: 0.4,
  targetMoistureRatio: 0.1,
  fallingRateConstantPerSecond: 0.000018,
);

const _polyesterTest = GarmentProfile(
  id: 'polyesterTest',
  fiberKind: FiberKind.polyester,
  dryMassKg: 0.1,
  effectiveAreaM2: 0.4,
  initialMoistureRatio: 0.8,
  criticalMoistureRatio: 0.4,
  targetMoistureRatio: 0.1,
  fallingRateConstantPerSecond: 0.000018,
);

final class _CaseDefinition {
  const _CaseDefinition({
    required this.name,
    required this.profile,
    required this.condition,
    required this.xeq,
    required this.xeqSource,
  });

  final String name;
  final GarmentProfile profile;
  final ConstantDryingCondition condition;
  final double xeq;
  final String xeqSource;
}

final class _CaseRun {
  const _CaseRun({
    required this.definition,
    required this.estimate,
    required this.diagnosticInitialStep,
  });

  final _CaseDefinition definition;
  final DryingEstimateV2 estimate;
  final DryingStepResult diagnosticInitialStep;

  DryingStepResult get firstStep => diagnosticInitialStep;

  DryingStepResult? get lastStep =>
      estimate.trace.isEmpty ? null : estimate.trace.last;

  DryingStepResult? get criticalCrossing {
    for (final step in estimate.trace) {
      if (step.phaseBefore == DryingPhase.constantRate &&
          step.phaseAfter == DryingPhase.fallingRate) {
        return step;
      }
    }
    return null;
  }
}

void main() {
  final estimator = DryingEstimatorV2(config: _config);
  final literatureCotton95 = _config.prototypeEquilibriumMoistureRatio(
    FiberKind.cotton,
    95,
  );
  final literaturePolyester95 = _config.prototypeEquilibriumMoistureRatio(
    FiberKind.polyester,
    95,
  );

  final caseA = _run(
    estimator,
    const _CaseDefinition(
      name: 'Case A: standard condition',
      profile: _cottonTest,
      condition: (
        airTemperatureC: 25,
        relativeHumidityPct: 60,
        windSpeedMs: 0.5,
      ),
      xeq: 0.05,
      xeqSource: 'explicit sanity fixture (not literature)',
    ),
  );
  final caseB = _run(
    estimator,
    _CaseDefinition(
      name: 'Case B: high humidity cotton',
      profile: _cottonTest,
      condition: const (
        airTemperatureC: 25,
        relativeHumidityPct: 95,
        windSpeedMs: 0.5,
      ),
      xeq: literatureCotton95,
      xeqSource: '${DryingModelV2Config.parameterSetId} at RH95',
    ),
  );
  final caseC = _run(
    estimator,
    _CaseDefinition(
      name: 'Case C: high humidity PES',
      profile: _polyesterTest,
      condition: const (
        airTemperatureC: 25,
        relativeHumidityPct: 95,
        windSpeedMs: 0.5,
      ),
      xeq: literaturePolyester95,
      xeqSource: '${DryingModelV2Config.parameterSetId} at RH95',
    ),
  );
  final caseD = _run(
    estimator,
    const _CaseDefinition(
      name: 'Case D: zero forecast wind',
      profile: _cottonTest,
      condition: (airTemperatureC: 25, relativeHumidityPct: 60, windSpeedMs: 0),
      xeq: 0.05,
      xeqSource: 'explicit sanity fixture (not literature)',
    ),
  );

  final windRuns = <_CaseRun>[
    for (final wind in const [0.0, 0.2, 0.5, 1.0])
      _run(
        estimator,
        _CaseDefinition(
          name: 'Case E: wind $wind m/s',
          profile: _cottonTest,
          condition: (
            airTemperatureC: 25,
            relativeHumidityPct: 60,
            windSpeedMs: wind,
          ),
          xeq: 0.05,
          xeqSource: 'explicit sanity fixture (not literature)',
        ),
      ),
  ];

  const rhFixtures = <({double rh, double xeq})>[
    (rh: 40, xeq: 0.025),
    (rh: 60, xeq: 0.05),
    (rh: 80, xeq: 0.075),
    (rh: 95, xeq: 0.09),
  ];
  final rhRuns = <_CaseRun>[
    for (final fixture in rhFixtures)
      _run(
        estimator,
        _CaseDefinition(
          name: 'Case F: RH ${fixture.rh.toStringAsFixed(0)}%',
          profile: _cottonTest,
          condition: (
            airTemperatureC: 25,
            relativeHumidityPct: fixture.rh,
            windSpeedMs: 0.5,
          ),
          xeq: fixture.xeq,
          xeqSource: 'explicit RH-comparison fixture (not literature)',
        ),
      ),
  ];

  print('DryNow v2 Phase 1 sanity check');
  print('parameterSetId: $_sanityParameterSetId');
  print(
    'Profiles are artificial diagnostic fixtures, not calibrated garments.',
  );
  print('Integration step: ${_config.integrationStep.inMinutes} min');

  for (final run in [caseA, caseB, caseC, caseD]) {
    _printCase(run);
  }
  _printWindComparison(windRuns);
  _printRhComparison(rhRuns);
  _printMaterialComparison([caseB, caseC]);

  final warnings = <String>[
    ..._checkIndividualRuns({
      caseA,
      caseB,
      caseC,
      caseD,
      ...windRuns,
      ...rhRuns,
    }),
    ..._checkWindRelationship(windRuns),
    ..._checkRhRelationship(rhRuns),
  ];

  print('\n=== Sanity warnings ===');
  if (warnings.isEmpty) {
    print('No WARNING detected.');
  } else {
    for (final warning in warnings) {
      print('WARNING: $warning');
    }
  }
}

_CaseRun _run(DryingEstimatorV2 estimator, _CaseDefinition definition) {
  final result = estimator.estimate(
    profile: definition.profile,
    condition: definition.condition,
    equilibriumMoistureRatio: definition.xeq,
  );
  // equilibriumLimitedが即時確定するケースでも、恒率期の初期診断値は
  // Estimator本体から取得する。ツール側へ計算式は複製しない。
  final initialStep = result.trace.isNotEmpty
      ? result.trace.first
      : estimator
            .estimate(
              profile: definition.profile,
              condition: definition.condition,
              equilibriumMoistureRatio: 0,
            )
            .trace
            .first;
  return _CaseRun(
    definition: definition,
    estimate: result,
    diagnosticInitialStep: initialStep,
  );
}

void _printCase(_CaseRun run) {
  final definition = run.definition;
  final profile = definition.profile;
  final condition = definition.condition;
  final crossing = run.criticalCrossing;
  final total = run.estimate.duration;
  final constantDuration = crossing?.endElapsed;
  final fallingDuration = total == null || constantDuration == null
      ? null
      : total - constantDuration;

  print('\n=== ${definition.name} ===');
  print('material: ${profile.fiberKind.name} (${profile.id})');
  print(
    'condition: ${condition.airTemperatureC.toStringAsFixed(1)} C, '
    'RH ${condition.relativeHumidityPct.toStringAsFixed(1)}%, '
    'wind ${condition.windSpeedMs.toStringAsFixed(1)} m/s',
  );
  print(
    'X0=${_fixed(profile.initialMoistureRatio)}, '
    'Xc=${_fixed(profile.criticalMoistureRatio)}, '
    'Xeq=${_fixed(definition.xeq)}, '
    'Xtarget=${_fixed(profile.targetMoistureRatio)}',
  );
  print('Xeq source: ${definition.xeqSource}');
  print('status: ${run.estimate.status.name}');
  print('total duration: ${_duration(total)}');
  print('constantRate duration: ${_duration(constantDuration)}');
  print('fallingRate duration: ${_duration(fallingDuration)}');
  print('Xc reached: ${_duration(crossing?.endElapsed)}');
  print(
    run.estimate.status == DryingPredictionStatus.completed
        ? 'completion: ${_duration(total)}'
        : 'completion: equilibriumLimited',
  );
  print('initial drying rate: ${_rate(run.firstStep)} 1/s');
  print('final drying rate: ${_rate(run.lastStep)} 1/s');
  print(
    'removed water: '
    '${run.estimate.finalState.removedWaterKg.toStringAsFixed(6)} kg',
  );
  _printTrace(run);
}

void _printTrace(_CaseRun run) {
  print('trace:');
  print(
    'time       phase              X        Xeq      dryingRate    hm        deltaRho',
  );
  if (run.estimate.trace.isEmpty) {
    final first = run.firstStep;
    print(
      '0:00       ${run.estimate.finalState.phase.name.padRight(18)} '
      '${_fixed(run.definition.profile.initialMoistureRatio)}  '
      '${_fixed(run.definition.xeq)}  '
      '${first.dryingRatePerSecond.toStringAsExponential(4).padRight(13)} '
      '${first.massTransferVelocityMs.toStringAsExponential(3).padRight(9)} '
      '${first.vaporDensityDifferenceKgM3.toStringAsExponential(3)}',
    );
    return;
  }

  final first = run.firstStep;
  print(
    '${_duration(Duration.zero).padRight(10)} '
    '${first.phaseBefore.name.padRight(18)} '
    '${_fixed(first.xBefore)}  ${_fixed(first.xeq)}  '
    '${first.dryingRatePerSecond.toStringAsExponential(4).padRight(13)} '
    '${first.massTransferVelocityMs.toStringAsExponential(3).padRight(9)} '
    '${first.vaporDensityDifferenceKgM3.toStringAsExponential(3)}',
  );

  final totalHours = run.estimate.finalState.elapsed.inHours;
  final sampleIntervalHours = totalHours <= 12
      ? 1
      : totalHours <= 36
      ? 3
      : 6;
  final selected = <int>{run.estimate.trace.length - 1};
  for (var index = 0; index < run.estimate.trace.length; index++) {
    final step = run.estimate.trace[index];
    final minutes = step.endElapsed.inMinutes;
    if (minutes > 0 && minutes % (sampleIntervalHours * 60) == 0 ||
        step.phaseBefore != step.phaseAfter) {
      selected.add(index);
    }
  }
  for (final index in selected.toList()..sort()) {
    final step = run.estimate.trace[index];
    print(
      '${_duration(step.endElapsed).padRight(10)} '
      '${step.phaseAfter.name.padRight(18)} '
      '${_fixed(step.xAfter)}  ${_fixed(step.xeq)}  '
      '${step.dryingRatePerSecond.toStringAsExponential(4).padRight(13)} '
      '${step.massTransferVelocityMs.toStringAsExponential(3).padRight(9)} '
      '${step.vaporDensityDifferenceKgM3.toStringAsExponential(3)}',
    );
  }
}

void _printWindComparison(List<_CaseRun> runs) {
  print('\n=== Wind comparison ===');
  print('wind m/s  initial rate  time to Xc  completion  status');
  for (final run in runs) {
    print(
      '${run.definition.condition.windSpeedMs.toStringAsFixed(1).padRight(9)} '
      '${_rate(run.firstStep).padRight(13)} '
      '${_duration(run.criticalCrossing?.endElapsed).padRight(11)} '
      '${_duration(run.estimate.duration).padRight(11)} '
      '${run.estimate.status.name}',
    );
  }
}

void _printRhComparison(List<_CaseRun> runs) {
  print('\n=== RH comparison ===');
  print('RH %  Xeq source      deltaRho    initial rate  completion  status');
  for (final run in runs) {
    print(
      '${run.definition.condition.relativeHumidityPct.toStringAsFixed(0).padRight(5)} '
      '${_fixed(run.definition.xeq).padRight(15)} '
      '${_deltaRho(run.firstStep).padRight(11)} '
      '${_rate(run.firstStep).padRight(13)} '
      '${_duration(run.estimate.duration).padRight(11)} '
      '${run.estimate.status.name}',
    );
  }
  print('All Xeq values in this RH table are explicit sanity fixtures.');
}

void _printMaterialComparison(List<_CaseRun> runs) {
  print('\n=== Cotton vs PES at RH95 ===');
  print('material    Xeq      completion  status');
  for (final run in runs) {
    print(
      '${run.definition.profile.fiberKind.name.padRight(11)} '
      '${_fixed(run.definition.xeq).padRight(8)} '
      '${_duration(run.estimate.duration).padRight(11)} '
      '${run.estimate.status.name}',
    );
  }
  print('Xeq values above use ${DryingModelV2Config.parameterSetId}.');
}

List<String> _checkIndividualRuns(Set<_CaseRun> runs) {
  final warnings = <String>[];
  for (final run in runs) {
    var previousX = run.definition.profile.initialMoistureRatio;
    for (final step in run.estimate.trace) {
      final values = [
        step.xBefore,
        step.xAfter,
        step.xeq,
        step.dryingRatePerSecond,
        step.massTransferVelocityMs,
        step.vaporDensityDifferenceKgM3,
        step.removedWaterKg,
      ];
      if (values.any((value) => !value.isFinite)) {
        warnings.add('${run.definition.name}: NaN or Infinity detected');
        break;
      }
      if (step.xAfter > previousX + _config.numericEpsilon) {
        warnings.add('${run.definition.name}: X increased');
      }
      if (step.xAfter < step.xeq - _config.numericEpsilon) {
        warnings.add('${run.definition.name}: X fell below Xeq');
      }
      previousX = step.xAfter;
    }
    if (run.estimate.status == DryingPredictionStatus.completed &&
        run.criticalCrossing == null) {
      warnings.add('${run.definition.name}: Xc phase transition missing');
    }
    final crossing = run.criticalCrossing;
    if (crossing != null) {
      final crossingIndex = run.estimate.trace.indexOf(crossing);
      if (crossingIndex + 1 < run.estimate.trace.length) {
        final firstFallingRate =
            run.estimate.trace[crossingIndex + 1].dryingRatePerSecond;
        if (firstFallingRate >
            crossing.dryingRatePerSecond + _config.numericEpsilon) {
          warnings.add(
            '${run.definition.name}: drying rate increased at Xc transition',
          );
        }
      }
    }
    final duration = run.estimate.duration;
    if (duration != null &&
        duration.inMicroseconds % _config.integrationStep.inMicroseconds == 0) {
      warnings.add(
        '${run.definition.name}: completion is exactly on a step boundary',
      );
    }
  }
  return warnings;
}

List<String> _checkWindRelationship(List<_CaseRun> runs) {
  final warnings = <String>[];
  for (var index = 1; index < runs.length; index++) {
    final previous = runs[index - 1].firstStep;
    final current = runs[index].firstStep;
    if (current.dryingRatePerSecond + _config.numericEpsilon <
        previous.dryingRatePerSecond) {
      warnings.add('wind increase reduced the initial drying rate');
    }
  }
  final slopes = <double>[];
  for (var index = 1; index < runs.length; index++) {
    final windDelta =
        runs[index].definition.condition.windSpeedMs -
        runs[index - 1].definition.condition.windSpeedMs;
    final rateDelta =
        runs[index].firstStep.dryingRatePerSecond -
        runs[index - 1].firstStep.dryingRatePerSecond;
    slopes.add(rateDelta / windDelta);
  }
  for (var index = 1; index < slopes.length; index++) {
    if (slopes[index] > slopes[index - 1] + _config.numericEpsilon) {
      warnings.add('wind response did not show a saturation tendency');
      break;
    }
  }
  return warnings;
}

List<String> _checkRhRelationship(List<_CaseRun> runs) {
  final warnings = <String>[];
  for (var index = 1; index < runs.length; index++) {
    if (runs[index].firstStep.dryingRatePerSecond >
        runs[index - 1].firstStep.dryingRatePerSecond +
            _config.numericEpsilon) {
      warnings.add('RH increase raised the initial drying rate');
    }
  }
  return warnings;
}

String _rate(DryingStepResult? step) =>
    step == null ? 'n/a' : step.dryingRatePerSecond.toStringAsExponential(4);

String _deltaRho(DryingStepResult? step) => step == null
    ? 'n/a'
    : step.vaporDensityDifferenceKgM3.toStringAsExponential(3);

String _fixed(double value) => value.toStringAsFixed(4);

String _duration(Duration? duration) {
  if (duration == null) return 'n/a';
  final totalSeconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return '$hours:${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toStringAsFixed(1).padLeft(4, '0')}';
}
