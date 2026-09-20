// ignore_for_file: avoid_print

import 'dart:io';

import 'package:weather_app/models/weather_location.dart';
import 'package:weather_app/weather_api.dart';

import 'forecast_snapshot.dart';

Future<void> main(List<String> arguments) async {
  final requestedOutput = _argumentValue(arguments, '--output=');
  const location = WeatherLocation.kasukabe;
  final api = WeatherApi();
  try {
    final response = await api.fetchHourlyForecastByCoordinates(
      location.latitude,
      location.longitude,
      cityName: location.name,
    );
    final snapshot = ForecastSnapshot(
      source: 'open-meteo',
      requestedLatitude: location.latitude,
      requestedLongitude: location.longitude,
      fetchedAtUtc: response.fetchedAt,
      series: response.series,
      rawOpenMeteoResponse: decodeRawOpenMeteoResponse(response.rawJson),
    );
    final path = requestedOutput ?? _defaultPath(snapshot.fetchedAtUtc);
    await saveForecastSnapshotImmutable(snapshot, path);
    print('snapshot_path=${File(path).absolute.path}');
    print('source=${snapshot.source}');
    print(
      'requested=${snapshot.requestedLatitude},${snapshot.requestedLongitude}',
    );
    print('returned=${snapshot.series.latitude},${snapshot.series.longitude}');
    print('fetched_at_utc=${snapshot.fetchedAtUtc.toIso8601String()}');
    print('fetched_at_local=${snapshot.fetchedAtLocalIso8601}');
    print('timezone=${snapshot.series.timezone}');
    print('utc_offset_seconds=${snapshot.series.locationUtcOffset!.inSeconds}');
    print('forecast_start_utc=${snapshot.forecastStartUtc.toIso8601String()}');
    print('forecast_end_utc=${snapshot.forecastEndUtc.toIso8601String()}');
    print('hourly_points=${snapshot.series.forecasts.length}');
    print('immutable=true (existing paths are never overwritten)');
    print(
      'operation=Save a snapshot when a prediction is reviewed; promote only '
      'selected reproducibility fixtures to Git.',
    );
  } finally {
    api.close();
  }
}

String? _argumentValue(List<String> arguments, String prefix) {
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) return argument.substring(prefix.length);
  }
  return null;
}

String _defaultPath(DateTime fetchedAtUtc) {
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp =
      '${fetchedAtUtc.year}${two(fetchedAtUtc.month)}'
      '${two(fetchedAtUtc.day)}_${two(fetchedAtUtc.hour)}'
      '${two(fetchedAtUtc.minute)}${two(fetchedAtUtc.second)}Z';
  return 'tools/forecast_snapshots/kasukabe_open_meteo_$stamp.json';
}
