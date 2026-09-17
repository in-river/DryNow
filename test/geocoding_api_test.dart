import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weather_app/geocoding_api.dart';
import 'package:weather_app/models/weather_location.dart';

void main() {
  http.Response jsonResponse(Object? data) =>
      http.Response.bytes(utf8.encode(jsonEncode(data)), 200);

  group('地点モデル', () {
    test('地名・緯度経度・地域情報を保持する', () {
      final location = WeatherLocation.fromOpenMeteoJson({
        'name': '東京',
        'latitude': 35.6895,
        'longitude': 139.6917,
        'admin1': '東京都',
        'country': '日本',
      });

      expect(location, isNotNull);
      expect(location!.name, '東京');
      expect(location.latitude, 35.6895);
      expect(location.longitude, 139.6917);
      expect(location.details, '東京都・日本');
    });

    for (final data in <Map<String, dynamic>>[
      {'name': '', 'latitude': 35, 'longitude': 139},
      {'name': '地点', 'latitude': null, 'longitude': 139},
      {'name': '地点', 'latitude': 91, 'longitude': 139},
      {'name': '地点', 'latitude': 35, 'longitude': 181},
      {'name': '地点', 'latitude': double.nan, 'longitude': 139},
    ]) {
      test('不正な地点を受理しない: $data', () {
        expect(WeatherLocation.fromOpenMeteoJson(data), isNull);
      });
    }
  });

  group('Open-Meteo Geocoding API', () {
    test('検索条件を送信し、同名地点を区別できる情報を取り込む', () async {
      final api = GeocodingApi(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'geocoding-api.open-meteo.com');
          expect(request.url.path, '/v1/search');
          expect(request.url.queryParameters['name'], '東京都');
          expect(request.url.queryParameters['count'], '10');
          expect(request.url.queryParameters['language'], 'ja');
          expect(request.url.queryParameters['format'], 'json');
          return jsonResponse({
            'results': [
              {
                'name': '東京',
                'latitude': 35.6895,
                'longitude': 139.6917,
                'admin1': '東京都',
                'country': '日本',
              },
            ],
          });
        }),
      );
      addTearDown(api.close);

      final response = await api.search('  東京都  ');

      expect(response.locations, hasLength(1));
      expect(response.locations.single.name, '東京');
      expect(response.locations.single.details, '東京都・日本');
      expect(response.fetchedAt.isUtc, isTrue);
      expect(response.rawJson, contains('results'));
    });

    test('日本語の省略地名は自治体接尾辞を補って検索する', () async {
      final requestedNames = <String>[];
      final api = GeocodingApi(
        client: MockClient((request) async {
          final name = request.url.queryParameters['name']!;
          requestedNames.add(name);
          if (name != '東京都') return jsonResponse({});
          return jsonResponse({
            'results': [
              {
                'name': '東京都',
                'latitude': 35.6895,
                'longitude': 139.6917,
                'admin1': '東京都',
                'country': '日本',
              },
            ],
          });
        }),
      );
      addTearDown(api.close);

      final response = await api.search('東京');

      expect(requestedNames, ['東京市', '東京区', '東京都']);
      expect(response.locations.single.name, '東京都');
    });

    test('検索結果がないレスポンスを空リストとして返す', () async {
      final api = GeocodingApi(
        client: MockClient(
          (_) async => jsonResponse({'generationtime_ms': 0.1}),
        ),
      );
      addTearDown(api.close);

      final response = await api.search('存在しない地点名');

      expect(response.locations, isEmpty);
    });

    test('不正な候補だけを除外する', () async {
      final api = GeocodingApi(
        client: MockClient(
          (_) async => jsonResponse({
            'results': [
              {'name': '不正', 'latitude': null, 'longitude': 139},
              {'name': '熊谷市', 'latitude': 36.1473, 'longitude': 139.3886},
            ],
          }),
        ),
      );
      addTearDown(api.close);

      final response = await api.search('熊谷');

      expect(response.locations.map((location) => location.name), ['熊谷市']);
    });

    test('空文字は通信せず空リストを返す', () async {
      var requests = 0;
      final api = GeocodingApi(
        client: MockClient((_) async {
          requests++;
          return jsonResponse({});
        }),
      );
      addTearDown(api.close);

      expect((await api.search('  ')).locations, isEmpty);
      expect(requests, 0);
    });

    test('HTTPエラーを検索結果として返さない', () async {
      final api = GeocodingApi(
        client: MockClient((_) async => http.Response('diagnostic body', 500)),
      );
      addTearDown(api.close);

      await expectLater(
        api.search('東京'),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('HTTP 500'), isNot(contains('diagnostic body'))),
          ),
        ),
      );
    });

    test('不正JSONを受理しない', () async {
      final api = GeocodingApi(
        client: MockClient((_) async => http.Response('{broken', 200)),
      );
      addTearDown(api.close);

      await expectLater(api.search('東京'), throwsA(isA<FormatException>()));
    });

    test('接続失敗を利用者向けエラーへ変換する', () async {
      final api = GeocodingApi(
        client: MockClient((request) async {
          throw http.ClientException('internal diagnostic', request.url);
        }),
      );
      addTearDown(api.close);

      await expectLater(
        api.search('東京'),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('接続できません'), isNot(contains('internal diagnostic'))),
          ),
        ),
      );
    });

    test('応答待ちをタイムアウトする', () async {
      final pending = Completer<http.Response>();
      final api = GeocodingApi(
        client: MockClient((_) => pending.future),
        timeout: const Duration(milliseconds: 1),
      );
      addTearDown(api.close);
      try {
        await expectLater(
          api.search('東京'),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('タイムアウト'),
            ),
          ),
        );
      } finally {
        pending.complete(jsonResponse({}));
      }
    });
  });
}
