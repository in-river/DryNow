// ignore_for_file: avoid_print

import 'dart:io';

import 'package:weather_app/drying_v2/drying_estimator_v2.dart';
import 'package:weather_app/drying_v2/drying_model_v2_config.dart';
import 'package:weather_app/drying_v2/equilibrium_moisture_model.dart';
import 'package:weather_app/drying_v2/garment_profile.dart';

import 'forecast_snapshot.dart';
import 'rh_coverage_audit.dart';

const _minimumSupportedRh = 65.0;
const _maximumSupportedRh = 95.0;

Future<void> main(List<String> arguments) async {
  final path = arguments.isNotEmpty ? arguments.first : _latestSnapshotPath();
  final snapshot = await loadForecastSnapshot(path);
  final audit = auditRhCoverage(snapshot.series);
  final offset = snapshot.series.locationUtcOffset!;

  print('snapshot=${File(path).absolute.path}');
  print('source=${snapshot.source}');
  print(
    'location=${snapshot.series.cityName} '
    'requested=${snapshot.requestedLatitude},${snapshot.requestedLongitude} '
    'returned=${snapshot.series.latitude},${snapshot.series.longitude}',
  );
  print('fetched_at_utc=${snapshot.fetchedAtUtc.toIso8601String()}');
  print('fetched_at_local=${snapshot.fetchedAtLocalIso8601}');
  print('timezone=${snapshot.series.timezone}');
  print('forecast_start_local=${_local(audit.forecastStartUtc, offset)}');
  print('forecast_end_local=${_local(audit.forecastEndUtc, offset)}');
  print('hourly_points=${audit.hourlyPointCount}');
  print('rh_min=${_number(audit.minimumRh)}');
  print('rh_max=${_number(audit.maximumRh)}');
  print('rh_mean=${_number(audit.meanRh)}');
  print('rh_median=${_number(audit.medianRh)}');

  print('\nPOINT COVERAGE');
  for (final band in RhCoverageBand.values) {
    final coverage = audit.pointCoverage[band]!;
    print(
      '${_bandName(band)}: points=${coverage.count}, '
      'ratio=${_percent(coverage.ratio)}',
    );
  }

  print('\n5-MINUTE TIME COVERAGE');
  for (final band in RhCoverageBand.values) {
    final coverage = audit.timeCoverage[band]!;
    print(
      '${_bandName(band)}: hours=${_hours(coverage.duration)}, '
      'ratio=${_percent(coverage.ratio)}',
    );
  }

  print('\nUNSUPPORTED INTERVALS');
  if (audit.unsupportedIntervals.isEmpty) {
    print('none');
  } else {
    for (final interval in audit.unsupportedIntervals) {
      print(
        '${_local(interval.startTimeUtc, offset)} - '
        '${_local(interval.endTimeUtc, offset)} '
        'RH=${_number(interval.minimumRh)}..${_number(interval.maximumRh)} '
        '${_bandName(interval.band)}',
      );
    }
  }

  print('\nPHASE 3 INPUT CHECK');
  for (final material in [FiberKind.cotton, FiberKind.polyester]) {
    final result =
        DryingEstimatorV2(
          config: const DryingModelV2Config(
            hmNaturalMs: 0.001,
            hmForcedMaxMs: 0.001,
            windScaleMs: 0.5,
          ),
        ).estimateForecastWithEquilibriumModel(
          series: snapshot.series,
          profile: _auditProfile(material),
          startTimeUtc: snapshot.forecastStartUtc,
          equilibriumMoistureModel: const TabulatedEquilibriumMoistureModel(),
        );
    final issue = result.issue;
    print(
      '${material.name}: status=${result.status.name}, '
      'first_unsupported_local='
      '${issue == null ? 'none' : _local(issue.timeUtc, offset)}, '
      'rh=${issue?.relativeHumidityPct}, reason=${issue?.reason}',
    );
  }

  print('\nREQUIRED XEQ RANGE');
  print('required=${_number(audit.minimumRh)}..${_number(audit.maximumRh)}%');
  print('current=$_minimumSupportedRh..$_maximumSupportedRh%');
  print(
    'missing_below=${audit.minimumRh < _minimumSupportedRh ? '${_number(audit.minimumRh)}..$_minimumSupportedRh%' : 'none'}',
  );
  print(
    'missing_above=${audit.maximumRh > _maximumSupportedRh ? '$_maximumSupportedRh..${_number(audit.maximumRh)}%' : 'none'}',
  );
}

GarmentProfile _auditProfile(FiberKind material) => GarmentProfile(
  id: 'rh-coverage-audit-${material.name}',
  fiberKind: material,
  dryMassKg: 1,
  effectiveAreaM2: 1e-9,
  initialMoistureRatio: 0.8,
  criticalMoistureRatio: 0.4,
  targetMoistureRatio: 0.001,
  fallingRateConstantPerSecond: 1e-9,
);

String _latestSnapshotPath() {
  final directory = Directory('tools/forecast_snapshots');
  if (!directory.existsSync()) {
    throw StateError('forecast snapshotがありません。先にcaptureツールを実行してください。');
  }
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.json'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
  if (files.isEmpty) throw StateError('forecast snapshot JSONがありません。');
  return files.first.path;
}

String _bandName(RhCoverageBand band) => switch (band) {
  RhCoverageBand.belowSupported => 'RH < 65%',
  RhCoverageBand.supported => '65% <= RH <= 95%',
  RhCoverageBand.aboveSupported => 'RH > 95%',
};

String _number(double value) => value.toStringAsFixed(2);
String _percent(double value) => '${(value * 100).toStringAsFixed(2)}%';
String _hours(Duration value) =>
    (value.inMicroseconds / Duration.microsecondsPerHour).toStringAsFixed(2);

String _local(DateTime utc, Duration offset) {
  final value = utc.add(offset);
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
