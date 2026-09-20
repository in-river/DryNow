import '../models/weather.dart';

final class ForecastSubstep {
  const ForecastSubstep({
    required this.startTimeUtc,
    required this.endTimeUtc,
    required this.temperatureC,
    required this.relativeHumidityPct,
    required this.windSpeedMs,
  });

  final DateTime startTimeUtc;
  final DateTime endTimeUtc;
  final double temperatureC;
  final double relativeHumidityPct;
  final double windSpeedMs;
}

final class ForecastStepCursor {
  ForecastStepCursor({
    required ForecastSeries series,
    required DateTime startTimeUtc,
    required this.integrationStep,
  }) : _forecasts = series.forecasts,
       _currentTimeUtc = startTimeUtc.toUtc() {
    _validate(series, startTimeUtc);
    _intervalIndex = _findInterval(_currentTimeUtc);
  }

  static const _maximumGap = Duration(hours: 1);
  static const _minimumTemperatureC = -80.0;
  static const _maximumTemperatureC = 70.0;

  final List<HourlyForecast> _forecasts;
  final Duration integrationStep;
  DateTime _currentTimeUtc;
  late int _intervalIndex;

  DateTime get forecastEndUtc => _forecasts.last.forecastTimeUtc.toUtc();
  bool get hasNext => _currentTimeUtc.isBefore(forecastEndUtc);

  ForecastSubstep next() {
    if (!hasNext) {
      throw StateError('予報末尾を超えてstepを取得できません。');
    }
    while (_intervalIndex + 1 < _forecasts.length &&
        !_currentTimeUtc.isBefore(
          _forecasts[_intervalIndex + 1].forecastTimeUtc.toUtc(),
        )) {
      _intervalIndex++;
    }
    if (_intervalIndex + 1 >= _forecasts.length) {
      throw StateError('補間に必要な次の予報点がありません。');
    }

    final left = _forecasts[_intervalIndex];
    final right = _forecasts[_intervalIndex + 1];
    _validateForecastPoint(left);
    _validateForecastPoint(right);
    final rightTimeUtc = right.forecastTimeUtc.toUtc();
    final nextGridUtc = _nextGridBoundary(_currentTimeUtc);
    final endTimeUtc = nextGridUtc.isBefore(rightTimeUtc)
        ? nextGridUtc
        : rightTimeUtc;
    final midpointUtc = DateTime.fromMicrosecondsSinceEpoch(
      (_currentTimeUtc.microsecondsSinceEpoch +
              endTimeUtc.microsecondsSinceEpoch) ~/
          2,
      isUtc: true,
    );
    final fraction =
        midpointUtc.difference(left.forecastTimeUtc.toUtc()).inMicroseconds /
        rightTimeUtc.difference(left.forecastTimeUtc.toUtc()).inMicroseconds;

    final temperature = _interpolate(
      left.temperature,
      right.temperature,
      fraction,
      'temperature',
    );
    final humidity = _interpolate(
      left.humidity,
      right.humidity,
      fraction,
      'relativeHumidity',
    );
    final wind = _interpolate(
      left.windSpeed,
      right.windSpeed,
      fraction,
      'windSpeed',
    );
    _validateWeather(temperature, humidity, wind);

    final step = ForecastSubstep(
      startTimeUtc: _currentTimeUtc,
      endTimeUtc: endTimeUtc,
      temperatureC: temperature,
      relativeHumidityPct: humidity,
      windSpeedMs: wind,
    );
    _currentTimeUtc = endTimeUtc;
    return step;
  }

  void _validate(ForecastSeries series, DateTime startTime) {
    if (integrationStep <= Duration.zero) {
      throw const FormatException('積分stepは正の時間である必要があります。');
    }
    final offset = series.locationUtcOffset;
    if (offset == null || offset.abs() > const Duration(hours: 14)) {
      throw const FormatException('地点timezone offsetが不明または不正です。');
    }
    if (!startTime.isUtc) {
      throw const FormatException('開始時刻はUTCの絶対時刻で指定してください。');
    }
    if (_forecasts.length < 2) {
      throw const FormatException('補間には2点以上の予報が必要です。');
    }
    for (var index = 0; index < _forecasts.length; index++) {
      final time = _forecasts[index].forecastTimeUtc;
      if (!time.isUtc) {
        throw const FormatException('予報時刻はUTCである必要があります。');
      }
      if (index == 0) continue;
      final gap = time.difference(_forecasts[index - 1].forecastTimeUtc);
      if (gap <= Duration.zero) {
        throw const FormatException('予報時刻に重複または逆順があります。');
      }
      if (gap > _maximumGap) {
        throw const FormatException('予報時刻に1時間を超える穴があります。');
      }
    }
    final first = _forecasts.first.forecastTimeUtc;
    final last = _forecasts.last.forecastTimeUtc;
    if (startTime.isBefore(first) || !startTime.isBefore(last)) {
      throw const FormatException('開始時刻が予報範囲外です。');
    }
  }

  int _findInterval(DateTime timeUtc) {
    for (var index = 0; index + 1 < _forecasts.length; index++) {
      final left = _forecasts[index].forecastTimeUtc.toUtc();
      final right = _forecasts[index + 1].forecastTimeUtc.toUtc();
      if (!timeUtc.isBefore(left) && timeUtc.isBefore(right)) return index;
    }
    throw const FormatException('開始時刻を含む予報区間がありません。');
  }

  DateTime _nextGridBoundary(DateTime valueUtc) {
    final stepMicroseconds = integrationStep.inMicroseconds;
    final remainder = valueUtc.microsecondsSinceEpoch % stepMicroseconds;
    final increment = remainder == 0
        ? stepMicroseconds
        : stepMicroseconds - remainder;
    return DateTime.fromMicrosecondsSinceEpoch(
      valueUtc.microsecondsSinceEpoch + increment,
      isUtc: true,
    );
  }

  double _interpolate(
    double? left,
    double? right,
    double fraction,
    String name,
  ) {
    if (left == null || right == null || !left.isFinite || !right.isFinite) {
      throw FormatException('$nameが欠損または不正です。');
    }
    final value = left + (right - left) * fraction;
    if (!value.isFinite) throw FormatException('$nameの補間結果が不正です。');
    return value;
  }

  void _validateWeather(double temperature, double humidity, double wind) {
    if (temperature < _minimumTemperatureC ||
        temperature > _maximumTemperatureC) {
      throw const FormatException('気温が許容範囲外です。');
    }
    if (humidity < 0 || humidity > 100) {
      throw const FormatException('相対湿度が0〜100%の範囲外です。');
    }
    if (wind < 0) throw const FormatException('風速が負です。');
  }

  void _validateForecastPoint(HourlyForecast forecast) {
    final temperature = forecast.temperature;
    final humidity = forecast.humidity;
    final wind = forecast.windSpeed;
    if (temperature == null || humidity == null || wind == null) {
      throw const FormatException('気象値が欠損しています。');
    }
    if (!temperature.isFinite || !humidity.isFinite || !wind.isFinite) {
      throw const FormatException('気象値がNaNまたはInfinityです。');
    }
    _validateWeather(temperature, humidity, wind);
  }
}
