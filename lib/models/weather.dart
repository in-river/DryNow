import '../drying_assessment.dart';

const _wetWeatherCodes = {
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

double? _number(dynamic value) =>
    value is num && value.isFinite ? value.toDouble() : null;

int? _integer(dynamic value) {
  final number = _number(value);
  return number != null && number == number.truncateToDouble()
      ? number.toInt()
      : null;
}

String _weatherDescription(int? code) => switch (code) {
  0 || 1 => '晴れ',
  2 || 3 => '曇り',
  45 || 48 => '霧',
  51 || 53 || 55 || 56 || 57 => '霧雨',
  61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => '雨',
  71 || 73 || 75 || 77 || 85 || 86 => '雪',
  95 || 96 || 99 => '雷雨',
  _ => '天気状態は不明',
};

String _formatValue(double? value, String unit) =>
    value == null ? '不明' : '${value.toStringAsFixed(1)}$unit';

bool? _precipitationDetected(double? amount, int? weatherCode) {
  if (_wetWeatherCodes.contains(weatherCode)) return true;
  if (amount != null && amount.isFinite && amount >= 0) return amount > 0;
  return null;
}

class Weather {
  final String cityName;
  final double? latitude;
  final double? longitude;
  final DateTime? updatedAtUtc;
  final double? temperature;
  final double? feelsLike;
  final double? humidity;
  final double? windSpeed;
  final double? precipitationMm;
  final int? precipitationIntervalSeconds;
  final int? weatherCode;

  const Weather({
    required this.cityName,
    this.latitude,
    this.longitude,
    this.updatedAtUtc,
    this.temperature,
    this.feelsLike,
    this.humidity,
    this.windSpeed,
    this.precipitationMm,
    this.precipitationIntervalSeconds,
    this.weatherCode,
  });

  factory Weather.fromOpenMeteoJson(
    Map<String, dynamic> json, {
    required String cityName,
  }) {
    final current = json['current'];
    final units = json['current_units'];
    if (current is! Map<String, dynamic> || units is! Map<String, dynamic>) {
      throw const FormatException('現在の気象データがありません。');
    }
    // 単位が違う値を同じ閾値へ渡さず、欠損として判定側に伝える。
    double? value(String key, String unit) =>
        units[key] == unit ? _number(current[key]) : null;
    final epoch = units['time'] == 'unixtime'
        ? _integer(current['time'])
        : null;
    final interval = units['interval'] == 'seconds'
        ? _integer(current['interval'])
        : null;
    return Weather(
      cityName: cityName,
      latitude: _number(json['latitude']),
      longitude: _number(json['longitude']),
      updatedAtUtc: epoch != null && epoch.abs() <= 8640000000000
          ? DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true)
          : null,
      temperature: value('temperature_2m', '°C'),
      feelsLike: value('apparent_temperature', '°C'),
      humidity: value('relative_humidity_2m', '%'),
      windSpeed: value('wind_speed_10m', 'm/s'),
      precipitationMm: value('precipitation', 'mm'),
      precipitationIntervalSeconds: interval != null && interval > 0
          ? interval
          : null,
      weatherCode: units['weather_code'] == 'wmo code'
          ? _integer(current['weather_code'])
          : null,
    );
  }

  // 降水量が欠けても、雨・雪・雷雨のコードがあれば危険側へ判定する。
  bool? get precipitationDetected =>
      _precipitationDetected(precipitationMm, weatherCode);

  DryingConditions get dryingConditions => DryingConditions(
    temperatureC: temperature,
    humidityPct: humidity,
    windSpeedMs: windSpeed,
    precipitationMm: precipitationMm,
    precipitationDetected: precipitationDetected,
    sourceTime: updatedAtUtc,
  );

  String get description => _weatherDescription(weatherCode);

  String get temperatureText => _formatValue(temperature, '℃');
  String get feelsLikeText => _formatValue(feelsLike, '℃');
  String get humidityText => _formatValue(humidity, '%');
  String get windSpeedText => _formatValue(windSpeed, ' m/s');
  String get rainText {
    final interval = precipitationIntervalSeconds;
    final window = interval == null ? '集計時間不明' : '直前${interval / 60}分';
    return '${_formatValue(precipitationMm, ' mm')}（$window、雨・雪を含む）';
  }

  String get coordinatesText => latitude == null || longitude == null
      ? '不明'
      : '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';

  String get updatedAtText =>
      updatedAtUtc == null ? '不明' : '${updatedAtUtc!.toLocal()}（端末時刻）';
}

class HourlyForecast {
  final DateTime forecastTimeUtc;
  final double? temperature;
  final double? humidity;
  final double? windSpeed;
  final double? precipitationMm;
  final double? precipitationProbability;
  final int? weatherCode;

  const HourlyForecast({
    required this.forecastTimeUtc,
    this.temperature,
    this.humidity,
    this.windSpeed,
    this.precipitationMm,
    this.precipitationProbability,
    this.weatherCode,
  });

  bool? get precipitationDetected =>
      _precipitationDetected(precipitationMm, weatherCode);

  DryingConditions get dryingConditions => DryingConditions(
    temperatureC: temperature,
    humidityPct: humidity,
    windSpeedMs: windSpeed,
    precipitationMm: precipitationMm,
    precipitationProbabilityPct: precipitationProbability,
    precipitationDetected: precipitationDetected,
    sourceTime: forecastTimeUtc,
  );

  String get description => _weatherDescription(weatherCode);
  String get temperatureText => _formatValue(temperature, '℃');
  String get humidityText => _formatValue(humidity, '%');
  String get windSpeedText => _formatValue(windSpeed, ' m/s');
  String get precipitationText => _formatValue(precipitationMm, ' mm');
  String get precipitationProbabilityText =>
      _formatValue(precipitationProbability, '%');
  String get forecastTimeText => _formatDateTime(forecastTimeUtc.toLocal());
}

class ForecastSeries {
  final String cityName;
  final double? latitude;
  final double? longitude;
  final List<HourlyForecast> forecasts;

  ForecastSeries({
    required this.cityName,
    this.latitude,
    this.longitude,
    required List<HourlyForecast> forecasts,
  }) : forecasts = List.unmodifiable(forecasts);

  factory ForecastSeries.fromOpenMeteoJson(
    Map<String, dynamic> json, {
    required String cityName,
  }) {
    final hourly = json['hourly'];
    final units = json['hourly_units'];
    if (hourly is! Map<String, dynamic> || units is! Map<String, dynamic>) {
      throw const FormatException('時間別予報データがありません。');
    }

    final times = hourly['time'];
    if (times is! List) {
      return ForecastSeries(
        cityName: cityName,
        latitude: _number(json['latitude']),
        longitude: _number(json['longitude']),
        forecasts: const [],
      );
    }

    double? value(String key, int index, String unit) {
      if (units[key] != unit) return null;
      final values = hourly[key];
      return values is List && index < values.length
          ? _number(values[index])
          : null;
    }

    int? integerValue(String key, int index, String unit) {
      if (units[key] != unit) return null;
      final values = hourly[key];
      return values is List && index < values.length
          ? _integer(values[index])
          : null;
    }

    final forecasts = <HourlyForecast>[];
    for (var index = 0; index < times.length; index++) {
      final epoch = units['time'] == 'unixtime' ? _integer(times[index]) : null;
      if (epoch == null || epoch.abs() > 8640000000000) continue;
      forecasts.add(
        HourlyForecast(
          forecastTimeUtc: DateTime.fromMillisecondsSinceEpoch(
            epoch * 1000,
            isUtc: true,
          ),
          temperature: value('temperature_2m', index, '°C'),
          humidity: value('relative_humidity_2m', index, '%'),
          windSpeed: value('wind_speed_10m', index, 'm/s'),
          precipitationMm: value('precipitation', index, 'mm'),
          precipitationProbability: value(
            'precipitation_probability',
            index,
            '%',
          ),
          weatherCode: integerValue('weather_code', index, 'wmo code'),
        ),
      );
    }
    forecasts.sort((a, b) => a.forecastTimeUtc.compareTo(b.forecastTimeUtc));
    return ForecastSeries(
      cityName: cityName,
      latitude: _number(json['latitude']),
      longitude: _number(json['longitude']),
      forecasts: forecasts,
    );
  }

  HourlyForecast? forecastNearestTo(
    DateTime plannedTime, {
    Duration maximumDifference = const Duration(minutes: 30),
  }) {
    HourlyForecast? nearest;
    Duration? nearestDifference;
    final plannedUtc = plannedTime.toUtc();
    for (final forecast in forecasts) {
      final difference = forecast.forecastTimeUtc.difference(plannedUtc).abs();
      final isCloser =
          nearestDifference == null || difference < nearestDifference;
      final isSameDistanceButLater =
          nearestDifference != null &&
          difference == nearestDifference &&
          forecast.forecastTimeUtc.isAfter(nearest!.forecastTimeUtc);
      if (isCloser || isSameDistanceButLater) {
        nearest = forecast;
        nearestDifference = difference;
      }
    }
    if (nearestDifference == null || nearestDifference > maximumDifference) {
      return null;
    }
    return nearest;
  }

  String get coordinatesText => latitude == null || longitude == null
      ? '不明'
      : '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
}

String _formatDateTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}/${twoDigits(value.month)}/${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}
