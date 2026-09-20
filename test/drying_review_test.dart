import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/drying_advice.dart';
import 'package:weather_app/drying_advice_card.dart';
import 'package:weather_app/drying_assessment.dart';
import 'package:weather_app/drying_estimator.dart';
import 'package:weather_app/drying_model_config.dart';
import 'package:weather_app/models/drying_environment.dart';
import 'package:weather_app/models/weather.dart';

import 'drying_estimator_test.dart' show environment, sample, seriesOf;

void main() {
  final start = DateTime.utc(2026, 9, 18, 11);
  final unitK = 1 / calculateVpd(25, 50)!;
  final sunny = 2 - math.exp(-1);
  final shaded = 2 - math.exp(-0.2);

  GarmentDryingEstimate estimate(
    List<HourlyForecast> rows, {
    double requiredDrying = 0.5,
    SunExposurePattern pattern = SunExposurePattern.allDay,
    Duration offset = Duration.zero,
    DateTime? from,
    int dayEndHour = 18,
  }) =>
      DryingEstimator(
            config: DryingModelConfig(
              k: unitK,
              provisionalDryingCalibrationFactor: 1,
              windAmplitude: 0,
              dayEndHour: dayEndHour,
              categories: [GarmentCategory('test', '試験', '', requiredDrying)],
            ),
          )
          .estimateDryingTime(
            series: seriesOf(rows, offset: offset),
            environment: DryingEnvironment(
              roofProtection: false,
              dryingPlace: DryingPlace.garden,
              windExposure: WindExposure.good,
              sunExposurePattern: pattern,
            ),
            startTime: from ?? rows.first.forecastTimeUtc,
          )
          .single;

  void durationIs(GarmentDryingEstimate result, double hours) {
    expect(result.status, DryingEstimateStatus.estimated);
    expect(
      result.estimatedDuration!.inMicroseconds / Duration.microsecondsPerHour,
      closeTo(hours, 1e-8),
    );
  }

  group('日射の時間窓', () {
    test('前の1時間の強い日射を現在区間へ混ぜない', () {
      durationIs(
        estimate([
          sample(start, solar: 1200),
          sample(start.add(const Duration(hours: 1)), solar: 0),
        ]),
        0.5,
      );
    });
    test('左端の日射欠損は対象区間の日射欠損ではない', () {
      durationIs(
        estimate([
          sample(start, solar: null),
          sample(start.add(const Duration(hours: 1)), solar: 300),
        ]),
        0.5 / sunny,
      );
    });
    test('右端の日射欠損は前の平均値で補わない', () {
      final result = estimate([
        sample(start, solar: 1000),
        sample(start.add(const Duration(hours: 1)), solar: null),
      ]);
      expect(result.status, DryingEstimateStatus.insufficientData);
      expect(result.estimatedCompletionTime, isNull);
    });
    test('時刻値由来の乾燥力を台形補間し区間日射を一定に掛ける', () {
      final result = estimate([
        sample(start, humidity: 100, solar: 0),
        sample(start.add(const Duration(hours: 1)), humidity: 0, solar: 300),
      ], requiredDrying: 0.8);
      durationIs(result, math.sqrt(0.8 / sunny));
    });
    test('次の区間の強い日射を完了前へ先取りしない', () {
      durationIs(
        estimate([
          sample(start, solar: 0),
          sample(start.add(const Duration(hours: 1)), solar: 0),
          sample(start.add(const Duration(hours: 2)), solar: 1500),
        ]),
        0.5,
      );
    });
    test('区間途中開始でも右端の平均値だけを使う', () {
      durationIs(
        estimate([
          sample(start, solar: 1500),
          sample(start.add(const Duration(hours: 1)), solar: 0),
        ], from: start.add(const Duration(minutes: 20))),
        0.5,
      );
    });
    for (final pattern in [
      SunExposurePattern.morningOnly,
      SunExposurePattern.afternoonOnly,
    ]) {
      test('$patternの11〜12時と12〜13時を取り違えない', () {
        final morning = pattern == SunExposurePattern.morningOnly;
        durationIs(
          estimate([
            sample(start, solar: 0),
            sample(start.add(const Duration(hours: 1)), solar: 300),
          ], pattern: pattern),
          0.5 / (morning ? sunny : shaded),
        );
        durationIs(
          estimate([
            sample(start.add(const Duration(hours: 1)), solar: 0),
            sample(start.add(const Duration(hours: 2)), solar: 300),
          ], pattern: pattern),
          0.5 / (morning ? shaded : sunny),
        );
      });
      test('$patternの現地正午が予報区間途中なら分割する', () {
        final morning = pattern == SunExposurePattern.morningOnly;
        durationIs(
          estimate(
            [
              sample(start, solar: 0),
              sample(start.add(const Duration(hours: 1)), solar: 300),
            ],
            offset: const Duration(minutes: 30),
            pattern: pattern,
            requiredDrying:
                (morning ? sunny : shaded) * 0.5 +
                (morning ? shaded : sunny) * 0.25,
          ),
          0.75,
        );
      });
    }
    test('現地正午ちょうどの途中開始に午前の日当たりを混ぜない', () {
      durationIs(
        estimate(
          [
            sample(start, solar: 0),
            sample(start.add(const Duration(hours: 1)), solar: 300),
          ],
          offset: const Duration(minutes: 30),
          pattern: SunExposurePattern.morningOnly,
          from: start.add(const Duration(minutes: 30)),
          requiredDrying: shaded / 4,
        ),
        0.25,
      );
    });
    for (final hour in [5, 6, 17, 18]) {
      test('$hour時からの区間に昼夜境界を正しく適用', () {
        final time = DateTime.utc(2026, 9, 18, hour);
        durationIs(
          estimate([
            sample(time, solar: 0),
            sample(time.add(const Duration(hours: 1)), solar: 300),
          ]),
          0.5 / (hour == 6 || hour == 17 ? sunny : 1),
        );
      });
    }
    test('日付跨ぎの日当たり境界も分割する', () {
      final time = DateTime.utc(2026, 9, 18, 23, 30);
      durationIs(
        estimate(
          [
            sample(time, solar: 0),
            sample(time.add(const Duration(hours: 1)), solar: 300),
          ],
          dayEndHour: 24,
          requiredDrying: sunny * 0.5 + 0.25,
        ),
        0.75,
      );
    });
    test('1時間平均と対応しない予報間隔は推定しない', () {
      expect(
        estimate([
          sample(start),
          sample(start.add(const Duration(minutes: 30))),
        ]).status,
        DryingEstimateStatus.insufficientData,
      );
    });
  });

  DryingAdvice advise(
    List<HourlyForecast> rows, {
    List<GarmentCategory> categories = const [
      GarmentCategory('thin', '薄手', '', 1),
      GarmentCategory('normal', '普通', '', 2),
      GarmentCategory('thick', '厚手', '', 6),
    ],
    Duration margin = const Duration(minutes: 30),
  }) =>
      DryingAdvisor(
        config: DryingModelConfig(
          k: unitK,
          windAmplitude: 0,
          solarAmplitude: 0,
          categories: categories,
          safetyMargin: margin,
        ),
      ).advise(
        series: seriesOf(rows),
        environment: environment,
        startTime: start,
        now: start,
        fetchedAt: start,
      );

  List<HourlyForecast> calm(int count) => List.generate(
    count,
    (i) => sample(start.add(Duration(hours: i)), solar: 0),
  );

  group('部分的な判定不能', () {
    test('薄手・普通OKと厚手unknownは総合注意とカテゴリ名付き理由', () {
      final result = advise(calm(5));
      expect(result.garments.map((g) => g.status), [
        DryingStatus.suitable,
        DryingStatus.suitable,
        DryingStatus.unknown,
      ]);
      expect(result.overallStatus, DryingStatus.caution);
      expect(result.detailMessages.join(), contains('厚手は予報範囲内で判定できません'));
      expect(result.garments.first.estimate.estimatedCompletionTime, isNotNull);
    });
    test('全カテゴリunknownのときだけ総合判定不能', () {
      final result = advise([sample(start)]);
      expect(
        result.garments.every((g) => g.status == DryingStatus.unknown),
        isTrue,
      );
      expect(result.overallStatus, DryingStatus.unknown);
    });
    test('非推奨とunknownが混在しても危険情報を残す', () {
      final rows = calm(5);
      rows[2] = sample(start.add(const Duration(hours: 2)), rain: 1);
      final result = advise(
        rows,
        categories: const [
          GarmentCategory('thin', '薄手', '', 1.5),
          GarmentCategory('normal', '普通', '', 2),
          GarmentCategory('thick', '厚手', '', 6),
        ],
      );
      expect(result.overallStatus, DryingStatus.caution);
      expect(result.garments.first.status, DryingStatus.notRecommended);
      expect(result.detailMessages.join(), contains('室内干し'));
      expect(result.detailMessages.join(), contains('厚手は予報範囲内'));
    });
  });

  List<WeatherRisk> windRisks(double? a, double? b, {Duration? gap}) {
    final rows = [
      sample(start, wind: a),
      sample(start.add(gap ?? const Duration(hours: 1)), wind: b),
    ];
    rows.addAll(
      List.generate(
        7,
        (i) => sample(
          start.add((gap ?? const Duration(hours: 1)) + Duration(hours: i + 1)),
          wind: b,
        ),
      ),
    );
    return DryingAdvisor()
        .assessWeatherRisks(rows)
        .where((r) => r.kind == WeatherRiskKind.wind)
        .toList();
  }

  group('風速到達時刻', () {
    test('4→6m/sの注意開始は30分後', () {
      expect(
        windRisks(4, 6).first.riskStartTime,
        start.add(const Duration(minutes: 30)),
      );
      expect(
        windRisks(4, 6).every((r) => r.status == DryingStatus.caution),
        isTrue,
      );
    });
    test('7→9m/sの非推奨開始は30分後、直前までは注意', () {
      final risks = windRisks(7, 9);
      expect(risks.first.status, DryingStatus.caution);
      expect(risks.first.riskStartTime, start);
      expect(risks.first.endTime, start.add(const Duration(minutes: 30)));
      expect(risks.last.status, DryingStatus.notRecommended);
      expect(risks.last.riskStartTime, start.add(const Duration(minutes: 30)));
    });
    test('4→9m/sで5と8の両到達時刻を保持', () {
      final risks = windRisks(4, 9);
      expect(risks.first.riskStartTime, start.add(const Duration(minutes: 12)));
      expect(risks.last.riskStartTime, start.add(const Duration(minutes: 48)));
    });
    test('閾値をまたがず5未満ならリスクなし', () => expect(windRisks(2, 4), isEmpty));
    test('閾値をまたがず5以上なら開始時から注意', () {
      final risk = windRisks(6, 7).single;
      expect(risk.status, DryingStatus.caution);
      expect(risk.riskStartTime, start);
    });
    test('一定8m/sでもゼロ除算せず非推奨', () {
      expect(windRisks(8, 8).single.status, DryingStatus.notRecommended);
    });
    test('9→7m/sは非推奨区間が30分後に終わる', () {
      final risks = windRisks(9, 7);
      expect(risks.first.status, DryingStatus.notRecommended);
      expect(risks.first.endTime, start.add(const Duration(minutes: 30)));
      expect(risks.last.status, DryingStatus.caution);
    });
    test('8m/sに触れて下がる瞬間の非推奨を重複せず保持', () {
      final rows = calm(9);
      rows[1] = sample(start.add(const Duration(hours: 1)), wind: 8);
      final risks = advise(rows).weatherRisks
          .where(
            (r) =>
                r.kind == WeatherRiskKind.wind &&
                r.status == DryingStatus.notRecommended,
          )
          .toList();
      expect(risks, hasLength(1));
      expect(risks.single.riskStartTime, start.add(const Duration(hours: 1)));
      expect(risks.single.endTime, risks.single.riskStartTime);
    });
    for (final invalid in <double?>[
      null,
      double.nan,
      double.infinity,
      -1,
      151,
    ]) {
      test('不正風速$invalidから到達時刻を補間しない', () {
        final risks = windRisks(invalid, 9);
        expect(risks, hasLength(1));
        expect(
          risks.every(
            (r) =>
                !r.riskStartTime.isBefore(start.add(const Duration(hours: 1))),
          ),
          isTrue,
        );
      });
    }
    test('2時間の穴をまたいで補間しない', () {
      expect(
        windRisks(4, 9, gap: const Duration(hours: 2)).single.riskStartTime,
        start.add(const Duration(hours: 2)),
      );
    });
    test('8m/s到達前の完了を区間統合で非推奨へ繰り上げない', () {
      final rows = [
        sample(start, wind: 7),
        ...List.generate(
          8,
          (i) => sample(start.add(Duration(hours: i + 1)), wind: 9),
        ),
      ];
      final result = advise(
        rows,
        margin: Duration.zero,
        categories: const [GarmentCategory('thin', '薄手', '', 0.25)],
      );
      expect(result.garments.single.status, DryingStatus.caution);
    });
  });

  group('雨リスクの統合', () {
    test('降水量・確率・天気コードと連続区間を一つに統合', () {
      final rows = calm(9);
      rows[1] = sample(
        start.add(const Duration(hours: 1)),
        rain: 1,
        probability: 60,
        code: 61,
      );
      rows[2] = sample(
        start.add(const Duration(hours: 2)),
        rain: 1,
        probability: 60,
      );
      final risks = advise(
        rows,
      ).weatherRisks.where((r) => r.kind == WeatherRiskKind.rain).toList();
      expect(risks, hasLength(1));
      expect(risks.single.riskStartTime, start);
      expect(risks.single.endTime, start.add(const Duration(hours: 2)));
      expect(risks.single.status, DryingStatus.notRecommended);
      expect(risks.single.precipitationMm, 1);
      expect(risks.single.precipitationProbabilityPct, 60);
      expect(risks.single.weatherCodes, [61]);
    });
    test('同じ区間のcautionとnotRecommendedは強い方を保持', () {
      final rows = calm(9);
      rows[0] = sample(start, code: 61);
      rows[1] = sample(start.add(const Duration(hours: 1)), probability: 30);
      final risks = advise(
        rows,
      ).weatherRisks.where((r) => r.kind == WeatherRiskKind.rain).toList();
      expect(risks, hasLength(1));
      expect(risks.single.status, DryingStatus.notRecommended);
      expect(risks.single.precipitationProbabilityPct, 30);
      expect(risks.single.weatherCodes, [61]);
    });
    test('連続する注意と非推奨はseverityの変更時刻を保持', () {
      final rows = calm(9);
      rows[1] = sample(start.add(const Duration(hours: 1)), probability: 30);
      rows[2] = sample(start.add(const Duration(hours: 2)), rain: 1);
      final risks = advise(
        rows,
      ).weatherRisks.where((r) => r.kind == WeatherRiskKind.rain).toList();
      expect(risks.map((r) => r.status), [
        DryingStatus.caution,
        DryingStatus.notRecommended,
      ]);
      expect(risks.last.riskStartTime, start.add(const Duration(hours: 1)));
    });
    test('離れた雨イベントを間の晴れ時間ごと統合しない', () {
      final rows = calm(9);
      rows[1] = sample(start.add(const Duration(hours: 1)), rain: 1);
      rows[4] = sample(start.add(const Duration(hours: 4)), rain: 1);
      final risks = advise(
        rows,
      ).weatherRisks.where((r) => r.kind == WeatherRiskKind.rain).toList();
      expect(risks, hasLength(2));
      expect(risks.first.endTime.isBefore(risks.last.riskStartTime), isTrue);
    });
  });

  Future<void> showAdvice(WidgetTester tester, DryingAdvice advice) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                DryingAdviceCard(
                  advice: advice,
                  locationUtcOffset: Duration.zero,
                  referenceTime: start,
                ),
                if (advice.weatherRisks.isNotEmpty)
                  WeatherRiskDetails(
                    risks: advice.weatherRisks,
                    locationUtcOffset: Duration.zero,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('部分unknownのカードに注意・厚手の理由・既知の完了時刻を残す', (tester) async {
    final result = advise(calm(5));
    await showAdvice(tester, result);
    expect(find.text('外干しできますが注意'), findsOneWidget);
    expect(find.text('予報範囲内では乾燥完了を確認できません'), findsOneWidget);
    expect(find.text('今日 11:42'), findsOneWidget);
    expect(find.text('今日 12:25'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('重複した雨入力でもカードの雨開始メッセージは一つ', (tester) async {
    final rows = calm(9);
    rows[1] = sample(
      start.add(const Duration(hours: 1)),
      rain: 1,
      probability: 60,
      code: 61,
    );
    rows[2] = sample(start.add(const Duration(hours: 2)), rain: 1);
    await showAdvice(tester, advise(rows));
    final details = find.byKey(const Key('weather-risk-details'));
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('最大降水確率 60%・予想降水量 最大1mm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
