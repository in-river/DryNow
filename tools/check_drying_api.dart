import 'dart:convert';
import 'dart:io';

import 'package:weather_app/drying_advice.dart';
import 'package:weather_app/drying_estimator.dart';
import 'package:weather_app/models/drying_environment.dart';
import 'package:weather_app/weather_api.dart';

// 手動検証専用。公開地点へGETのみ行い、DB・raw JSON・設定は保存しない。
Future<void> main() async {
  final api = WeatherApi();
  const environment = DryingEnvironment(
    roofProtection: false,
    dryingPlace: DryingPlace.openBalcony,
    windExposure: WindExposure.good,
    sunExposurePattern: SunExposurePattern.allDay,
  );
  try {
    for (final location in [
      ('春日部', 35.9795, 139.7523),
      ('東京', 35.691667, 139.75),
      ('熊谷', 36.15, 139.38),
    ]) {
      final response = await api.fetchHourlyForecastByCoordinates(
        location.$2,
        location.$3,
        cityName: location.$1,
      );
      final now = DateTime.now().toUtc();
      final rows = response.series.forecasts;
      final upcoming = rows
          .where((r) => r.forecastTimeUtc.isAfter(now))
          .take(6)
          .toList();
      final valid =
          upcoming.length == 6 &&
          upcoming.every(
            (row) =>
                row.temperature != null &&
                row.humidity != null &&
                row.windSpeed != null &&
                row.solarRadiation != null &&
                row.precipitationMm != null &&
                row.precipitationProbability != null &&
                row.weatherCode != null,
          );
      final advice = DryingAdvisor().advise(
        series: response.series,
        environment: environment,
        startTime: now,
        now: now,
        fetchedAt: response.fetchedAt,
      );
      final powers = upcoming
          .map(
            (row) => DryingEstimator().calculateDryingPower(
              row,
              environment,
              response.series.locationUtcOffset ?? Duration.zero,
            ),
          )
          .toList();
      stdout.writeln(
        jsonEncode({
          'city': location.$1,
          'fetchedAt': response.fetchedAt.toIso8601String(),
          'forecastCount': rows.length,
          'timezone': response.series.timezone,
          'offsetSeconds': response.series.locationUtcOffset?.inSeconds,
          'nextSixHoursAllFieldsPresent': valid,
          'nextSixHoursPower': powers,
          'status': advice.overallStatus.name,
          'estimates': advice.garments
              .map(
                (g) => {
                  'category': g.estimate.category.id,
                  'minutes': g.estimate.estimatedDuration?.inMinutes,
                  'completionUtc': g.estimate.estimatedCompletionTime
                      ?.toIso8601String(),
                  'status': g.status.name,
                },
              )
              .toList(),
        }),
      );
      if (!valid ||
          response.series.locationUtcOffset == null ||
          powers.contains(null) ||
          advice.garments.any(
            (g) => g.estimate.status != DryingEstimateStatus.estimated,
          )) {
        exitCode = 1;
      }
    }
  } finally {
    api.close();
  }
}
