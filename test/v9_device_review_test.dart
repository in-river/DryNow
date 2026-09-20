import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/drying_advice.dart';
import 'package:weather_app/drying_advice_card.dart';
import 'package:weather_app/drying_assessment.dart';
import 'package:weather_app/drying_estimator.dart';
import 'package:weather_app/drying_model_config.dart';
import 'package:weather_app/environment_store.dart';
import 'package:weather_app/main.dart';
import 'package:weather_app/models/drying_environment.dart';
import 'package:weather_app/models/weather.dart';
import 'package:weather_app/weather_api.dart';

import 'drying_estimator_test.dart' show environment, sample;

DryingAdvice adviceWith({
  List<GarmentAdvice> garments = const [],
  List<WeatherRisk> risks = const [],
}) => DryingAdvice(
  overallStatus: DryingStatus.caution,
  garments: garments,
  weatherRisks: risks,
  primaryMessage: '外干しできますが注意',
  detailMessages: const [],
);

GarmentAdvice garmentAt(
  DateTime completion,
  DateTime start, [
  String id = 'thin',
]) {
  return GarmentAdvice(
    estimate: GarmentDryingEstimate(
      category: GarmentCategory(id, id, '', 0.8),
      status: DryingEstimateStatus.estimated,
      estimatedCompletionTime: completion,
      estimatedDuration: completion.difference(start),
    ),
    status: DryingStatus.caution,
    reasons: const [],
  );
}

GarmentAdvice garmentWithStatus({
  required String id,
  required DateTime completion,
  required DateTime start,
  required DryingStatus status,
}) => GarmentAdvice(
  estimate: GarmentDryingEstimate(
    category: GarmentCategory(id, id, '', 0.8),
    status: DryingEstimateStatus.estimated,
    estimatedCompletionTime: completion,
    estimatedDuration: completion.difference(start),
  ),
  status: status,
  reasons: const [],
);

GarmentAdvice unavailableGarment(String id) => GarmentAdvice(
  estimate: GarmentDryingEstimate(
    category: GarmentCategory(id, id, '', 0.8),
    status: DryingEstimateStatus.forecastLimit,
  ),
  status: DryingStatus.unknown,
  reasons: const ['予測可能な時間内では乾燥完了を確認できません。'],
);

Future<void> showCard(
  WidgetTester tester,
  DryingAdvice advice, {
  required DateTime reference,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            DryingAdviceCard(
              advice: advice,
              locationUtcOffset: Duration.zero,
              referenceTime: reference,
            ),
            if (advice.weatherRisks.isNotEmpty)
              WeatherRiskDetails(
                risks: advice.weatherRisks,
                locationUtcOffset: Duration.zero,
              ),
            DryingPredictionAbout(
              advice: advice,
              locationUtcOffset: Duration.zero,
              timezone: 'UTC',
              referenceTime: reference,
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> openRisks(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('weather-risk-details')));
  await tester.pumpAndSettle();
}

Future<void> openAbout(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('prediction-about')));
  await tester.pumpAndSettle();
}

WeatherRisk risk({
  WeatherRiskKind kind = WeatherRiskKind.rain,
  DryingStatus status = DryingStatus.caution,
  double? precipitation,
  double? probability,
  List<int> codes = const [],
  double? wind,
  double? threshold,
}) => WeatherRisk(
  kind: kind,
  status: status,
  riskStartTime: DateTime.utc(2026, 9, 18, 16, 30),
  endTime: DateTime.utc(2026, 9, 18, 17, 30),
  sourceTime: DateTime.utc(2026, 9, 18, 17),
  precipitationMm: precipitation,
  precipitationProbabilityPct: probability,
  weatherCodes: codes,
  windSpeedMs: wind,
  windThresholdMs: threshold,
);

class _Store implements EnvironmentStore {
  @override
  Future<DryingEnvironment?> load() async => environment;

  @override
  Future<void> save(DryingEnvironment environment) async {}
}

class _Api extends WeatherApi {
  _Api(this.response);
  final ForecastResponse response;

  @override
  Future<ForecastResponse> fetchHourlyForecastByCoordinates(
    double lat,
    double lon, {
    String cityName = '指定地点',
  }) async => response;
}

void main() {
  final reference = DateTime.utc(2026, 9, 18, 8);

  test('干し始め時刻を今日・明日・日付で表示', () {
    final localReference = DateTime(2026, 9, 18, 10);
    expect(
      formatRelativeDeviceTime(DateTime(2026, 9, 18, 23, 32), localReference),
      '今日 23:32',
    );
    expect(
      formatRelativeDeviceTime(DateTime(2026, 9, 19, 8, 5), localReference),
      '明日 08:05',
    );
    expect(
      formatRelativeDeviceTime(DateTime(2026, 9, 20, 17, 44), localReference),
      '9/20 17:44',
    );
  });

  test('Windowsの表示タイトルはDryNow', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();
    expect(source, contains('window.Create(L"DryNow"'));
    expect(source, isNot(contains('window.Create(L"weather_app"')));
  });

  testWidgets('今日の乾燥予想時刻と所要時間を表示', (tester) async {
    final completion = DateTime.utc(2026, 9, 18, 10, 40);
    await showCard(
      tester,
      adviceWith(garments: [garmentAt(completion, reference)]),
      reference: reference,
    );
    expect(find.text('今日 10:40'), findsOneWidget);
    expect(find.text('約2時間40分'), findsOneWidget);
  });

  testWidgets('明日の乾燥予想時刻を表示', (tester) async {
    final completion = DateTime.utc(2026, 9, 19, 5, 50);
    await showCard(
      tester,
      adviceWith(garments: [garmentAt(completion, reference)]),
      reference: reference,
    );
    expect(find.text('明日 05:50'), findsOneWidget);
  });

  testWidgets('翌々日はあさってで乾燥予想時刻を表示', (tester) async {
    final completion = DateTime.utc(2026, 9, 20, 8, 30);
    await showCard(
      tester,
      adviceWith(garments: [garmentAt(completion, reference)]),
      reference: reference,
    );
    expect(find.text('あさって 08:30'), findsOneWidget);
  });

  testWidgets('降水確率30%の注意文を表示', (tester) async {
    await showCard(
      tester,
      adviceWith(risks: [risk(probability: 30)]),
      reference: reference,
    );
    await openRisks(tester);
    expect(find.text('最大降水確率 30%'), findsOneWidget);
  });

  testWidgets('降水確率60%の非推奨文を表示', (tester) async {
    await showCard(
      tester,
      adviceWith(
        risks: [risk(probability: 60, status: DryingStatus.notRecommended)],
      ),
      reference: reference,
    );
    await openRisks(tester);
    expect(find.text('最大降水確率 60%'), findsOneWidget);
  });

  testWidgets('実降水量ありの文章を表示', (tester) async {
    await showCard(
      tester,
      adviceWith(
        risks: [risk(precipitation: 0.2, status: DryingStatus.notRecommended)],
      ),
      reference: reference,
    );
    await openRisks(tester);
    expect(find.text('予想降水量 最大0.2mm'), findsOneWidget);
  });

  testWidgets('weather codeは一般UIに表示しない', (tester) async {
    await showCard(
      tester,
      adviceWith(
        risks: [
          risk(codes: const [61], status: DryingStatus.notRecommended),
        ],
      ),
      reference: reference,
    );
    await openRisks(tester);
    expect(find.textContaining('雨の可能性があります'), findsOneWidget);
    expect(find.textContaining('weather code'), findsNothing);
  });

  testWidgets('5m/s風の注意文を表示', (tester) async {
    await showCard(
      tester,
      adviceWith(
        risks: [risk(kind: WeatherRiskKind.wind, wind: 6, threshold: 5)],
      ),
      reference: reference,
    );
    await openRisks(tester);
    expect(find.text('16:30ごろから風が強まる見込みです'), findsOneWidget);
    expect(find.text('最大風速 6m/s程度'), findsOneWidget);
  });

  testWidgets('8m/s風の非推奨文を表示', (tester) async {
    await showCard(
      tester,
      adviceWith(
        risks: [
          risk(
            kind: WeatherRiskKind.wind,
            status: DryingStatus.notRecommended,
            wind: 9,
            threshold: 8,
          ),
        ],
      ),
      reference: reference,
    );
    await openRisks(tester);
    expect(find.text('16:30ごろから風が強まる見込みです'), findsOneWidget);
    expect(find.text('最大風速 9m/s程度'), findsOneWidget);
  });

  testWidgets('複数の風イベントは開始時刻と最大風速へ要約', (tester) async {
    await showCard(
      tester,
      adviceWith(
        risks: [
          risk(kind: WeatherRiskKind.wind, wind: 6, threshold: 5),
          risk(
            kind: WeatherRiskKind.wind,
            status: DryingStatus.notRecommended,
            wind: 9,
            threshold: 8,
          ),
        ],
      ),
      reference: reference,
    );
    await openRisks(tester);
    expect(find.text('16:30ごろから風が強まる見込みです'), findsOneWidget);
    expect(find.text('最大風速 9m/s程度'), findsOneWidget);
    expect(find.textContaining('以上になる見込み'), findsNothing);
  });

  testWidgets('夜間と翌日の予測へ低信頼表示を付ける', (tester) async {
    await showCard(
      tester,
      adviceWith(
        garments: [
          garmentAt(DateTime.utc(2026, 9, 18, 20), reference, 'night'),
          garmentAt(DateTime.utc(2026, 9, 19, 10), reference, 'tomorrow'),
        ],
      ),
      reference: reference,
    );
    expect(find.textContaining('夜間の再吸湿・結露'), findsNothing);
    await openAbout(tester);
    expect(find.textContaining('夜間の再吸湿・結露を考慮していないため'), findsOneWidget);
  });

  testWidgets('非推奨とunknownの混在は室内干しを主結論にする', (tester) async {
    await showCard(
      tester,
      adviceWith(
        garments: [
          garmentWithStatus(
            id: 'thin',
            completion: reference.add(const Duration(hours: 3)),
            start: reference,
            status: DryingStatus.notRecommended,
          ),
          unavailableGarment('thick'),
        ],
      ),
      reference: reference,
    );
    expect(find.text('室内干しがおすすめ'), findsOneWidget);
    expect(find.text('一部の衣類は判定できません（注意）'), findsNothing);
  });

  testWidgets('全カテゴリunknownの場合だけ今回は判定できませんと表示', (tester) async {
    await showCard(
      tester,
      adviceWith(
        garments: [
          unavailableGarment('thin'),
          unavailableGarment('normal'),
          unavailableGarment('thick'),
        ],
      ),
      reference: reference,
    );
    expect(find.text('今回は判定できません'), findsOneWidget);
    expect(find.text('室内干しがおすすめ'), findsNothing);
  });

  testWidgets('予報範囲外の衣類は故障に見えない短い文で表示', (tester) async {
    await showCard(
      tester,
      adviceWith(garments: [unavailableGarment('thick')]),
      reference: reference,
    );
    expect(find.text('乾燥予想　予報範囲外'), findsOneWidget);
    expect(find.text('予報範囲内では乾燥完了を確認できません'), findsOneWidget);
    expect(find.text('判定不能'), findsNothing);
  });

  testWidgets('雨の注意は要約を展開して表示', (tester) async {
    await showCard(
      tester,
      adviceWith(risks: [risk(precipitation: 0.2, probability: 60)]),
      reference: reference,
    );
    expect(find.text('雨・風の注意'), findsOneWidget);
    expect(find.text('最大降水確率 60%・予想降水量 最大0.2mm'), findsNothing);
    await openRisks(tester);
    expect(find.text('最大降水確率 60%・予想降水量 最大0.2mm'), findsOneWidget);
  });

  testWidgets('免責事項はこの予測についてを開くまで表示しない', (tester) async {
    await showCard(
      tester,
      adviceWith(
        garments: [
          garmentAt(reference.add(const Duration(hours: 2)), reference),
        ],
      ),
      reference: reference,
    );
    expect(find.text('この予測について'), findsOneWidget);
    expect(find.byKey(const Key('model-limitation')), findsNothing);
    await openAbout(tester);
    expect(find.byKey(const Key('model-limitation')), findsOneWidget);
    expect(
      find.text('・乾燥時間は公開データと理論式をもとにした目安で、素材・脱水・干し方により変わります。'),
      findsOneWidget,
    );
    expect(find.text('・雨による濡れ直しは乾燥時間へ計算していません。'), findsOneWidget);
    expect(find.text('・時刻は選択地点（UTC）の時刻です。'), findsOneWidget);
  });

  Future<void> pumpV9(WidgetTester tester, {bool withRainRisk = false}) async {
    final rows = List.generate(
      30,
      (index) => sample(
        reference.add(Duration(hours: index)),
        rain: withRainRisk && index == 2 ? 0.2 : 0,
        probability: withRainRisk && index == 2 ? 60 : 0,
        code: withRainRisk && index == 2 ? 61 : 0,
      ),
    );
    final api = _Api(
      ForecastResponse(
        series: ForecastSeries(
          cityName: '春日部',
          forecasts: rows,
          locationUtcOffset: Duration.zero,
          timezone: 'UTC',
        ),
        fetchedAt: reference,
        rawJson: '{}',
      ),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      WeatherApp(api: api, environmentStore: _Store(), now: () => reference),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('開始時点だけの判定をUIから削除', (tester) async {
    await pumpV9(tester);
    expect(find.text('開始時点だけの天気・判定'), findsNothing);
    expect(find.byKey(const Key('assessment-card')), findsNothing);
  });

  testWidgets('開始時刻チップは今からと6時間後までに限定', (tester) async {
    await pumpV9(tester);
    for (final hours in [0, 1, 2, 3, 6]) {
      expect(find.byKey(Key('offset-$hours')), findsOneWidget);
    }
    final chipTops = [0, 1, 2, 3, 6]
        .map((hours) => tester.getTopLeft(find.byKey(Key('offset-$hours'))).dy)
        .toSet();
    expect(chipTops, hasLength(1));
    for (final hours in [9, 12, 18, 24]) {
      expect(find.byKey(Key('offset-$hours')), findsNothing);
    }
    expect(find.text('+6h'), findsOneWidget);
  });

  testWidgets('カテゴリIDを維持して新しい表示名と代表例を表示', (tester) async {
    await pumpV9(tester);
    for (final item in [
      ('thin', '薄手', '肌着・靴下・速乾ウェア'),
      ('normal', '普通', '綿Tシャツ・シャツ・フェイスタオル'),
      ('thick', '厚手', 'パーカー・デニム・バスタオル'),
    ]) {
      expect(find.byKey(Key('garment-${item.$1}')), findsOneWidget);
      expect(find.text(item.$2), findsOneWidget);
      expect(find.text(item.$3), findsOneWidget);
    }
    expect(find.textContaining('パンツ'), findsNothing);
  });

  testWidgets('干し始め表示とOpen-Meteo帰属を簡潔に表示', (tester) async {
    await pumpV9(tester);
    expect(find.textContaining('干す予定'), findsNothing);
    expect(find.text('開始時刻 今日 17:00'), findsOneWidget);
    expect(find.textContaining('（端末時刻）'), findsNothing);
    expect(
      find.textContaining('Weather data: Open-Meteo · CC BY 4.0'),
      findsOneWidget,
    );
    expect(find.textContaining('https://open-meteo.com/'), findsNothing);
    expect(find.textContaining('取得データを表示用に加工しています'), findsOneWidget);
  });

  testWidgets('気象詳細はホーム最下部の導線から表示', (tester) async {
    await pumpV9(tester);
    expect(find.byKey(const Key('forecast-evidence')), findsNothing);
    expect(find.byKey(const Key('metric-temperature')), findsNothing);
    final detailsButton = find.byKey(const Key('forecast-details-button'));
    expect(find.text('予測の根拠を見る'), findsOneWidget);
    await tester.ensureVisible(detailsButton);
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forecast-evidence')), findsOneWidget);
    for (final key in [
      'metric-temperature',
      'metric-humidity',
      'metric-wind',
      'metric-probability',
      'evidence-precipitation',
      'evidence-solar',
      'evidence-forecast-time',
      'evidence-fetched-at',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
  });

  testWidgets('根拠を5セクションで表示し注意事項をシートで開く', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpV9(tester, withRainRisk: true);
    final detailsButton = find.byKey(const Key('forecast-details-button'));
    await tester.ensureVisible(detailsButton);
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();
    expect(find.text('雨・風の注意'), findsOneWidget);
    for (final title in ['気象データ', '干し始めの予報', '物干し環境', '乾燥時間について', '衣類カテゴリ']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.byType(DryingDetailsTile), findsOneWidget);
    final aboutButton = find.byKey(const Key('prediction-about-button'));
    await tester.ensureVisible(aboutButton);
    await tester.tap(aboutButton);
    await tester.pumpAndSettle();
    expect(find.text('予測の概要'), findsOneWidget);
    expect(find.text('乾燥時間は目安です'), findsOneWidget);
    expect(find.text('急な天気の変化に注意'), findsOneWidget);
    expect(find.text('衣類カテゴリについて'), findsOneWidget);
    expect(find.text('予測精度について'), findsOneWidget);
    expect(
      find.text('公開データと理論式をもとに予測しています。今後、実測データを用いた検証を進めます。'),
      findsOneWidget,
    );
    expect(find.byTooltip('閉じる'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '閉じる'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('API格子を一般UIに表示しない', (tester) async {
    await pumpV9(tester);
    expect(find.textContaining('API格子'), findsNothing);
  });

  test('診断トレースに区間乾燥量と累積値を保持', () {
    final rows = [
      sample(reference, temperature: 23.4, humidity: 72, wind: 2.2, solar: 0),
      sample(
        reference.add(const Duration(hours: 1)),
        temperature: 23.4,
        humidity: 72,
        wind: 2.2,
        solar: 128,
      ),
    ];
    final trace = DryingEstimator().traceDrying(
      series: ForecastSeries(
        cityName: '春日部',
        forecasts: rows,
        locationUtcOffset: Duration.zero,
      ),
      environment: environment,
      startTime: reference,
    );
    expect(trace, hasLength(1));
    expect(trace.single.vpd, closeTo(calculateVpd(23.4, 72)!, 1e-10));
    expect(trace.single.shortwaveRadiation, 128);
    expect(trace.single.cumulativeDrying, trace.single.intervalDryingAmount);
  });
}
