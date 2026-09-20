import 'dart:io';

import 'package:weather_app/drying_advice.dart';
import 'package:weather_app/drying_estimator.dart';
import 'package:weather_app/models/drying_environment.dart';
import 'package:weather_app/weather_api.dart';

// 春日部のモデル診断専用。API値と計算途中だけを標準出力へ出し、保存しない。
Future<void> main(List<String> arguments) async {
  String? requested;
  for (final value in arguments) {
    if (value.startsWith('--start-local=')) {
      requested = value.substring('--start-local='.length);
    }
  }
  final api = WeatherApi();
  try {
    final response = await api.fetchHourlyForecastByCoordinates(
      35.9795,
      139.7523,
      cityName: '春日部',
    );
    final offset = response.series.locationUtcOffset;
    if (offset == null || response.series.forecasts.isEmpty) {
      throw StateError('地点の時差または時間別予報がありません。');
    }
    final firstLocal = response.series.forecasts.first.forecastTimeUtc.add(
      offset,
    );
    final parsed = requested == null ? null : DateTime.parse(requested);
    final localStart = parsed == null
        ? DateTime.utc(firstLocal.year, firstLocal.month, firstLocal.day, 15)
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
          );
    final start = localStart.subtract(offset);
    const environment = DryingEnvironment(
      roofProtection: false,
      dryingPlace: DryingPlace.openBalcony,
      windExposure: WindExposure.good,
      sunExposurePattern: SunExposurePattern.allDay,
    );
    final estimator = DryingEstimator();
    final estimates = estimator.estimateDryingTime(
      series: response.series,
      environment: environment,
      startTime: start,
    );
    final trace = estimator.traceDrying(
      series: response.series,
      environment: environment,
      startTime: start,
    );
    String local(DateTime value) => value.toUtc().add(offset).toIso8601String();
    String number(double value) => value.toStringAsFixed(4);
    stdout.writeln('start_local=${local(start)}');
    stdout.writeln(
      'environment=wind:good,sun:allDay,K=${estimator.config.k},'
      'required:${estimator.config.categories.map((c) => '${c.id}=${c.requiredDrying}').join(',')}',
    );
    stdout.writeln(
      'forecast_time,temperature,humidity,VPD,forecast_wind,effective_wind,'
      'WindFactor,shortwave_radiation,effective_solar,SolarFactor,DryingPower,'
      'interval_DryingAmount,cumulativeDrying',
    );
    for (final row in trace) {
      stdout.writeln(
        [
          local(row.forecastTime),
          number(row.temperature),
          number(row.humidity),
          number(row.vpd),
          number(row.forecastWind),
          number(row.effectiveWind),
          number(row.windFactor),
          number(row.shortwaveRadiation),
          number(row.effectiveSolar),
          number(row.solarFactor),
          number(row.dryingPower),
          number(row.intervalDryingAmount),
          number(row.cumulativeDrying),
        ].join(','),
      );
    }
    for (final estimate in estimates) {
      stdout.writeln(
        '${estimate.category.id}: status=${estimate.status.name}, '
        'minutes=${estimate.estimatedDuration?.inMinutes}, '
        'completion_local=${estimate.estimatedCompletionTime == null ? null : local(estimate.estimatedCompletionTime!)}',
      );
    }
    const wetCodes = {
      51,
      53,
      55,
      56,
      57,
      61,
      63,
      65,
      66,
      67,
      71,
      73,
      75,
      77,
      80,
      81,
      82,
      85,
      86,
      95,
      96,
      99,
    };
    for (final row in response.series.forecasts.where(
      (row) => !row.forecastTimeUtc.isBefore(start),
    )) {
      final triggers =
          (row.precipitationMm != null && row.precipitationMm! > 0) ||
          (row.precipitationProbability != null &&
              row.precipitationProbability! >= 30) ||
          wetCodes.contains(row.weatherCode);
      if (triggers) {
        stdout.writeln(
          'raw_rain_trigger: forecast_time=${local(row.forecastTimeUtc)}, '
          'precipitation=${row.precipitationMm}, '
          'probability=${row.precipitationProbability}, '
          'weatherCode=${row.weatherCode}',
        );
      }
    }
    final risks = DryingAdvisor().assessWeatherRisks(response.series.forecasts);
    for (final risk in risks.where((risk) => !risk.endTime.isBefore(start))) {
      stdout.writeln(
        'risk: kind=${risk.kind.name}, status=${risk.status.name}, '
        'start=${local(risk.riskStartTime)}, end=${local(risk.endTime)}, '
        'source=${local(risk.sourceTime)}, precipitation=${risk.precipitationMm}, '
        'probability=${risk.precipitationProbabilityPct}, '
        'weatherCodes=${risk.weatherCodes}, wind=${risk.windSpeedMs}, '
        'threshold=${risk.windThresholdMs}',
      );
    }
  } finally {
    api.close();
  }
}
