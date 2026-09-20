// ignore_for_file: avoid_print

import 'package:weather_app/drying_v2/drying_estimator_v2.dart';
import 'package:weather_app/drying_v2/drying_model_v2_config.dart';
import 'package:weather_app/drying_v2/equilibrium_moisture_model.dart';
import 'package:weather_app/drying_v2/forecast_drying_result_v2.dart';
import 'package:weather_app/drying_v2/garment_profile.dart';
import 'package:weather_app/drying_v2/moisture_state.dart';
import 'package:weather_app/models/weather.dart';

final _start = DateTime.utc(2026, 9, 19, 12);
const _xeqModel = TabulatedEquilibriumMoistureModel();
const _config = DryingModelV2Config(
  hmNaturalMs: 0.001,
  hmForcedMaxMs: 0.001,
  windScaleMs: 0.5,
);

double _rhAtHour(int hour) {
  const anchors = <(int, double)>[
    (0, 65),
    (6, 65),
    (12, 95),
    (18, 90),
    (24, 65),
  ];
  for (var index = 1; index < anchors.length; index++) {
    final lower = anchors[index - 1];
    final upper = anchors[index];
    if (hour <= upper.$1) {
      final fraction = (hour - lower.$1) / (upper.$1 - lower.$1);
      return lower.$2 + fraction * (upper.$2 - lower.$2);
    }
  }
  return anchors.last.$2;
}

ForecastSeries _forecast() => ForecastSeries(
  cityName: 'Phase 3 synthetic forecast',
  forecasts: [
    for (var hour = 0; hour <= 24; hour++)
      HourlyForecast(
        forecastTimeUtc: _start.add(Duration(hours: hour)),
        temperature: 25,
        humidity: _rhAtHour(hour),
        windSpeed: 0.5,
      ),
  ],
  locationUtcOffset: Duration.zero,
  timezone: 'UTC',
);

GarmentProfile _profile(FiberKind material) => GarmentProfile(
  id: 'phase3-diagnostic-${material.name}',
  fiberKind: material,
  dryMassKg: 0.1,
  effectiveAreaM2: 0.4,
  initialMoistureRatio: 0.4,
  criticalMoistureRatio: 0.25,
  targetMoistureRatio: 0.02,
  fallingRateConstantPerSecond: 0.00003,
);

ForecastDryingEstimateV2 _run(FiberKind material) =>
    DryingEstimatorV2(config: _config).estimateForecastWithEquilibriumModel(
      series: _forecast(),
      profile: _profile(material),
      startTimeUtc: _start,
      equilibriumMoistureModel: _xeqModel,
    );

String _time(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}/'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _candidate(ForecastDryingStepResult step, double target) {
  if (step.phaseAfter == DryingPhase.completed) return 'completed';
  if (step.xeq >= target) return 'equilibrium-limited';
  return 'target-reachable';
}

Iterable<ForecastDryingStepResult> _sample(
  List<ForecastDryingStepResult> trace,
) sync* {
  for (var index = 0; index < trace.length; index++) {
    final step = trace[index];
    final previous = index == 0 ? null : trace[index - 1];
    final phaseChanged =
        previous != null && previous.phaseAfter != step.phaseAfter;
    final onHour = step.endTimeUtc.minute == 0;
    if (index == 0 || index == trace.length - 1 || phaseChanged || onHour) {
      yield step;
    }
  }
}

void _printResult(FiberKind material, ForecastDryingEstimateV2 result) {
  final profile = _profile(material);
  print('\n=== ${material.name.toUpperCase()} ===');
  print(
    'status=${result.status.name}, finalX='
    '${result.finalState.moistureRatio.toStringAsFixed(5)}, '
    'steps=${result.numberOfSteps}',
  );
  print(
    'time        RH    material   X        Xeq      phase                rate/s       candidate',
  );
  for (final step in _sample(result.trace)) {
    print(
      '${_time(step.endTimeUtc).padRight(11)} '
      '${step.relativeHumidityPct.toStringAsFixed(1).padLeft(5)} '
      '${material.name.padRight(10)} '
      '${step.xAfter.toStringAsFixed(5).padLeft(8)} '
      '${step.xeq.toStringAsFixed(5).padLeft(8)} '
      '${step.phaseAfter.name.padRight(20)} '
      '${step.dryingRatePerSecond.toStringAsExponential(3).padLeft(11)} '
      '${_candidate(step, profile.targetMoistureRatio)}',
    );
  }
}

List<String> _warnings(
  ForecastDryingEstimateV2 cotton,
  ForecastDryingEstimateV2 polyester,
) {
  final warnings = <String>[];
  for (final result in [cotton, polyester]) {
    if (result.trace.any(
      (step) =>
          !step.xAfter.isFinite ||
          !step.xeq.isFinite ||
          !step.dryingRatePerSecond.isFinite,
    )) {
      warnings.add('NaNまたはInfinityを検出しました。');
    }
    if (result.trace.any((step) => step.xAfter > step.xBefore + 1e-12)) {
      warnings.add('Xの増加（再吸湿）を検出しました。');
    }
  }
  final pairs = cotton.trace.length < polyester.trace.length
      ? cotton.trace.length
      : polyester.trace.length;
  for (var index = 0; index < pairs; index++) {
    if (cotton.trace[index].xeq <= polyester.trace[index].xeq) {
      warnings.add('cotton XeqがPES以下になる区間を検出しました。');
      break;
    }
  }
  return warnings;
}

void main() {
  final cotton = _run(FiberKind.cotton);
  final polyester = _run(FiberKind.polyester);
  final metadata = _xeqModel.metadata;

  print('DryNow v2 Phase 3 diagnostic trace');
  print('parameterSetId=${metadata.parameterSetId}');
  print('source=${metadata.source}');
  print(
    'RH nodes=${metadata.relativeHumidityNodesPct}, basis=${metadata.basis}',
  );
  print('temperature=${metadata.temperatureCondition}');
  print('prototype=${metadata.isPrototype}');

  _printResult(FiberKind.cotton, cotton);
  _printResult(FiberKind.polyester, polyester);

  print('\n=== MATERIAL SUMMARY ===');
  print('material    minXeq   maxXeq   stalled steps  status');
  for (final entry in [
    (FiberKind.cotton, cotton),
    (FiberKind.polyester, polyester),
  ]) {
    final xeqs = entry.$2.trace.map((step) => step.xeq).toList();
    xeqs.sort();
    final stalled = entry.$2.trace
        .where((step) => step.phaseAfter == DryingPhase.equilibriumStalled)
        .length;
    print(
      '${entry.$1.name.padRight(11)} '
      '${xeqs.first.toStringAsFixed(5).padLeft(8)} '
      '${xeqs.last.toStringAsFixed(5).padLeft(8)} '
      '${stalled.toString().padLeft(13)}  '
      '${entry.$2.status.name}',
    );
  }

  final warnings = _warnings(cotton, polyester);
  if (warnings.isEmpty) {
    print('\nWARNING: none');
  } else {
    for (final warning in warnings) {
      print('\nWARNING: $warning');
    }
  }
  print(
    '\nThis trace checks structure and direction only; it is not calibrated.',
  );
}
