import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/drying_advice.dart';
import 'package:weather_app/drying_assessment.dart';
import 'package:weather_app/drying_estimator.dart';
import 'package:weather_app/drying_model_config.dart';
import 'package:weather_app/models/drying_environment.dart';
import 'package:weather_app/models/weather.dart';

import 'drying_estimator_test.dart' show environment, sample, seriesOf;

void main() {
  final start = DateTime.utc(2026, 9, 18, 9);
  // 乾燥力を1/時に固定し、時間窓と安全判定だけを検証する。
  final advisor = DryingAdvisor(
    config: DryingModelConfig(
      k: 1 / calculateVpd(25, 50)!,
      windAmplitude: 0,
      solarAmplitude: 0,
      categories: const [
        GarmentCategory('thin', '薄手', '', 1.5),
        GarmentCategory('normal', '普通', '', 2.75),
        GarmentCategory('thick', '厚手', '', 4.5),
      ],
    ),
  );
  List<HourlyForecast> rows({
    int? rainAt,
    int? probabilityAt,
    double probability = 60,
    int? windAt,
    double wind = 8,
    int? codeAt,
    int code = 61,
    int? missingAt,
    bool missingSolar = false,
  }) => List.generate(
    9,
    (i) => sample(
      start.add(Duration(hours: i)),
      rain: i == rainAt ? 1 : 0,
      probability: i == missingAt
          ? null
          : i == probabilityAt
          ? probability
          : 0,
      wind: i == windAt ? wind : 2,
      code: i == codeAt ? code : 0,
      solar: missingSolar ? null : 500,
    ),
  );
  DryingAdvice advise(
    List<HourlyForecast> input, {
    bool roof = false,
    DateTime? now,
    DateTime? fetchedAt,
  }) => advisor.advise(
    series: seriesOf(input),
    environment: DryingEnvironment(
      roofProtection: roof,
      dryingPlace: environment.dryingPlace,
      windExposure: environment.windExposure,
      sunExposurePattern: environment.sunExposurePattern,
    ),
    startTime: start,
    now: now ?? start,
    fetchedAt: fetchedAt ?? start,
  );

  test('雨も強風もない場合は全カテゴリOK', () {
    final result = advise(rows());
    expect(result.overallStatus, DryingStatus.suitable);
    expect(
      result.garments.every((g) => g.status == DryingStatus.suitable),
      isTrue,
    );
    expect(result.weatherRisks, isEmpty);
  });
  test(
    '完了から十分後の雨はOK',
    () => expect(advise(rows(rainAt: 7)).overallStatus, DryingStatus.suitable),
  );
  test('薄手・普通は乾き、厚手の前に雨なら総合注意', () {
    final result = advise(rows(rainAt: 4));
    expect(result.overallStatus, DryingStatus.caution);
    expect(result.garments.map((g) => g.status), [
      DryingStatus.suitable,
      DryingStatus.suitable,
      DryingStatus.notRecommended,
    ]);
    expect(
      result.weatherRisks.first.riskStartTime,
      start.add(const Duration(hours: 3)),
    );
    expect(result.detailMessages.join(), contains('厚手は室内干し'));
  });
  test(
    '薄手の完了前から雨なら全カテゴリ非推奨',
    () => expect(
      advise(rows(rainAt: 2)).overallStatus,
      DryingStatus.notRecommended,
    ),
  );
  test('薄手の完了30分後に雨が始まる場合も注意', () {
    final marginAdvisor = DryingAdvisor(
      config: DryingModelConfig(
        k: 1 / calculateVpd(25, 50)!,
        windAmplitude: 0,
        solarAmplitude: 0,
        categories: const [GarmentCategory('thin', '薄手', '', 2.1)],
      ),
    );
    final result = marginAdvisor.advise(
      series: seriesOf(rows(rainAt: 3)),
      environment: environment,
      startTime: start,
      now: start,
      fetchedAt: start,
    );
    expect(result.garments.first.status, DryingStatus.caution);
    expect(result.garments.first.reasons.join(), contains('余裕'));
  });
  test('確率も直前1時間の先頭から評価', () {
    final result = advise(rows(probabilityAt: 2));
    expect(result.overallStatus, DryingStatus.notRecommended);
    expect(
      result.weatherRisks.first.sourceTime,
      start.add(const Duration(hours: 2)),
    );
    expect(
      result.weatherRisks.first.riskStartTime,
      start.add(const Duration(hours: 1)),
    );
  });
  for (final item in [
    (29.999, DryingStatus.suitable),
    (30.0, DryingStatus.caution),
    (59.999, DryingStatus.caution),
    (60.0, DryingStatus.notRecommended),
  ]) {
    test(
      '確率の境界${item.$1}',
      () => expect(
        advise(rows(probabilityAt: 1, probability: item.$1)).overallStatus,
        item.$2,
      ),
    );
  }
  for (final item in [
    (4.999, DryingStatus.suitable),
    (5.0, DryingStatus.caution),
    (7.999, DryingStatus.caution),
    (8.0, DryingStatus.notRecommended),
  ]) {
    test(
      '風の境界${item.$1}',
      () =>
          expect(advise(rows(windAt: 1, wind: item.$1)).overallStatus, item.$2),
    );
  }
  for (final code in [51, 61, 71, 95, 99]) {
    test(
      '雨量0でも降水コード$codeは非推奨',
      () => expect(
        advise(rows(codeAt: 1, code: code)).overallStatus,
        DryingStatus.notRecommended,
      ),
    );
  }
  test('屋根で雨リスクを無効化しない', () {
    final withRoof = advise(rows(rainAt: 2), roof: true);
    final withoutRoof = advise(rows(rainAt: 2));
    expect(withRoof.overallStatus, withoutRoof.overallStatus);
    expect(withRoof.detailMessages.join(), contains('軽減'));
    expect(withRoof.detailMessages.join(), contains('吹き込み'));
  });
  test('風通しが悪くても8m/sの安全判定は下げない', () {
    final result = advisor.advise(
      series: seriesOf(rows(windAt: 1)),
      environment: const DryingEnvironment(
        roofProtection: true,
        dryingPlace: DryingPlace.enclosedBalcony,
        windExposure: WindExposure.poor,
        sunExposurePattern: SunExposurePattern.shaded,
      ),
      startTime: start,
      now: start,
      fetchedAt: start,
    );
    expect(result.overallStatus, DryingStatus.notRecommended);
  });
  test(
    '乾燥力の欠損は判定不能',
    () => expect(
      advise(rows(missingSolar: true)).overallStatus,
      DryingStatus.unknown,
    ),
  );
  test(
    '乾燥力欠損でも開始時の独立した危険を保持',
    () => expect(
      advise(rows(missingSolar: true, windAt: 0)).overallStatus,
      DryingStatus.notRecommended,
    ),
  );
  test('雨・風のデータ欠損は乾燥時間を残して判定不能', () {
    final result = advise(rows(missingAt: 1));
    expect(result.overallStatus, DryingStatus.unknown);
    expect(result.garments.first.estimate.estimatedCompletionTime, isNotNull);
  });
  test('薄手以降の欠損を薄手のOKだけで総合OKにしない', () {
    final result = advise(rows(missingAt: 4));
    expect(result.garments.first.status, DryingStatus.suitable);
    expect(result.overallStatus, DryingStatus.caution);
  });
  test(
    '未知の天気コードは判定不能',
    () => expect(
      advise(rows(codeAt: 1, code: 123)).overallStatus,
      DryingStatus.unknown,
    ),
  );
  test(
    '危険な雨は他のリスクデータ欠損より優先',
    () => expect(
      advise(rows(rainAt: 2, missingAt: 1)).overallStatus,
      DryingStatus.notRecommended,
    ),
  );
  test('完了しても余裕時間の予報が足りなければOKにしない', () {
    final result = advise(rows().take(3).toList());
    expect(result.garments.first.status, DryingStatus.suitable);
    expect(result.overallStatus, DryingStatus.caution);
  });
  test('期限超過した取得データでは結果を非表示', () {
    final result = advise(
      rows(),
      fetchedAt: start.subtract(const Duration(hours: 3, seconds: 1)),
    );
    expect(result.overallStatus, DryingStatus.unknown);
    expect(
      result.garments.every((g) => g.estimate.estimatedCompletionTime == null),
      isTrue,
    );
  });
  test(
    '取得から3時間ちょうどは許容',
    () => expect(
      advise(
        rows(),
        fetchedAt: start.subtract(const Duration(hours: 3)),
      ).overallStatus,
      DryingStatus.suitable,
    ),
  );
  test(
    '未来の取得時刻は判定不能',
    () => expect(
      advise(
        rows(),
        fetchedAt: start.add(const Duration(minutes: 6)),
      ).overallStatus,
      DryingStatus.unknown,
    ),
  );
  test(
    '開始時刻を過ぎたら判定不能',
    () => expect(
      advise(rows(), now: start.add(const Duration(seconds: 1))).overallStatus,
      DryingStatus.unknown,
    ),
  );
  test('完了直前・同時の危険は非推奨', () {
    final custom = DryingAdvisor(
      config: DryingModelConfig(
        k: 1 / calculateVpd(25, 50)!,
        windAmplitude: 0,
        solarAmplitude: 0,
        categories: const [
          GarmentCategory('a', 'A', '', 1),
          GarmentCategory('b', 'B', '', 1.1),
        ],
      ),
    );
    final result = custom.advise(
      series: seriesOf(rows(rainAt: 1)),
      environment: environment,
      startTime: start,
      now: start,
      fetchedAt: start,
    );
    expect(result.overallStatus, DryingStatus.notRecommended);
  });
}
