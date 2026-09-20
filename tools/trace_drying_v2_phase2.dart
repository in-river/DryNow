// ignore_for_file: avoid_print

import 'package:weather_app/drying_v2/drying_estimator_v2.dart';
import 'package:weather_app/drying_v2/drying_model_v2_config.dart';
import 'package:weather_app/drying_v2/forecast_drying_result_v2.dart';
import 'package:weather_app/drying_v2/garment_profile.dart';
import 'package:weather_app/drying_v2/moisture_state.dart';
import 'package:weather_app/models/weather.dart';

const _locationOffset = Duration(hours: 9);
final _startUtc = DateTime.utc(2026, 9, 19, 3); // 地点時刻12:00

const _profile = GarmentProfile(
  id: 'phase2SyntheticCotton',
  fiberKind: FiberKind.cotton,
  dryMassKg: 0.1,
  effectiveAreaM2: 0.4,
  initialMoistureRatio: 0.8,
  criticalMoistureRatio: 0.4,
  targetMoistureRatio: 0.1,
  fallingRateConstantPerSecond: 0.000018,
);

const _config = DryingModelV2Config(
  hmNaturalMs: 0.001,
  hmForcedMaxMs: 0.001,
  windScaleMs: 0.5,
);

const _anchors = <({int hour, double temperature, double rh, double wind})>[
  (hour: 0, temperature: 25, rh: 60, wind: 0.5),
  (hour: 6, temperature: 23, rh: 75, wind: 0.2),
  (hour: 12, temperature: 20, rh: 95, wind: 0.1),
  (hour: 18, temperature: 21, rh: 70, wind: 0.4),
  (hour: 24, temperature: 26, rh: 55, wind: 0.8),
];

void main() {
  final series = ForecastSeries(
    cityName: 'Phase 2 synthetic forecast',
    forecasts: _buildHourlyForecast(),
    locationUtcOffset: _locationOffset,
    timezone: 'Asia/Tokyo',
  );
  final result = DryingEstimatorV2(config: _config).estimateForecast(
    series: series,
    profile: _profile,
    startTimeUtc: _startUtc,
    equilibriumMoistureRatioForCondition: (condition, fiberKind) {
      // Phase 3のXeqモデルではなく、高湿度停止を確認する明示fixture。
      return condition.relativeHumidityPct >= 90 ? 0.12 : 0.05;
    },
  );

  print('DryNow v2 Phase 2 synthetic forecast trace');
  print('parameterSetId: sanity-check-phase2');
  print('Xeq: RH >= 90% -> 0.12, otherwise -> 0.05 (explicit fixture)');
  print('status: ${result.status.name}');
  print('start UTC: ${result.startTimeUtc.toIso8601String()}');
  print('forecast end UTC: ${result.forecastEndUtc?.toIso8601String()}');
  print(
    'completion UTC: ${result.completionTimeUtc?.toIso8601String() ?? 'n/a'}',
  );
  print('substeps: ${result.numberOfSteps}');
  print('final X: ${result.finalState.moistureRatio.toStringAsFixed(5)}');
  print(
    'removed water: ${result.finalState.removedWaterKg.toStringAsFixed(6)} kg',
  );

  print(
    '\nlocal time        T C    RH %   wind   phase               X        rate 1/s',
  );
  for (final step in _sample(result.trace)) {
    final local = step.endTimeUtc.add(_locationOffset);
    print(
      '${_time(local).padRight(17)} '
      '${step.temperatureC.toStringAsFixed(1).padLeft(5)}  '
      '${step.relativeHumidityPct.toStringAsFixed(1).padLeft(5)}  '
      '${step.windSpeedMs.toStringAsFixed(2).padLeft(5)}  '
      '${step.phaseAfter.name.padRight(19)} '
      '${step.xAfter.toStringAsFixed(5)}  '
      '${step.dryingRatePerSecond.toStringAsExponential(3)}',
    );
  }

  print('\n=== Period checkpoints ===');
  for (final checkpoint in const [6, 12, 18, 24]) {
    final time = _startUtc.add(Duration(hours: checkpoint));
    final step = result.trace.lastWhere(
      (entry) => !entry.endTimeUtc.isAfter(time),
    );
    print(
      '${_time(time.add(_locationOffset))}: '
      'X=${step.xAfter.toStringAsFixed(5)}, '
      'phase=${step.phaseAfter.name}, '
      'rate=${step.dryingRatePerSecond.toStringAsExponential(3)}',
    );
  }

  final warnings = _warnings(result);
  print('\n=== Diagnostic warnings ===');
  if (warnings.isEmpty) {
    print('No WARNING detected.');
  } else {
    for (final warning in warnings) {
      print('WARNING: $warning');
    }
  }
}

List<HourlyForecast> _buildHourlyForecast() => [
  for (var hour = 0; hour <= 24; hour++) _forecastAtHour(hour),
];

HourlyForecast _forecastAtHour(int hour) {
  final rightIndex = _anchors.indexWhere((anchor) => anchor.hour >= hour);
  final right = _anchors[rightIndex];
  final left = right.hour == hour || rightIndex == 0
      ? right
      : _anchors[rightIndex - 1];
  final fraction = right.hour == left.hour
      ? 0.0
      : (hour - left.hour) / (right.hour - left.hour);
  double interpolate(double a, double b) => a + (b - a) * fraction;
  return HourlyForecast(
    forecastTimeUtc: _startUtc.add(Duration(hours: hour)),
    temperature: interpolate(left.temperature, right.temperature),
    humidity: interpolate(left.rh, right.rh),
    windSpeed: interpolate(left.wind, right.wind),
  );
}

List<ForecastDryingStepResult> _sample(List<ForecastDryingStepResult> trace) {
  final indexes = <int>{0, trace.length - 1};
  for (var index = 0; index < trace.length; index++) {
    final step = trace[index];
    final local = step.endTimeUtc.add(_locationOffset);
    final phaseChanged =
        index > 0 && trace[index - 1].phaseAfter != step.phaseAfter;
    if (local.minute == 0 && local.hour % 2 == 0 || phaseChanged) {
      indexes.add(index);
    }
  }
  return [for (final index in indexes.toList()..sort()) trace[index]];
}

List<String> _warnings(ForecastDryingEstimateV2 result) {
  final warnings = <String>[];
  var sawStall = false;
  var sawResume = false;
  for (var index = 0; index < result.trace.length; index++) {
    final step = result.trace[index];
    final values = [
      step.temperatureC,
      step.relativeHumidityPct,
      step.windSpeedMs,
      step.xBefore,
      step.xAfter,
      step.xeq,
      step.dryingRatePerSecond,
    ];
    if (values.any((value) => !value.isFinite)) {
      warnings.add('NaN or Infinity detected');
      break;
    }
    if (step.xAfter > step.xBefore + _config.numericEpsilon) {
      warnings.add('X increased');
    }
    if (step.phaseAfter == DryingPhase.equilibriumStalled) {
      sawStall = true;
      if ((step.xAfter - step.xBefore).abs() > _config.numericEpsilon) {
        warnings.add('X changed during the high-humidity stall');
      }
    } else if (sawStall && step.dryingRatePerSecond > 0) {
      sawResume = true;
    }
  }
  if (!sawStall) warnings.add('high-humidity stall was not observed');
  if (!sawResume) warnings.add('drying did not resume after humidity improved');
  return warnings;
}

String _time(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.month}/${value.day} ${two(value.hour)}:${two(value.minute)}';
}
