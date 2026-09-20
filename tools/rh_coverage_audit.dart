import 'package:weather_app/drying_v2/forecast_step_cursor.dart';
import 'package:weather_app/models/weather.dart';

enum RhCoverageBand { belowSupported, supported, aboveSupported }

final class RhCoverageCount {
  const RhCoverageCount({required this.count, required this.ratio});

  final int count;
  final double ratio;
}

final class RhCoverageDuration {
  const RhCoverageDuration({required this.duration, required this.ratio});

  final Duration duration;
  final double ratio;
}

final class UnsupportedRhInterval {
  const UnsupportedRhInterval({
    required this.startTimeUtc,
    required this.endTimeUtc,
    required this.band,
    required this.minimumRh,
    required this.maximumRh,
  });

  final DateTime startTimeUtc;
  final DateTime endTimeUtc;
  final RhCoverageBand band;
  final double minimumRh;
  final double maximumRh;
}

final class RhCoverageAudit {
  const RhCoverageAudit({
    required this.forecastStartUtc,
    required this.forecastEndUtc,
    required this.hourlyPointCount,
    required this.minimumRh,
    required this.maximumRh,
    required this.meanRh,
    required this.medianRh,
    required this.pointCoverage,
    required this.timeCoverage,
    required this.unsupportedIntervals,
    required this.firstUnsupportedTimeUtc,
    required this.firstUnsupportedRh,
    required this.firstUnsupportedBand,
  });

  final DateTime forecastStartUtc;
  final DateTime forecastEndUtc;
  final int hourlyPointCount;
  final double minimumRh;
  final double maximumRh;
  final double meanRh;
  final double medianRh;
  final Map<RhCoverageBand, RhCoverageCount> pointCoverage;
  final Map<RhCoverageBand, RhCoverageDuration> timeCoverage;
  final List<UnsupportedRhInterval> unsupportedIntervals;
  final DateTime? firstUnsupportedTimeUtc;
  final double? firstUnsupportedRh;
  final RhCoverageBand? firstUnsupportedBand;
}

RhCoverageAudit auditRhCoverage(
  ForecastSeries series, {
  Duration step = const Duration(minutes: 5),
  double minimumSupportedRh = 65,
  double maximumSupportedRh = 95,
}) {
  if (minimumSupportedRh > maximumSupportedRh) {
    throw ArgumentError('RH support範囲の上下限が逆です。');
  }
  final humidities = <double>[];
  for (final point in series.forecasts) {
    final rh = point.humidity;
    if (rh == null || !rh.isFinite || rh < 0 || rh > 100) {
      throw const FormatException('hourly RHが欠損または不正です。');
    }
    humidities.add(rh);
  }
  if (humidities.length < 2) {
    throw const FormatException('RH coverageには2点以上必要です。');
  }

  final pointCounts = {for (final band in RhCoverageBand.values) band: 0};
  for (final rh in humidities) {
    final band = _band(rh, minimumSupportedRh, maximumSupportedRh);
    pointCounts[band] = pointCounts[band]! + 1;
  }

  final cursor = ForecastStepCursor(
    series: series,
    startTimeUtc: series.forecasts.first.forecastTimeUtc,
    integrationStep: step,
  );
  final durationMicros = {for (final band in RhCoverageBand.values) band: 0};
  final unsupported = <UnsupportedRhInterval>[];
  DateTime? firstUnsupportedTime;
  double? firstUnsupportedRh;
  RhCoverageBand? firstUnsupportedBand;
  _MutableUnsupportedInterval? currentUnsupported;

  while (cursor.hasNext) {
    final forecastStep = cursor.next();
    final rh = forecastStep.relativeHumidityPct;
    final band = _band(rh, minimumSupportedRh, maximumSupportedRh);
    durationMicros[band] =
        durationMicros[band]! +
        forecastStep.endTimeUtc
            .difference(forecastStep.startTimeUtc)
            .inMicroseconds;
    if (band == RhCoverageBand.supported) {
      if (currentUnsupported != null) {
        unsupported.add(currentUnsupported.freeze());
        currentUnsupported = null;
      }
      continue;
    }
    firstUnsupportedTime ??= forecastStep.startTimeUtc;
    firstUnsupportedRh ??= rh;
    firstUnsupportedBand ??= band;
    if (currentUnsupported == null || currentUnsupported.band != band) {
      if (currentUnsupported != null) {
        unsupported.add(currentUnsupported.freeze());
      }
      currentUnsupported = _MutableUnsupportedInterval(
        startTimeUtc: forecastStep.startTimeUtc,
        endTimeUtc: forecastStep.endTimeUtc,
        band: band,
        minimumRh: rh,
        maximumRh: rh,
      );
    } else {
      currentUnsupported.add(forecastStep.endTimeUtc, rh);
    }
  }
  if (currentUnsupported != null) unsupported.add(currentUnsupported.freeze());

  final sorted = [...humidities]..sort();
  final median = sorted.length.isOdd
      ? sorted[sorted.length ~/ 2]
      : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
  final totalMicros = durationMicros.values.reduce((a, b) => a + b);
  return RhCoverageAudit(
    forecastStartUtc: series.forecasts.first.forecastTimeUtc,
    forecastEndUtc: series.forecasts.last.forecastTimeUtc,
    hourlyPointCount: humidities.length,
    minimumRh: sorted.first,
    maximumRh: sorted.last,
    meanRh: humidities.reduce((a, b) => a + b) / humidities.length,
    medianRh: median,
    pointCoverage: {
      for (final band in RhCoverageBand.values)
        band: RhCoverageCount(
          count: pointCounts[band]!,
          ratio: pointCounts[band]! / humidities.length,
        ),
    },
    timeCoverage: {
      for (final band in RhCoverageBand.values)
        band: RhCoverageDuration(
          duration: Duration(microseconds: durationMicros[band]!),
          ratio: durationMicros[band]! / totalMicros,
        ),
    },
    unsupportedIntervals: List.unmodifiable(unsupported),
    firstUnsupportedTimeUtc: firstUnsupportedTime,
    firstUnsupportedRh: firstUnsupportedRh,
    firstUnsupportedBand: firstUnsupportedBand,
  );
}

RhCoverageBand _band(double rh, double minimum, double maximum) {
  if (rh < minimum) return RhCoverageBand.belowSupported;
  if (rh > maximum) return RhCoverageBand.aboveSupported;
  return RhCoverageBand.supported;
}

final class _MutableUnsupportedInterval {
  _MutableUnsupportedInterval({
    required this.startTimeUtc,
    required this.endTimeUtc,
    required this.band,
    required this.minimumRh,
    required this.maximumRh,
  });

  final DateTime startTimeUtc;
  DateTime endTimeUtc;
  final RhCoverageBand band;
  double minimumRh;
  double maximumRh;

  void add(DateTime end, double rh) {
    endTimeUtc = end;
    if (rh < minimumRh) minimumRh = rh;
    if (rh > maximumRh) maximumRh = rh;
  }

  UnsupportedRhInterval freeze() => UnsupportedRhInterval(
    startTimeUtc: startTimeUtc,
    endTimeUtc: endTimeUtc,
    band: band,
    minimumRh: minimumRh,
    maximumRh: maximumRh,
  );
}
