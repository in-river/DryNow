import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/geocoding_api.dart';
import 'package:weather_app/main.dart';
import 'package:weather_app/models/weather.dart';
import 'package:weather_app/models/weather_location.dart';
import 'package:weather_app/weather_api.dart';

typedef ForecastFetcher =
    Future<ForecastResponse> Function(double lat, double lon, String cityName);

class FakeWeatherApi extends WeatherApi {
  FakeWeatherApi(this.fetch);

  final ForecastFetcher fetch;

  @override
  Future<ForecastResponse> fetchHourlyForecastByCoordinates(
    double lat,
    double lon, {
    String cityName = '指定地点',
  }) => fetch(lat, lon, cityName);
}

class FakeGeocodingApi extends GeocodingApi {
  FakeGeocodingApi(this.fetch);

  final Future<GeocodingResponse> Function(String query) fetch;

  @override
  Future<GeocodingResponse> search(String query) => fetch(query);
}

void main() {
  final sourceTime = DateTime.utc(2026, 9, 17, 3);

  ForecastResponse response({
    String cityName = '春日部市',
    double? temperature = 25,
    double? humidity = 50,
    double? wind = 2,
    double rain = 0,
    double? probability = 10,
    List<HourlyForecast>? forecasts,
  }) => ForecastResponse(
    series: ForecastSeries(
      cityName: cityName,
      latitude: 35.98,
      longitude: 139.75,
      forecasts:
          forecasts ??
          [
            HourlyForecast(
              forecastTimeUtc: sourceTime.add(const Duration(hours: 1)),
              temperature: temperature,
              humidity: humidity,
              windSpeed: wind,
              precipitationMm: rain,
              precipitationProbability: probability,
              weatherCode: rain > 0 ? 61 : 1,
            ),
          ],
    ),
    fetchedAt: sourceTime,
    rawJson: '{}',
  );

  GeocodingResponse searchResponse(List<WeatherLocation> locations) =>
      GeocodingResponse(
        locations: locations,
        fetchedAt: sourceTime,
        rawJson: '{}',
      );

  Future<void> pumpPage(
    WidgetTester tester, {
    required WeatherApi api,
    GeocodingApi? geocodingApi,
    DateTime Function()? now,
  }) => tester.pumpWidget(
    MaterialApp(
      home: WeatherPage(
        api: api,
        geocodingApi: geocodingApi,
        now: now ?? () => sourceTime,
      ),
    ),
  );

  testWidgets('予報取得後に地点・判定・主要気象カードを表示する', (tester) async {
    final completer = Completer<ForecastResponse>();
    final api = FakeWeatherApi((_, _, _) => completer.future);
    addTearDown(api.close);
    await pumpPage(tester, api: api);
    expect(find.byKey(const Key('forecast-loading')), findsOneWidget);

    completer.complete(response());
    await tester.pumpAndSettle();

    expect(find.text('春日部市の予報を使用中'), findsOneWidget);
    expect(find.text('外干しOK'), findsOneWidget);
    expect(find.text('今のところ外干しに適した予報です。'), findsOneWidget);
    expect(find.byKey(const Key('planned-time')), findsOneWidget);
    expect(find.byKey(const Key('metric-temperature')), findsOneWidget);
    expect(find.byKey(const Key('metric-humidity')), findsOneWidget);
    expect(find.byKey(const Key('metric-wind')), findsOneWidget);
    expect(find.byKey(const Key('metric-probability')), findsOneWidget);
    expect(find.text('25.0℃'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text('2.0 m/s'), findsOneWidget);
    expect(find.text('10.0%'), findsOneWidget);
    final temperatureTop = tester.getTopLeft(
      find.byKey(const Key('metric-temperature')),
    );
    final humidityTop = tester.getTopLeft(
      find.byKey(const Key('metric-humidity')),
    );
    final windTop = tester.getTopLeft(find.byKey(const Key('metric-wind')));
    final probabilityTop = tester.getTopLeft(
      find.byKey(const Key('metric-probability')),
    );
    expect(temperatureTop.dy, humidityTop.dy);
    expect(windTop.dy, probabilityTop.dy);
    expect(windTop.dy, greaterThan(temperatureTop.dy));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('予報時刻を過ぎたらOK表示を判定不能へ変更する', (tester) async {
    var now = sourceTime;
    final api = FakeWeatherApi((_, _, _) async => response());
    addTearDown(api.close);
    await pumpPage(tester, api: api, now: () => now);
    await tester.pumpAndSettle();
    expect(find.text('外干しOK'), findsOneWidget);

    now = sourceTime.add(const Duration(hours: 1, seconds: 1));
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('判定できません'), findsOneWidget);
    expect(find.text('外干しOK'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('注意・NG・判定不能を文字とアイコン付きで表示する', (tester) async {
    var currentResponse = response(humidity: 80);
    final api = FakeWeatherApi((_, _, _) async => currentResponse);
    addTearDown(api.close);
    await pumpPage(tester, api: api);
    await tester.pumpAndSettle();
    expect(find.text('外干しは注意'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    currentResponse = response(rain: 1);
    await tester.ensureVisible(find.text('予報を更新'));
    await tester.tap(find.text('予報を更新'));
    await tester.pumpAndSettle();
    expect(find.text('外干しNG'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);

    currentResponse = response(probability: null);
    await tester.ensureVisible(find.text('予報を更新'));
    await tester.tap(find.text('予報を更新'));
    await tester.pumpAndSettle();
    expect(find.text('判定できません'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('対応する予報がなければ判定不能理由を表示する', (tester) async {
    final api = FakeWeatherApi(
      (_, _, _) async => response(forecasts: const []),
    );
    addTearDown(api.close);
    await pumpPage(tester, api: api);
    await tester.pumpAndSettle();
    expect(find.text('判定できません'), findsOneWidget);
    expect(find.textContaining('時間別予報データがありません'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('APIエラー後の再読み込みで予報判定を取得できる', (tester) async {
    var calls = 0;
    final api = FakeWeatherApi((_, _, _) async {
      if (calls++ == 0) throw Exception('接続できません');
      return response();
    });
    addTearDown(api.close);
    await pumpPage(tester, api: api);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forecast-error')), findsOneWidget);
    expect(find.text('外干しOK'), findsNothing);
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    expect(find.text('外干しOK'), findsOneWidget);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('時刻チップで3時間後を選択できる', (tester) async {
    final forecasts = [
      HourlyForecast(
        forecastTimeUtc: sourceTime.add(const Duration(hours: 1)),
        temperature: 25,
        humidity: 50,
        windSpeed: 2,
        precipitationMm: 0,
        precipitationProbability: 0,
        weatherCode: 1,
      ),
      HourlyForecast(
        forecastTimeUtc: sourceTime.add(const Duration(hours: 3)),
        temperature: 27,
        humidity: 45,
        windSpeed: 3,
        precipitationMm: 0,
        precipitationProbability: 10,
        weatherCode: 0,
      ),
    ];
    final api = FakeWeatherApi(
      (_, _, _) async => response(forecasts: forecasts),
    );
    addTearDown(api.close);
    await pumpPage(tester, api: api);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('offset-3')));
    await tester.pump();

    final chip = tester.widget<ChoiceChip>(find.byKey(const Key('offset-3')));
    expect(chip.selected, isTrue);
    expect(find.text('27.0℃'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('地点変更時は旧予報を隠し、新しい緯度経度で再取得する', (tester) async {
    const tokyo = WeatherLocation(
      name: '東京',
      latitude: 35.6895,
      longitude: 139.6917,
      administrativeArea: '東京都',
      country: '日本',
    );
    final tokyoForecast = Completer<ForecastResponse>();
    final calls = <(double, double, String)>[];
    final api = FakeWeatherApi((lat, lon, cityName) {
      calls.add((lat, lon, cityName));
      if (cityName == '東京') return tokyoForecast.future;
      return Future.value(response(cityName: cityName));
    });
    final geocodingApi = FakeGeocodingApi((_) async => searchResponse([tokyo]));
    addTearDown(api.close);
    addTearDown(geocodingApi.close);
    await pumpPage(tester, api: api, geocodingApi: geocodingApi);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('location-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('location-search-field')),
      '東京',
    );
    await tester.tap(find.byKey(const Key('location-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '東京'));
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.descendant(
        of: find.byKey(const Key('location-button')),
        matching: find.text('東京の予報を使用中'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('forecast-loading')), findsOneWidget);
    expect(find.text('外干しOK'), findsNothing);
    expect(calls.last, (tokyo.latitude, tokyo.longitude, tokyo.name));

    tokyoForecast.complete(response(cityName: '東京', temperature: 28));
    await tester.pumpAndSettle();
    expect(find.text('28.0℃'), findsOneWidget);
    expect(find.text('外干しOK'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('地点検索の0件・loading・errorを表示する', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final searchCompleter = Completer<GeocodingResponse>();
    final api = FakeWeatherApi((_, _, _) async => response());
    var mode = 'empty';
    final geocodingApi = FakeGeocodingApi((_) {
      if (mode == 'loading') return searchCompleter.future;
      if (mode == 'error') return Future.error(Exception('地点検索に失敗しました'));
      return Future.value(searchResponse(const []));
    });
    addTearDown(api.close);
    addTearDown(geocodingApi.close);
    await pumpPage(tester, api: api, geocodingApi: geocodingApi);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('location-button')));
    await tester.pumpAndSettle();
    expect(find.text('市区町村名や地域名で検索できます。'), findsOneWidget);
    expect(find.textContaining('現在地の利用は今後対応予定'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('location-search-content'))).height,
      lessThan(160),
    );
    await tester.enterText(
      find.byKey(const Key('location-search-field')),
      'なし',
    );
    await tester.tap(find.byKey(const Key('location-search-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('location-search-empty')), findsOneWidget);

    mode = 'loading';
    await tester.enterText(
      find.byKey(const Key('location-search-field')),
      '東京',
    );
    await tester.tap(find.byKey(const Key('location-search-button')));
    await tester.pump();
    expect(find.byKey(const Key('location-search-loading')), findsOneWidget);
    searchCompleter.completeError(Exception('一時的な接続エラー'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('location-search-error')), findsOneWidget);
    expect(find.textContaining('一時的な接続エラー'), findsOneWidget);

    mode = 'error';
    await tester.tap(find.byKey(const Key('location-search-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('地点検索に失敗しました'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('幅320pxでもoverflowせず表示できる', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = FakeWeatherApi((_, _, _) async => response());
    addTearDown(api.close);

    await pumpPage(tester, api: api);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('metric-temperature')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('大画面でも主コンテンツ幅を800px以下に制限する', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final api = FakeWeatherApi((_, _, _) async => response());
    addTearDown(api.close);

    await pumpPage(tester, api: api);
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('assessment-card'))).width,
      lessThanOrEqualTo(800),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
