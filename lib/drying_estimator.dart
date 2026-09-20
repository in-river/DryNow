import 'dart:math' as math;

import 'drying_assessment.dart';
import 'drying_model_config.dart';
import 'models/drying_environment.dart';
import 'models/weather.dart';

// kPa。異常値を丸めず欠損として返し、乾燥完了の誤表示を防ぐ。
double? calculateVpd(double? temperatureC, double? humidityPct) {
  if (temperatureC == null ||
      !temperatureC.isFinite ||
      temperatureC < DryingEvaluator.minimumReasonableTemperatureC ||
      temperatureC > DryingEvaluator.maximumReasonableTemperatureC ||
      humidityPct == null ||
      !humidityPct.isFinite ||
      humidityPct < 0 ||
      humidityPct > 100) {
    return null;
  }
  return 0.6108 *
      math.exp(17.27 * temperatureC / (temperatureC + 237.3)) *
      (1 - humidityPct / 100);
}

enum DryingEstimateStatus { estimated, insufficientData, forecastLimit }

class GarmentDryingEstimate {
  const GarmentDryingEstimate({
    required this.category,
    required this.status,
    this.estimatedDuration,
    this.estimatedCompletionTime,
  });
  final GarmentCategory category;
  final DryingEstimateStatus status;
  final Duration? estimatedDuration;
  final DateTime? estimatedCompletionTime;
}

class DryingTraceEntry {
  const DryingTraceEntry({
    required this.forecastTime,
    required this.intervalStartTime,
    required this.intervalEndTime,
    required this.temperature,
    required this.humidity,
    required this.vpd,
    required this.forecastWind,
    required this.effectiveWind,
    required this.windFactor,
    required this.shortwaveRadiation,
    required this.effectiveSolar,
    required this.solarFactor,
    required this.dryingPower,
    required this.intervalDryingAmount,
    required this.cumulativeDrying,
  });

  final DateTime forecastTime;
  final DateTime intervalStartTime;
  final DateTime intervalEndTime;
  final double temperature;
  final double humidity;
  final double vpd;
  final double forecastWind;
  final double effectiveWind;
  final double windFactor;
  final double shortwaveRadiation;
  final double effectiveSolar;
  final double solarFactor;
  final double dryingPower;
  final double intervalDryingAmount;
  final double cumulativeDrying;
}

class DryingEstimator {
  DryingEstimator({this.config = const DryingModelConfig()}) {
    config.validate();
  }
  final DryingModelConfig config;

  double? calculateEffectiveWind(double? forecastWind, WindExposure exposure) {
    if (forecastWind == null ||
        !forecastWind.isFinite ||
        forecastWind < 0 ||
        forecastWind > DryingEvaluator.maximumReasonableWindSpeedMs) {
      return null;
    }
    return forecastWind * config.windExposure(exposure);
  }

  double? calculateWindFactor(double? wind) =>
      _factor(wind, config.windAmplitude, config.windScale);

  double? calculateEffectiveSolar(
    double? solar,
    SunExposurePattern pattern,
    DateTime locationTime,
  ) {
    if (solar == null ||
        !solar.isFinite ||
        solar < 0 ||
        solar > config.maximumSolarRadiation) {
      return null;
    }
    return solar * config.sunExposure(pattern, locationTime);
  }

  double? calculateSolarFactor(double? solar) =>
      _factor(solar, config.solarAmplitude, config.solarScale);

  double? _factor(double? value, double amplitude, double scale) =>
      value == null || !value.isFinite || value < 0
      ? null
      : 1 + amplitude * (1 - math.exp(-value / scale));

  double? calculateDryingPower(
    HourlyForecast input,
    DryingEnvironment environment,
    Duration locationUtcOffset,
  ) {
    // 単独値の診断用。日射時間窓の中央を代表時刻とし、積分には使用しない。
    final airPower = _calculateAirPower(input, environment);
    final solar = calculateSolarFactor(
      calculateEffectiveSolar(
        input.solarRadiation,
        environment.sunExposurePattern,
        input.forecastTimeUtc
            .toUtc()
            .add(locationUtcOffset)
            .subtract(const Duration(minutes: 30)),
      ),
    );
    if (airPower == null || solar == null) return null;
    final power = _applyProvisionalCalibration(airPower * solar);
    return power.isFinite ? power : null;
  }

  double _applyProvisionalCalibration(double power) =>
      power * config.provisionalDryingCalibrationFactor;

  double? _calculateAirPower(
    HourlyForecast input,
    DryingEnvironment environment,
  ) {
    final vpd = calculateVpd(input.temperature, input.humidity);
    final wind = calculateWindFactor(
      calculateEffectiveWind(input.windSpeed, environment.windExposure),
    );
    if (vpd == null || wind == null) return null;
    final power = config.k * vpd * wind;
    return power.isFinite ? power : null;
  }

  List<DateTime> _sunBoundaries(DateTime from, DateTime to, Duration offset) {
    final local = from.toUtc().add(offset);
    final boundaries = <DateTime>[from, to];
    for (var day = 0; day <= 1; day++) {
      for (final hour in [
        config.dayStartHour,
        config.afternoonStartHour,
        config.dayEndHour,
      ]) {
        final boundary = DateTime.utc(
          local.year,
          local.month,
          local.day + day,
          hour,
        ).subtract(offset);
        if (boundary.isAfter(from) && boundary.isBefore(to)) {
          boundaries.add(boundary);
        }
      }
    }
    return boundaries..sort();
  }

  double integrateDrying(
    double startPower,
    double endPower,
    Duration duration,
  ) {
    if (!startPower.isFinite ||
        !endPower.isFinite ||
        startPower < 0 ||
        endPower < 0 ||
        duration.isNegative) {
      throw ArgumentError('積分区間が不正です。');
    }
    return (startPower + endPower) /
        2 *
        duration.inMicroseconds /
        Duration.microsecondsPerHour;
  }

  List<DryingTraceEntry> traceDrying({
    required ForecastSeries series,
    required DryingEnvironment environment,
    required DateTime startTime,
  }) {
    final rows = series.forecasts;
    final offset = series.locationUtcOffset;
    final start = startTime.toUtc();
    if (offset == null || rows.length < 2) return const [];
    final trace = <DryingTraceEntry>[];
    var cumulative = 0.0;
    for (var i = 0; i < rows.length - 1; i++) {
      final left = rows[i];
      final right = rows[i + 1];
      if (!right.forecastTimeUtc.isAfter(start)) continue;
      final interval = right.forecastTimeUtc.difference(left.forecastTimeUtc);
      final air0 = _calculateAirPower(left, environment);
      final air1 = _calculateAirPower(right, environment);
      final vpd = calculateVpd(right.temperature, right.humidity);
      final effectiveWind = calculateEffectiveWind(
        right.windSpeed,
        environment.windExposure,
      );
      final windFactor = calculateWindFactor(effectiveWind);
      if (interval != const Duration(hours: 1) ||
          air0 == null ||
          air1 == null ||
          right.temperature == null ||
          right.humidity == null ||
          vpd == null ||
          right.windSpeed == null ||
          effectiveWind == null ||
          windFactor == null ||
          right.solarRadiation == null) {
        break;
      }
      final from = left.forecastTimeUtc.isBefore(start)
          ? start
          : left.forecastTimeUtc;
      final boundaries = _sunBoundaries(from, right.forecastTimeUtc, offset);
      for (var part = 0; part < boundaries.length - 1; part++) {
        final segmentStart = boundaries[part];
        final segmentEnd = boundaries[part + 1];
        final effectiveSolar = calculateEffectiveSolar(
          right.solarRadiation,
          environment.sunExposurePattern,
          segmentStart.toUtc().add(offset),
        );
        final solarFactor = calculateSolarFactor(effectiveSolar);
        if (effectiveSolar == null || solarFactor == null) {
          return List.unmodifiable(trace);
        }
        double powerAt(DateTime time) {
          final fraction =
              time.difference(left.forecastTimeUtc).inMicroseconds /
              interval.inMicroseconds;
          return _applyProvisionalCalibration(
            (air0 + (air1 - air0) * fraction) * solarFactor,
          );
        }

        final duration = segmentEnd.difference(segmentStart);
        final amount = integrateDrying(
          powerAt(segmentStart),
          powerAt(segmentEnd),
          duration,
        );
        cumulative += amount;
        final hours = duration.inMicroseconds / Duration.microsecondsPerHour;
        trace.add(
          DryingTraceEntry(
            forecastTime: right.forecastTimeUtc,
            intervalStartTime: segmentStart,
            intervalEndTime: segmentEnd,
            temperature: right.temperature!,
            humidity: right.humidity!,
            vpd: vpd,
            forecastWind: right.windSpeed!,
            effectiveWind: effectiveWind,
            windFactor: windFactor,
            shortwaveRadiation: right.solarRadiation!,
            effectiveSolar: effectiveSolar,
            solarFactor: solarFactor,
            dryingPower: amount / hours,
            intervalDryingAmount: amount,
            cumulativeDrying: cumulative,
          ),
        );
      }
    }
    return List.unmodifiable(trace);
  }

  List<GarmentDryingEstimate> estimateDryingTime({
    required ForecastSeries series,
    required DryingEnvironment environment,
    required DateTime startTime,
  }) {
    final rows = series.forecasts;
    final start = startTime.toUtc();
    final completions = <String, DateTime>{};
    var failure = DryingEstimateStatus.forecastLimit;
    var total = 0.0;
    var covered = start;
    final offset = series.locationUtcOffset;
    final ordered = List.generate(math.max(0, rows.length - 1), (i) => i).every(
      (i) => rows[i + 1].forecastTimeUtc.isAfter(rows[i].forecastTimeUtc),
    );
    if (offset == null ||
        rows.length < 2 ||
        !ordered ||
        start.isBefore(rows.first.forecastTimeUtc) ||
        !start.isBefore(rows.last.forecastTimeUtc)) {
      failure = DryingEstimateStatus.insufficientData;
    } else {
      for (var i = 0; i < rows.length - 1; i++) {
        final left = rows[i];
        final right = rows[i + 1];
        if (!right.forecastTimeUtc.isAfter(start)) continue;
        final interval = right.forecastTimeUtc.difference(left.forecastTimeUtc);
        final air0 = _calculateAirPower(left, environment);
        final air1 = _calculateAirPower(right, environment);
        // 日射は右端時刻の直前1時間平均。別の時間窓を混ぜない。
        if (interval != const Duration(hours: 1) ||
            air0 == null ||
            air1 == null) {
          failure = DryingEstimateStatus.insufficientData;
          break;
        }
        final from = left.forecastTimeUtc.isBefore(start)
            ? start
            : left.forecastTimeUtc;
        if (from.isAfter(covered)) {
          failure = DryingEstimateStatus.insufficientData;
          break;
        }
        final boundaries = _sunBoundaries(from, right.forecastTimeUtc, offset);
        var invalidSolar = false;
        for (var part = 0; part < boundaries.length - 1; part++) {
          final segmentStart = boundaries[part];
          final segmentEnd = boundaries[part + 1];
          final solar = calculateSolarFactor(
            calculateEffectiveSolar(
              right.solarRadiation,
              environment.sunExposurePattern,
              segmentStart.toUtc().add(offset),
            ),
          );
          if (solar == null) {
            invalidSolar = true;
            break;
          }
          double powerAt(DateTime time) {
            final fraction =
                time.difference(left.forecastTimeUtc).inMicroseconds /
                interval.inMicroseconds;
            return _applyProvisionalCalibration(
              (air0 + (air1 - air0) * fraction) * solar,
            );
          }

          final fromPower = powerAt(segmentStart);
          final p1 = powerAt(segmentEnd);
          if (!fromPower.isFinite || !p1.isFinite) {
            invalidSolar = true;
            break;
          }
          final remaining = segmentEnd.difference(segmentStart);
          final amount = integrateDrying(fromPower, p1, remaining);
          for (final category in config.categories) {
            if (completions.containsKey(category.id) ||
                total + amount < category.requiredDrying) {
              continue;
            }
            final needed = category.requiredDrying - total;
            // 線形な乾燥力の積分を逆算する。二分探索でゼロ傾斜にも対応する。
            var low = 0.0;
            var high = 1.0;
            final hours =
                remaining.inMicroseconds / Duration.microsecondsPerHour;
            for (var step = 0; step < 48; step++) {
              final x = (low + high) / 2;
              final area =
                  hours * (fromPower * x + (p1 - fromPower) * x * x / 2);
              if (area < needed) {
                low = x;
              } else {
                high = x;
              }
            }
            completions[category.id] = segmentStart.add(
              Duration(microseconds: (remaining.inMicroseconds * high).round()),
            );
          }
          total += amount;
          if (completions.length == config.categories.length) break;
        }
        if (invalidSolar) {
          failure = DryingEstimateStatus.insufficientData;
          break;
        }
        covered = right.forecastTimeUtc;
        if (completions.length == config.categories.length) break;
      }
    }
    return List.unmodifiable(
      config.categories.map((category) {
        final completion = completions[category.id];
        return GarmentDryingEstimate(
          category: category,
          status: completion == null ? failure : DryingEstimateStatus.estimated,
          estimatedCompletionTime: completion,
          estimatedDuration: completion?.difference(start),
        );
      }),
    );
  }
}
