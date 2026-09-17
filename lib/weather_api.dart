import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models/weather.dart';

class WeatherResponse {
  final Weather weather;
  final DateTime fetchedAt;
  final String rawJson;

  const WeatherResponse({
    required this.weather,
    required this.fetchedAt,
    required this.rawJson,
  });

  String get fetchedAtText => fetchedAt.toLocal().toString();
}

class ForecastResponse {
  final ForecastSeries series;
  final DateTime fetchedAt;
  final String rawJson;

  const ForecastResponse({
    required this.series,
    required this.fetchedAt,
    required this.rawJson,
  });

  HourlyForecast? forecastNearestTo(DateTime plannedTime) =>
      series.forecastNearestTo(plannedTime);

  String get fetchedAtText => fetchedAt.toLocal().toString();
}

class WeatherApi {
  final http.Client _client;
  final Duration timeout;

  WeatherApi({http.Client? client, this.timeout = const Duration(seconds: 15)})
    : _client = client ?? http.Client();

  Future<WeatherResponse> fetchCurrentWeatherByCoordinates(
    double lat,
    double lon, {
    String cityName = '指定地点',
  }) async {
    _validateCoordinates(lat, lon);
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current':
          'temperature_2m,relative_humidity_2m,apparent_temperature,'
          'wind_speed_10m,precipitation,weather_code',
      'temperature_unit': 'celsius',
      'wind_speed_unit': 'ms',
      'precipitation_unit': 'mm',
      'timeformat': 'unixtime',
      'timezone': 'GMT',
    });

    late http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw Exception('天気情報の取得がタイムアウトしました。');
    } on http.ClientException {
      throw Exception('天気情報に接続できませんでした。');
    }
    final fetchedAt = DateTime.now().toUtc();
    if (response.statusCode != 200) {
      throw Exception('天気データの取得に失敗しました（HTTP ${response.statusCode}）。');
    }
    final rawJson = utf8.decode(response.bodyBytes);
    final payload = jsonDecode(rawJson);
    if (payload is! Map<String, dynamic> || payload['error'] == true) {
      throw const FormatException('天気データの形式が不正です。');
    }
    return WeatherResponse(
      weather: Weather.fromOpenMeteoJson(payload, cityName: cityName),
      fetchedAt: fetchedAt,
      // rawは正規化値と別にメモリ上で保持し、ログへは出さない。
      rawJson: rawJson,
    );
  }

  Future<ForecastResponse> fetchHourlyForecastByCoordinates(
    double lat,
    double lon, {
    String cityName = '指定地点',
  }) async {
    _validateCoordinates(lat, lon);
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'hourly':
          'temperature_2m,relative_humidity_2m,wind_speed_10m,'
          'precipitation,precipitation_probability,weather_code',
      'temperature_unit': 'celsius',
      'wind_speed_unit': 'ms',
      'precipitation_unit': 'mm',
      'timeformat': 'unixtime',
      // UTCの絶対時刻で保持し、画面表示時だけ端末のタイムゾーンへ変換する。
      'timezone': 'GMT',
      'forecast_days': '3',
    });

    late http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw Exception('時間別予報の取得がタイムアウトしました。');
    } on http.ClientException {
      throw Exception('時間別予報に接続できませんでした。');
    }
    final fetchedAt = DateTime.now().toUtc();
    if (response.statusCode != 200) {
      throw Exception('時間別予報の取得に失敗しました（HTTP ${response.statusCode}）。');
    }
    final rawJson = utf8.decode(response.bodyBytes);
    final payload = jsonDecode(rawJson);
    if (payload is! Map<String, dynamic> || payload['error'] == true) {
      throw const FormatException('時間別予報データの形式が不正です。');
    }
    return ForecastResponse(
      series: ForecastSeries.fromOpenMeteoJson(payload, cityName: cityName),
      fetchedAt: fetchedAt,
      rawJson: rawJson,
    );
  }

  void _validateCoordinates(double lat, double lon) {
    if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
      throw ArgumentError('緯度・経度が範囲外です。');
    }
  }

  void close() => _client.close();
}
