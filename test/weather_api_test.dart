import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weather_app/drying_assessment.dart';
import 'package:weather_app/models/weather.dart';
import 'package:weather_app/weather_api.dart';

void main() {
  final sourceTime = DateTime.utc(2026, 9, 17, 3);
  const evaluator = DryingEvaluator();

  Map<String, dynamic> payload({
    Map<String, dynamic> current = const {},
    Map<String, dynamic> units = const {},
    List<String> omitted = const [],
  }) => {
    'latitude': 35.98,
    'longitude': 139.75,
    'utc_offset_seconds': 0,
    'current_units': {
      'time': 'unixtime',
      'interval': 'seconds',
      'temperature_2m': '°C',
      'relative_humidity_2m': '%',
      'apparent_temperature': '°C',
      'wind_speed_10m': 'm/s',
      'precipitation': 'mm',
      'weather_code': 'wmo code',
      ...units,
    },
    'current': <String, dynamic>{
      'time': sourceTime.millisecondsSinceEpoch ~/ 1000,
      'interval': 900,
      'temperature_2m': 25.5,
      'relative_humidity_2m': 55,
      'apparent_temperature': 26,
      'wind_speed_10m': 2.5,
      'precipitation': 0,
      'weather_code': 2,
      ...current,
    }..removeWhere((key, _) => omitted.contains(key)),
  };

  http.Response jsonResponse(Object? data) =>
      http.Response.bytes(utf8.encode(jsonEncode(data)), 200);

  Future<WeatherResponse> fetch(Map<String, dynamic> data) {
    final api = WeatherApi(client: MockClient((_) async => jsonResponse(data)));
    addTearDown(api.close);
    return api.fetchCurrentWeatherByCoordinates(
      35.9795,
      139.7523,
      cityName: '春日部駅付近',
    );
  }

  DryingAssessment assess(WeatherResponse response) =>
      evaluator.evaluate(response.weather.dryingConditions, now: sourceTime);

  Map<String, dynamic> forecastPayload({
    List<dynamic>? times,
    Map<String, dynamic> hourly = const {},
    Map<String, dynamic> units = const {},
  }) => {
    'latitude': 35.98,
    'longitude': 139.75,
    'hourly_units': {
      'time': 'unixtime',
      'temperature_2m': '°C',
      'relative_humidity_2m': '%',
      'wind_speed_10m': 'm/s',
      'precipitation': 'mm',
      'precipitation_probability': '%',
      'weather_code': 'wmo code',
      ...units,
    },
    'hourly': {
      'time':
          times ??
          [
            sourceTime.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                1000,
            sourceTime.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
                1000,
          ],
      'temperature_2m': [25, 24],
      'relative_humidity_2m': [55, 60],
      'wind_speed_10m': [2, 3],
      'precipitation': [0, 0],
      'precipitation_probability': [10, 30],
      'weather_code': [1, 2],
      ...hourly,
    },
  };

  test('HTTPSで現在値を要求し、単位とUTC時刻形式を固定する', () async {
    var requests = 0;
    final api = WeatherApi(
      client: MockClient((request) async {
        requests++;
        expect(request.method, 'GET');
        expect(request.url.scheme, 'https');
        expect(request.url.host, 'api.open-meteo.com');
        expect(request.url.path, '/v1/forecast');
        final query = request.url.queryParameters;
        expect(query['latitude'], '35.9795');
        expect(query['longitude'], '139.7523');
        expect(query['temperature_unit'], 'celsius');
        expect(query['wind_speed_unit'], 'ms');
        expect(query['precipitation_unit'], 'mm');
        expect(query['timeformat'], 'unixtime');
        expect(query['timezone'], 'GMT');
        expect(
          query['current']!.split(','),
          containsAll([
            'temperature_2m',
            'relative_humidity_2m',
            'apparent_temperature',
            'wind_speed_10m',
            'precipitation',
            'weather_code',
          ]),
        );
        expect(query.keys, isNot(contains('apikey')));
        expect(query.keys, isNot(contains('appid')));
        expect(request.headers.keys, isNot(contains('authorization')));
        return jsonResponse(payload());
      }),
    );
    addTearDown(api.close);

    final response = await api.fetchCurrentWeatherByCoordinates(
      35.9795,
      139.7523,
      cityName: '春日部駅付近',
    );
    expect(requests, 1);
    expect(response.weather.cityName, '春日部駅付近');
    expect(response.weather.temperature, 25.5);
    expect(response.weather.humidity, 55);
    expect(response.weather.windSpeed, 2.5);
    expect(assess(response).status, DryingStatus.suitable);
  });

  test('raw JSONはUTF-8の元文字列のまま正規化値と別に保持する', () async {
    final data = payload()..['note'] = '追加情報を保持';
    final raw = '${const JsonEncoder.withIndent('  ').convert(data)}\n';
    final api = WeatherApi(
      client: MockClient(
        (_) async => http.Response.bytes(utf8.encode(raw), 200),
      ),
    );
    addTearDown(api.close);

    final before = DateTime.now().toUtc();
    final response = await api.fetchCurrentWeatherByCoordinates(
      35.9795,
      139.7523,
    );
    final after = DateTime.now().toUtc();

    expect(response.rawJson, raw);
    expect(response.weather.updatedAtUtc, sourceTime);
    expect(response.weather.updatedAtUtc!.isUtc, isTrue);
    expect(response.fetchedAt.isUtc, isTrue);
    expect(response.fetchedAt.isBefore(before), isFalse);
    expect(response.fetchedAt.isAfter(after), isFalse);
  });

  test('降水量の集計時間を維持し、1時間量に換算しない', () async {
    final response = await fetch(payload(current: {'precipitation': 0.4}));
    expect(response.weather.precipitationMm, 0.4);
    expect(response.weather.precipitationIntervalSeconds, 900);
    expect(response.weather.rainText, contains('0.4 mm'));
    expect(response.weather.rainText, matches(r'直前15(?:\.0)?分'));
  });

  test('降水の集計時間が欠けても15分と仮定しない', () async {
    final response = await fetch(payload(omitted: ['interval']));
    expect(response.weather.precipitationIntervalSeconds, isNull);
    expect(response.weather.rainText, contains('集計時間不明'));
  });

  test('0の気温・湿度・風速・降水量を保持する', () async {
    final response = await fetch(
      payload(
        current: {
          'temperature_2m': 0,
          'relative_humidity_2m': 0,
          'wind_speed_10m': 0,
          'precipitation': 0,
        },
      ),
    );
    final weather = response.weather;
    expect(weather.temperature, 0);
    expect(weather.humidity, 0);
    expect(weather.windSpeed, 0);
    expect(weather.precipitationMm, 0);
    expect(weather.precipitationDetected, isFalse);
    expect(assess(response).status, DryingStatus.caution);
  });

  test('欠損値とnullを0へ変換しない', () async {
    final response = await fetch(
      payload(
        current: {'relative_humidity_2m': null, 'precipitation': null},
        omitted: ['temperature_2m', 'wind_speed_10m'],
      ),
    );
    final weather = response.weather;
    expect(weather.temperature, isNull);
    expect(weather.humidity, isNull);
    expect(weather.windSpeed, isNull);
    expect(weather.precipitationMm, isNull);
    expect(weather.precipitationDetected, isNull);
    expect(weather.humidityText, '不明');
    expect(assess(response).status, DryingStatus.unknown);
  });

  test('湿度だけ欠けても乾きやすいと判定しない', () async {
    final response = await fetch(payload(omitted: ['relative_humidity_2m']));
    expect(assess(response).status, DryingStatus.unknown);
    expect(assess(response).reasons.join(), contains('湿度'));
  });

  for (final scenario in <(int, String)>[
    (51, '霧雨'),
    (61, '雨'),
    (71, '雪'),
    (95, '雷雨'),
  ]) {
    test('${scenario.$2}コードなら降水量0でもNG', () async {
      final response = await fetch(
        payload(current: {'weather_code': scenario.$1}),
      );
      expect(response.weather.precipitationMm, 0);
      expect(response.weather.precipitationDetected, isTrue);
      expect(response.weather.description, scenario.$2);
      expect(assess(response).status, DryingStatus.notRecommended);
    });
  }

  test('雨量と湿度が欠損しても有効な雪コードによるNGを隠さない', () async {
    final response = await fetch(
      payload(
        current: {'weather_code': 73},
        omitted: ['precipitation', 'relative_humidity_2m'],
      ),
    );
    expect(response.weather.precipitationMm, isNull);
    expect(response.weather.precipitationDetected, isTrue);
    expect(assess(response).status, DryingStatus.notRecommended);
  });

  for (final scenario in <(String, String)>[
    ('temperature_2m', '°F'),
    ('relative_humidity_2m', 'fraction'),
    ('wind_speed_10m', 'km/h'),
    ('precipitation', 'inch'),
    ('time', 'iso8601'),
  ]) {
    test('${scenario.$1}の単位が違えば現在の適性を判定しない', () async {
      final response = await fetch(payload(units: {scenario.$1: scenario.$2}));
      expect(assess(response).status, DryingStatus.unknown);
    });
  }

  test('数値文字列を実測の数値として解釈しない', () async {
    final response = await fetch(
      payload(current: {'relative_humidity_2m': '55'}),
    );
    expect(response.weather.humidity, isNull);
    expect(assess(response).status, DryingStatus.unknown);
  });

  for (final timestamp in [null, 1.5, 8640000000001]) {
    test('欠損・小数・範囲外の時刻 $timestamp を代替時刻へ置換しない', () async {
      final response = await fetch(payload(current: {'time': timestamp}));
      expect(response.weather.updatedAtUtc, isNull);
      expect(assess(response).status, DryingStatus.unknown);
    });
  }

  group('通信とレスポンスの失敗', () {
    test('HTTPエラーを空の正常データとして返さない', () async {
      final api = WeatherApi(
        client: MockClient((_) async => http.Response('diagnostic body', 429)),
      );
      addTearDown(api.close);
      await expectLater(
        api.fetchCurrentWeatherByCoordinates(35, 139),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('HTTP 429'), isNot(contains('diagnostic body'))),
          ),
        ),
      );
    });

    test('不正JSONはFormatException', () async {
      final api = WeatherApi(
        client: MockClient((_) async => http.Response('{broken', 200)),
      );
      addTearDown(api.close);
      await expectLater(
        api.fetchCurrentWeatherByCoordinates(35, 139),
        throwsA(isA<FormatException>()),
      );
    });

    for (final entry in <String, Object?>{
      'APIエラー': {'error': true, 'reason': 'invalid request'},
      '配列': [],
      'null': null,
      'currentなし': {'current_units': {}},
      'unitsなし': {'current': {}},
    }.entries) {
      test('${entry.key}レスポンスを正常な観測値として受理しない', () async {
        final api = WeatherApi(
          client: MockClient((_) async => jsonResponse(entry.value)),
        );
        addTearDown(api.close);
        await expectLater(
          api.fetchCurrentWeatherByCoordinates(35, 139),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('接続失敗では内部URLを含まないエラーを返す', () async {
      final api = WeatherApi(
        client: MockClient((request) async {
          throw http.ClientException('internal diagnostic', request.url);
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.fetchCurrentWeatherByCoordinates(35, 139),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('接続できません'), isNot(contains('internal diagnostic'))),
          ),
        ),
      );
    });

    test('応答待ちがタイムアウトする', () async {
      final pending = Completer<http.Response>();
      final api = WeatherApi(
        client: MockClient((_) => pending.future),
        timeout: const Duration(milliseconds: 1),
      );
      addTearDown(api.close);
      try {
        await expectLater(
          api.fetchCurrentWeatherByCoordinates(35, 139),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('タイムアウト'),
            ),
          ),
        );
      } finally {
        pending.complete(jsonResponse(payload()));
      }
    });
  });

  group('時間別予報', () {
    test('日射と地点の時差を取り込み、epochはUTCのまま保持する', () {
      final data = forecastPayload(
        hourly: {
          'shortwave_radiation': [0, 500],
        },
        units: {'shortwave_radiation': 'W/m²'},
      )..addAll({'utc_offset_seconds': 32400, 'timezone': 'Asia/Tokyo'});
      final series = ForecastSeries.fromOpenMeteoJson(data, cityName: '東京');
      expect(series.locationUtcOffset, const Duration(hours: 9));
      expect(series.timezone, 'Asia/Tokyo');
      expect(series.forecasts.first.solarRadiation, 0);
      expect(series.forecasts.last.solarRadiation, 500);
      expect(
        series.forecasts.first.forecastTimeUtc,
        sourceTime.add(const Duration(hours: 1)),
      );
    });

    for (final values in <List<dynamic>>[
      [],
      [null],
      ['500'],
      [double.nan],
      [double.infinity],
    ]) {
      test('日射の欠損・不正値$valuesをゼロにしない', () {
        final series = ForecastSeries.fromOpenMeteoJson(
          forecastPayload(
            hourly: {'shortwave_radiation': values},
            units: {'shortwave_radiation': 'W/m²'},
          ),
          cityName: '東京',
        );
        expect(series.forecasts.first.solarRadiation, isNull);
      });
    }
    test('日射の単位不一致は欠損', () {
      final series = ForecastSeries.fromOpenMeteoJson(
        forecastPayload(
          hourly: {
            'shortwave_radiation': [500],
          },
          units: {'shortwave_radiation': 'kW/m²'},
        ),
        cityName: '東京',
      );
      expect(series.forecasts.first.solarRadiation, isNull);
    });
    for (final offset in [null, 999999, 0.5, '32400']) {
      test('時差$offsetを推測しない', () {
        final data = forecastPayload()..['utc_offset_seconds'] = offset;
        expect(
          ForecastSeries.fromOpenMeteoJson(
            data,
            cityName: '東京',
          ).locationUtcOffset,
          isNull,
        );
      });
    }
    test('必要な時間別項目とUTC時刻を要求し、降水確率を取り込む', () async {
      final api = WeatherApi(
        client: MockClient((request) async {
          final query = request.url.queryParameters;
          expect(query['timeformat'], 'unixtime');
          expect(query['timezone'], 'auto');
          expect(query['forecast_days'], '3');
          expect(query['hourly']!.split(','), contains('shortwave_radiation'));
          expect(
            query['hourly']!.split(','),
            containsAll([
              'temperature_2m',
              'relative_humidity_2m',
              'wind_speed_10m',
              'precipitation',
              'precipitation_probability',
              'weather_code',
            ]),
          );
          return jsonResponse(forecastPayload());
        }),
      );
      addTearDown(api.close);

      final response = await api.fetchHourlyForecastByCoordinates(
        35.9795,
        139.7523,
        cityName: '春日部駅付近',
      );

      expect(response.series.cityName, '春日部駅付近');
      expect(response.series.forecasts, hasLength(2));
      final first = response.series.forecasts.first;
      expect(first.forecastTimeUtc.isUtc, isTrue);
      expect(first.temperature, 25);
      expect(first.humidity, 55);
      expect(first.windSpeed, 2);
      expect(first.precipitationMm, 0);
      expect(first.precipitationProbability, 10);
      expect(
        evaluator
            .evaluateForecast(first.dryingConditions, now: sourceTime)
            .status,
        DryingStatus.suitable,
      );
    });

    test('予定時刻に最も近い予報を選び、同距離なら未来側を選ぶ', () {
      final series = ForecastSeries.fromOpenMeteoJson(
        forecastPayload(),
        cityName: '春日部駅付近',
      );
      expect(
        series
            .forecastNearestTo(
              sourceTime.add(const Duration(hours: 1, minutes: 20)),
            )
            ?.forecastTimeUtc,
        sourceTime.add(const Duration(hours: 1)),
      );
      expect(
        series
            .forecastNearestTo(
              sourceTime.add(const Duration(hours: 1, minutes: 30)),
            )
            ?.forecastTimeUtc,
        sourceTime.add(const Duration(hours: 2)),
      );
      expect(
        series.forecastNearestTo(sourceTime.add(const Duration(hours: 3))),
        isNull,
      );
    });

    test('日付をまたいでも絶対時刻で予報を選択する', () {
      final beforeMidnight = DateTime.utc(2026, 9, 17, 23);
      final afterMidnight = DateTime.utc(2026, 9, 18);
      final series = ForecastSeries.fromOpenMeteoJson(
        forecastPayload(
          times: [
            beforeMidnight.millisecondsSinceEpoch ~/ 1000,
            afterMidnight.millisecondsSinceEpoch ~/ 1000,
          ],
        ),
        cityName: '春日部駅付近',
      );
      expect(
        series
            .forecastNearestTo(beforeMidnight.add(const Duration(minutes: 45)))
            ?.forecastTimeUtc,
        afterMidnight,
      );
    });

    test('配列の欠損・null・単位不一致を0へ変換しない', () {
      final series = ForecastSeries.fromOpenMeteoJson(
        forecastPayload(
          hourly: {
            'temperature_2m': [null, 24],
            'relative_humidity_2m': <dynamic>[],
            'precipitation_probability': [null, 30],
          },
          units: {'wind_speed_10m': 'km/h'},
        ),
        cityName: '春日部駅付近',
      );
      final first = series.forecasts.first;
      expect(first.temperature, isNull);
      expect(first.humidity, isNull);
      expect(first.windSpeed, isNull);
      expect(first.precipitationProbability, isNull);
      expect(
        evaluator
            .evaluateForecast(first.dryingConditions, now: sourceTime)
            .status,
        DryingStatus.unknown,
      );
    });

    test('時間配列がなければ空の予報として扱う', () {
      final data = forecastPayload();
      (data['hourly'] as Map<String, dynamic>).remove('time');
      final series = ForecastSeries.fromOpenMeteoJson(data, cityName: '春日部駅付近');
      expect(series.forecasts, isEmpty);
      expect(series.forecastNearestTo(sourceTime), isNull);
    });

    test('予報APIのHTTPエラーを正常な予報として返さない', () async {
      final api = WeatherApi(
        client: MockClient((_) async => http.Response('diagnostic body', 503)),
      );
      addTearDown(api.close);
      await expectLater(
        api.fetchHourlyForecastByCoordinates(35, 139),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('HTTP 503'), isNot(contains('diagnostic body'))),
          ),
        ),
      );
    });
  });

  group('座標の検証', () {
    for (final coordinate in <(double, double)>[
      (90.01, 0),
      (-90.01, 0),
      (0, 180.01),
      (0, -180.01),
      (double.nan, 0),
      (0, double.infinity),
    ]) {
      test('不正座標 $coordinate はHTTP要求前に拒否する', () async {
        var requests = 0;
        final api = WeatherApi(
          client: MockClient((_) async {
            requests++;
            return jsonResponse(payload());
          }),
        );
        addTearDown(api.close);
        await expectLater(
          api.fetchCurrentWeatherByCoordinates(coordinate.$1, coordinate.$2),
          throwsArgumentError,
        );
        expect(requests, 0);
      });
    }

    test('境界の緯度経度と0座標を許容する', () async {
      var requests = 0;
      final api = WeatherApi(
        client: MockClient((_) async {
          requests++;
          return jsonResponse(payload());
        }),
      );
      addTearDown(api.close);
      await api.fetchCurrentWeatherByCoordinates(90, 180);
      await api.fetchCurrentWeatherByCoordinates(-90, -180);
      await api.fetchCurrentWeatherByCoordinates(0, 0);
      expect(requests, 3);
    });
  });
}
