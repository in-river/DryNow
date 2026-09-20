import 'dart:convert';
import 'dart:io';

import 'package:weather_app/models/weather.dart';

const forecastSnapshotSchemaVersion = 1;

final class ForecastSnapshot {
  ForecastSnapshot({
    required this.source,
    required this.requestedLatitude,
    required this.requestedLongitude,
    required this.fetchedAtUtc,
    required this.series,
    required this.rawOpenMeteoResponse,
  }) {
    _validate();
  }

  final String source;
  final double requestedLatitude;
  final double requestedLongitude;
  final DateTime fetchedAtUtc;
  final ForecastSeries series;
  final Map<String, dynamic> rawOpenMeteoResponse;

  String get fetchedAtLocalIso8601 =>
      _formatWithOffset(fetchedAtUtc, series.locationUtcOffset!);
  DateTime get forecastStartUtc => series.forecasts.first.forecastTimeUtc;
  DateTime get forecastEndUtc => series.forecasts.last.forecastTimeUtc;

  Map<String, dynamic> toJson() => {
    'schemaVersion': forecastSnapshotSchemaVersion,
    'source': source,
    'requestedLatitude': requestedLatitude,
    'requestedLongitude': requestedLongitude,
    'returnedLatitude': series.latitude,
    'returnedLongitude': series.longitude,
    'cityName': series.cityName,
    'timezone': series.timezone,
    'utcOffsetSeconds': series.locationUtcOffset!.inSeconds,
    'fetchedAtUtc': fetchedAtUtc.toIso8601String(),
    'fetchedAtLocal': fetchedAtLocalIso8601,
    'forecastStartUtc': forecastStartUtc.toIso8601String(),
    'forecastEndUtc': forecastEndUtc.toIso8601String(),
    'hourly': [for (final point in series.forecasts) _pointToJson(point)],
    'rawOpenMeteoResponse': rawOpenMeteoResponse,
  };

  factory ForecastSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != forecastSnapshotSchemaVersion) {
      throw const FormatException('未対応のforecast snapshot形式です。');
    }
    final hourly = json['hourly'];
    final raw = json['rawOpenMeteoResponse'];
    if (hourly is! List || raw is! Map<String, dynamic>) {
      throw const FormatException('snapshotのhourlyまたはrawレスポンスが不正です。');
    }
    final offsetSeconds = _requiredInt(json['utcOffsetSeconds']);
    final snapshot = ForecastSnapshot(
      source: _requiredString(json['source']),
      requestedLatitude: _requiredDouble(json['requestedLatitude']),
      requestedLongitude: _requiredDouble(json['requestedLongitude']),
      fetchedAtUtc: _requiredUtc(json['fetchedAtUtc']),
      series: ForecastSeries(
        cityName: _requiredString(json['cityName']),
        latitude: _nullableDouble(json['returnedLatitude']),
        longitude: _nullableDouble(json['returnedLongitude']),
        forecasts: [
          for (final value in hourly)
            _pointFromJson(_requiredMap(value, 'hourly point')),
        ],
        locationUtcOffset: Duration(seconds: offsetSeconds),
        timezone: _requiredString(json['timezone']),
      ),
      rawOpenMeteoResponse: Map<String, dynamic>.from(raw),
    );
    if (_requiredUtc(json['forecastStartUtc']) != snapshot.forecastStartUtc ||
        _requiredUtc(json['forecastEndUtc']) != snapshot.forecastEndUtc ||
        _requiredString(json['fetchedAtLocal']) !=
            snapshot.fetchedAtLocalIso8601) {
      throw const FormatException('snapshotのメタデータとhourly内容が一致しません。');
    }
    return snapshot;
  }

  void _validate() {
    if (source.trim().isEmpty ||
        !requestedLatitude.isFinite ||
        !requestedLongitude.isFinite ||
        requestedLatitude.abs() > 90 ||
        requestedLongitude.abs() > 180 ||
        !fetchedAtUtc.isUtc) {
      throw const FormatException('snapshotメタデータが不正です。');
    }
    final offset = series.locationUtcOffset;
    if (offset == null ||
        offset.abs() > const Duration(hours: 14) ||
        series.timezone == null ||
        series.timezone!.isEmpty ||
        series.forecasts.length < 2) {
      throw const FormatException('timezoneまたはforecast点数が不正です。');
    }
    DateTime? previous;
    for (final point in series.forecasts) {
      if (!point.forecastTimeUtc.isUtc ||
          (previous != null && !point.forecastTimeUtc.isAfter(previous))) {
        throw const FormatException('hourly時刻がUTC昇順ではありません。');
      }
      previous = point.forecastTimeUtc;
    }
  }
}

Future<ForecastSnapshot> loadForecastSnapshot(String path) async {
  final decoded = jsonDecode(await File(path).readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('snapshot JSONのルートが不正です。');
  }
  return ForecastSnapshot.fromJson(decoded);
}

Future<void> saveForecastSnapshotImmutable(
  ForecastSnapshot snapshot,
  String path,
) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.create(exclusive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
    flush: true,
  );
}

Map<String, dynamic> decodeRawOpenMeteoResponse(String rawJson) {
  final decoded = jsonDecode(rawJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Open-Meteo raw JSONが不正です。');
  }
  return decoded;
}

Map<String, dynamic> _pointToJson(HourlyForecast point) => {
  'timeUtc': point.forecastTimeUtc.toIso8601String(),
  'temperatureC': point.temperature,
  'relativeHumidityPct': point.humidity,
  'windSpeedMs': point.windSpeed,
  'shortwaveRadiationWm2': point.solarRadiation,
  'precipitationMm': point.precipitationMm,
  'precipitationProbabilityPct': point.precipitationProbability,
  'weatherCode': point.weatherCode,
};

HourlyForecast _pointFromJson(Map<String, dynamic> json) => HourlyForecast(
  forecastTimeUtc: _requiredUtc(json['timeUtc']),
  temperature: _nullableDouble(json['temperatureC']),
  humidity: _nullableDouble(json['relativeHumidityPct']),
  windSpeed: _nullableDouble(json['windSpeedMs']),
  solarRadiation: _nullableDouble(json['shortwaveRadiationWm2']),
  precipitationMm: _nullableDouble(json['precipitationMm']),
  precipitationProbability: _nullableDouble(
    json['precipitationProbabilityPct'],
  ),
  weatherCode: json['weatherCode'] == null
      ? null
      : _requiredInt(json['weatherCode']),
);

Map<String, dynamic> _requiredMap(dynamic value, String name) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$nameがJSON objectではありません。');
  }
  return value;
}

String _requiredString(dynamic value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('必須文字列が欠損しています。');
  }
  return value;
}

double _requiredDouble(dynamic value) {
  final result = _nullableDouble(value);
  if (result == null) throw const FormatException('必須数値が不正です。');
  return result;
}

double? _nullableDouble(dynamic value) =>
    value is num && value.isFinite ? value.toDouble() : null;

int _requiredInt(dynamic value) {
  if (value is! num || !value.isFinite || value != value.truncateToDouble()) {
    throw const FormatException('必須整数が不正です。');
  }
  return value.toInt();
}

DateTime _requiredUtc(dynamic value) {
  final result = _requiredDateTime(value);
  if (!result.isUtc) throw const FormatException('UTC時刻が必要です。');
  return result;
}

DateTime _requiredDateTime(dynamic value) {
  if (value is! String) throw const FormatException('日時が欠損しています。');
  final result = DateTime.tryParse(value);
  if (result == null) throw const FormatException('日時形式が不正です。');
  return result;
}

String _formatWithOffset(DateTime utc, Duration offset) {
  final local = utc.add(offset);
  String two(int value) => value.toString().padLeft(2, '0');
  final sign = offset.isNegative ? '-' : '+';
  final absoluteMinutes = offset.inMinutes.abs();
  final offsetText =
      '$sign${two(absoluteMinutes ~/ 60)}:${two(absoluteMinutes % 60)}';
  return '${local.year.toString().padLeft(4, '0')}-'
      '${two(local.month)}-${two(local.day)}T${two(local.hour)}:'
      '${two(local.minute)}:${two(local.second)}.'
      '${local.millisecond.toString().padLeft(3, '0')}$offsetText';
}
