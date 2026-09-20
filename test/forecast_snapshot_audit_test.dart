import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/models/weather.dart';

import '../tools/forecast_snapshot.dart';
import '../tools/rh_coverage_audit.dart';

final _start = DateTime.utc(2026, 9, 20, 0);

HourlyForecast _point(int hour, double rh) => HourlyForecast(
  forecastTimeUtc: _start.add(Duration(hours: hour)),
  temperature: 25 + hour.toDouble(),
  humidity: rh,
  windSpeed: 1 + hour.toDouble(),
  solarRadiation: hour * 10,
  precipitationMm: hour / 10,
  precipitationProbability: hour * 20,
  weatherCode: hour,
);

ForecastSeries _series(List<double> humidity) => ForecastSeries(
  cityName: '春日部市',
  latitude: 36,
  longitude: 139.75,
  forecasts: [
    for (var index = 0; index < humidity.length; index++)
      _point(index, humidity[index]),
  ],
  locationUtcOffset: const Duration(hours: 9),
  timezone: 'Asia/Tokyo',
);

ForecastSnapshot _snapshot() => ForecastSnapshot(
  source: 'open-meteo',
  requestedLatitude: 35.9795,
  requestedLongitude: 139.7523,
  fetchedAtUtc: DateTime.utc(2026, 9, 20, 1, 2, 3, 456),
  series: _series([64, 65, 95, 96]),
  rawOpenMeteoResponse: const {
    'latitude': 36,
    'longitude': 139.75,
    'hourly': <String, dynamic>{},
  },
);

void main() {
  group('forecast snapshot', () {
    test('serializeとdeserializeでメタデータを保持する', () {
      final restored = ForecastSnapshot.fromJson(_snapshot().toJson());
      expect(restored.source, 'open-meteo');
      expect(restored.requestedLatitude, 35.9795);
      expect(restored.requestedLongitude, 139.7523);
      expect(restored.fetchedAtUtc, DateTime.utc(2026, 9, 20, 1, 2, 3, 456));
      expect(restored.fetchedAtLocalIso8601, '2026-09-20T10:02:03.456+09:00');
    });

    test('ForecastSeriesとtimezoneを再構築する', () {
      final restored = ForecastSnapshot.fromJson(_snapshot().toJson());
      expect(restored.series.cityName, '春日部市');
      expect(restored.series.timezone, 'Asia/Tokyo');
      expect(restored.series.locationUtcOffset, const Duration(hours: 9));
      expect(restored.series.latitude, 36);
      expect(restored.series.longitude, 139.75);
    });

    test('hourly pointの全対象項目を保持する', () {
      final restored = ForecastSnapshot.fromJson(_snapshot().toJson());
      final point = restored.series.forecasts[2];
      expect(point.forecastTimeUtc, _start.add(const Duration(hours: 2)));
      expect(point.temperature, 27);
      expect(point.humidity, 95);
      expect(point.windSpeed, 3);
      expect(point.solarRadiation, 20);
      expect(point.precipitationMm, 0.2);
      expect(point.precipitationProbability, 40);
      expect(point.weatherCode, 2);
    });

    test('hourly内容と不一致な期間メタデータを拒否する', () {
      final json = _snapshot().toJson();
      json['forecastEndUtc'] = DateTime.utc(2026, 9, 21).toIso8601String();
      expect(() => ForecastSnapshot.fromJson(json), throwsFormatException);
    });
  });

  group('RH coverage', () {
    test('min max mean medianとpoint割合を計算する', () {
      final audit = auditRhCoverage(_series([64, 65, 95, 96]));
      expect(audit.minimumRh, 64);
      expect(audit.maximumRh, 96);
      expect(audit.meanRh, 80);
      expect(audit.medianRh, 80);
      expect(audit.pointCoverage[RhCoverageBand.belowSupported]!.count, 1);
      expect(audit.pointCoverage[RhCoverageBand.supported]!.count, 2);
      expect(audit.pointCoverage[RhCoverageBand.aboveSupported]!.count, 1);
      expect(
        audit.pointCoverage[RhCoverageBand.supported]!.ratio,
        closeTo(0.5, 1e-12),
      );
    });

    test('65%と95%の境界をsupportedに含める', () {
      final audit = auditRhCoverage(_series([65, 65, 95, 95]));
      expect(audit.pointCoverage[RhCoverageBand.supported]!.count, 4);
      expect(
        audit.timeCoverage[RhCoverageBand.supported]!.duration,
        const Duration(hours: 3),
      );
      expect(audit.unsupportedIntervals, isEmpty);
    });

    test('5分補間の時間割合を計算する', () {
      final audit = auditRhCoverage(_series([64, 65, 95, 96]));
      expect(
        audit.timeCoverage[RhCoverageBand.belowSupported]!.duration,
        const Duration(hours: 1),
      );
      expect(
        audit.timeCoverage[RhCoverageBand.supported]!.duration,
        const Duration(hours: 1),
      );
      expect(
        audit.timeCoverage[RhCoverageBand.aboveSupported]!.duration,
        const Duration(hours: 1),
      );
      expect(
        audit.timeCoverage[RhCoverageBand.supported]!.ratio,
        closeTo(1 / 3, 1e-12),
      );
    });

    test('同じ側のunsupported stepを連続区間へ結合する', () {
      final audit = auditRhCoverage(_series([60, 60, 70, 97, 97]));
      expect(audit.unsupportedIntervals, hasLength(2));
      expect(audit.unsupportedIntervals.first.startTimeUtc, _start);
      expect(
        audit.unsupportedIntervals.first.endTimeUtc,
        _start.add(const Duration(hours: 1, minutes: 30)),
      );
      expect(
        audit.unsupportedIntervals.first.band,
        RhCoverageBand.belowSupported,
      );
      expect(
        audit.unsupportedIntervals.last.startTimeUtc,
        _start.add(const Duration(hours: 2, minutes: 55)),
      );
      expect(
        audit.unsupportedIntervals.last.endTimeUtc,
        _start.add(const Duration(hours: 4)),
      );
      expect(
        audit.unsupportedIntervals.last.band,
        RhCoverageBand.aboveSupported,
      );
    });

    test('日付跨ぎでもUTC期間と5分coverageを維持する', () {
      final start = DateTime.utc(2026, 9, 20, 23);
      final series = ForecastSeries(
        cityName: '春日部市',
        forecasts: [
          HourlyForecast(
            forecastTimeUtc: start,
            temperature: 25,
            humidity: 64,
            windSpeed: 1,
          ),
          HourlyForecast(
            forecastTimeUtc: start.add(const Duration(hours: 1)),
            temperature: 24,
            humidity: 64,
            windSpeed: 1,
          ),
        ],
        locationUtcOffset: const Duration(hours: 9),
        timezone: 'Asia/Tokyo',
      );
      final audit = auditRhCoverage(series);
      expect(audit.forecastEndUtc.day, 21);
      expect(
        audit.timeCoverage[RhCoverageBand.belowSupported]!.duration,
        const Duration(hours: 1),
      );
    });
  });
}
