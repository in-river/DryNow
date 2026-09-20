import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/drying_estimator.dart';
import 'package:weather_app/drying_model_config.dart';
import 'package:weather_app/models/drying_environment.dart';
import 'package:weather_app/models/weather.dart';

const environment = DryingEnvironment(
  roofProtection: false,
  dryingPlace: DryingPlace.garden,
  windExposure: WindExposure.good,
  sunExposurePattern: SunExposurePattern.allDay,
);

HourlyForecast sample(
  DateTime time, {
  double? temperature = 25,
  double? humidity = 50,
  double? wind = 2,
  double? solar = 500,
  double? rain = 0,
  double? probability = 0,
  int? code = 0,
}) => HourlyForecast(
  forecastTimeUtc: time,
  temperature: temperature,
  humidity: humidity,
  windSpeed: wind,
  solarRadiation: solar,
  precipitationMm: rain,
  precipitationProbability: probability,
  weatherCode: code,
);

ForecastSeries seriesOf(
  List<HourlyForecast> rows, {
  Duration? offset = Duration.zero,
}) => ForecastSeries(
  cityName: 'テスト地点',
  forecasts: rows,
  locationUtcOffset: offset,
  timezone: 'UTC',
);

void main() {
  final estimator = DryingEstimator();
  final start = DateTime.utc(2026, 9, 18, 9);
  group('VPD', () {
    for (final item in [
      (25.0, 50.0, 1.5839),
      (20.0, 60.0, 0.9353),
      (0.0, 50.0, 0.3054),
      (30.0, 80.0, 0.8486),
    ]) {
      test(
        '温度${item.$1} 湿度${item.$2}',
        () => expect(calculateVpd(item.$1, item.$2), closeTo(item.$3, 0.001)),
      );
    }
    test(
      'RH0は飽和水蒸気圧',
      () => expect(calculateVpd(25, 0), closeTo(3.1678, 0.001)),
    );
    test('RH100はゼロ', () => expect(calculateVpd(25, 100), 0));
    for (final value in <double?>[
      null,
      -1,
      101,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('不正湿度$value', () => expect(calculateVpd(25, value), isNull));
    }
    for (final value in <double?>[
      null,
      -101,
      71,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('不正温度$value', () => expect(calculateVpd(value, 50), isNull));
    }
  });
  group('風', () {
    for (final wind in [0.0, 1.0, 2.0, 5.0, 8.0]) {
      test(
        '$wind m/sで飽和式',
        () => expect(
          estimator.calculateWindFactor(wind),
          closeTo(2 - math.exp(-wind / 1.5), 1e-12),
        ),
      );
    }
    test('低風速域の増分が大きく、高風速域では飽和する', () {
      double f(double v) => estimator.calculateWindFactor(v)!;
      expect(f(2) - f(0), greaterThan(f(8) - f(5)));
      expect(f(150), closeTo(2, 1e-10));
    });
    for (final item in [
      (WindExposure.good, 2.0),
      (WindExposure.normal, 1.4),
      (WindExposure.poor, 0.8),
    ]) {
      test(
        '風通し${item.$1}',
        () => expect(estimator.calculateEffectiveWind(2, item.$1), item.$2),
      );
    }
    for (final value in <double?>[null, -1, 151, double.nan, double.infinity]) {
      test(
        '不正風速$value',
        () => expect(
          estimator.calculateEffectiveWind(value, WindExposure.good),
          isNull,
        ),
      );
    }
  });
  group('日射', () {
    for (final solar in [0.0, 50.0, 500.0, 1000.0]) {
      test(
        '$solar W/m²',
        () => expect(
          estimator.calculateSolarFactor(solar),
          closeTo(2 - math.exp(-solar / 300), 1e-12),
        ),
      );
    }
    test('強い日射で増分が小さくなる', () {
      double f(double v) => estimator.calculateSolarFactor(v)!;
      expect(f(500) - f(0), greaterThan(f(1000) - f(500)));
    });
    for (final item in [
      (SunExposurePattern.allDay, 500.0, 500.0),
      (SunExposurePattern.morningOnly, 500.0, 100.0),
      (SunExposurePattern.afternoonOnly, 100.0, 500.0),
      (SunExposurePattern.shaded, 100.0, 100.0),
    ]) {
      test('日当たり${item.$1}', () {
        expect(estimator.calculateEffectiveSolar(500, item.$1, start), item.$2);
        expect(
          estimator.calculateEffectiveSolar(
            500,
            item.$1,
            DateTime.utc(2026, 9, 18, 12),
          ),
          item.$3,
        );
      });
    }
    test(
      '夜間の補正はゼロ',
      () => expect(
        estimator.calculateEffectiveSolar(
          100,
          SunExposurePattern.allDay,
          DateTime.utc(2026, 9, 18, 23),
        ),
        0,
      ),
    );
    for (final value in <double?>[
      null,
      -1,
      1501,
      double.nan,
      double.infinity,
    ]) {
      test(
        '不正日射$value',
        () => expect(
          estimator.calculateEffectiveSolar(
            value,
            SunExposurePattern.allDay,
            start,
          ),
          isNull,
        ),
      );
    }
  });
  group('乾燥力', () {
    double? power(HourlyForecast row, [DryingEnvironment env = environment]) =>
        estimator.calculateDryingPower(row, env, Duration.zero);
    test(
      '代表条件で式の積になる',
      () => expect(
        power(sample(start)),
        closeTo(
          0.1 *
              calculateVpd(25, 50)! *
              (2 - math.exp(-2 / 1.5)) *
              (2 - math.exp(-500 / 300)) *
              1.4,
          1e-10,
        ),
      ),
    );
    test('暫定キャリブレーションを最終DryingPowerへ1.4倍で適用', () {
      final withoutCalibration = DryingEstimator(
        config: const DryingModelConfig(provisionalDryingCalibrationFactor: 1),
      );
      final input = sample(start);
      final base = withoutCalibration.calculateDryingPower(
        input,
        environment,
        Duration.zero,
      )!;
      expect(power(input), closeTo(base * 1.4, 1e-12));
    });
    for (final item in [
      ('高湿度', sample(start, humidity: 90)),
      ('低温', sample(start, temperature: 0)),
      ('無風', sample(start, wind: 0)),
      ('日射なし', sample(start, solar: 0)),
    ]) {
      test('${item.$1}でも非負で基準より遅い', () {
        expect(power(item.$2), greaterThanOrEqualTo(0));
        expect(power(item.$2), lessThan(power(sample(start))!));
      });
    }
    test('飽和湿度では乾燥量ゼロ', () => expect(power(sample(start, humidity: 100)), 0));
    test(
      '場所と屋根は乾燥力へ二重掛けしない',
      () => expect(
        power(
          sample(start),
          const DryingEnvironment(
            roofProtection: true,
            dryingPlace: DryingPlace.enclosedBalcony,
            windExposure: WindExposure.good,
            sunExposurePattern: SunExposurePattern.allDay,
          ),
        ),
        power(sample(start)),
      ),
    );
    test('端末の時差でなく地点の時差を使う', () {
      const env = DryingEnvironment(
        roofProtection: false,
        dryingPlace: DryingPlace.garden,
        windExposure: WindExposure.good,
        sunExposurePattern: SunExposurePattern.morningOnly,
      );
      final row = sample(DateTime.utc(2026, 9, 18, 3, 30));
      expect(
        estimator.calculateDryingPower(row, env, const Duration(hours: 9)),
        greaterThan(estimator.calculateDryingPower(row, env, Duration.zero)!),
      );
      expect(
        estimator.calculateDryingPower(row, env, const Duration(hours: 8)),
        greaterThan(
          estimator.calculateDryingPower(row, env, const Duration(hours: 9))!,
        ),
      );
    });
  });
  group('積算と補間', () {
    test(
      '台形面積 0.3→0.5を1時間',
      () => expect(
        estimator.integrateDrying(0.3, 0.5, const Duration(hours: 1)),
        closeTo(0.4, 1e-12),
      ),
    );
    test(
      '不正区間は拒否',
      () => expect(
        () => estimator.integrateDrying(-1, 1, const Duration(hours: 1)),
        throwsArgumentError,
      ),
    );
    List<GarmentDryingEstimate> estimate(
      List<HourlyForecast> rows, {
      DateTime? from,
      Duration? offset = Duration.zero,
    }) => estimator.estimateDryingTime(
      series: seriesOf(rows, offset: offset),
      environment: environment,
      startTime: from ?? start,
    );
    final rows = List.generate(
      30,
      (i) => sample(start.add(Duration(hours: i)), solar: 0),
    );
    test('一定条件の完了時間は必要量/乾燥力、3カテゴリは順序通り', () {
      final result = estimate(rows);
      final power = estimator.calculateDryingPower(
        rows.first,
        environment,
        Duration.zero,
      )!;
      for (final item in result) {
        expect(item.status, DryingEstimateStatus.estimated);
        expect(
          item.estimatedDuration!.inMicroseconds / Duration.microsecondsPerHour,
          closeTo(item.category.requiredDrying / power, 1e-8),
        );
      }
      expect(
        result[0].estimatedDuration,
        lessThan(result[1].estimatedDuration!),
      );
      expect(
        result[1].estimatedDuration,
        lessThan(result[2].estimatedDuration!),
      );
    });
    test('変化する乾燥力の区間途中は積分の逆算と一致', () {
      final custom = DryingEstimator(
        config: const DryingModelConfig(
          k: 1,
          windAmplitude: 0,
          solarAmplitude: 0,
          categories: [GarmentCategory('test', '試験', '', 0.75)],
        ),
      );
      final pressure = calculateVpd(25, 0)!;
      final input = [
        sample(start, humidity: 100),
        sample(
          start.add(const Duration(hours: 1)),
          humidity: 100 * (1 - 2 / pressure),
        ),
      ];
      final result = custom
          .estimateDryingTime(
            series: seriesOf(input),
            environment: environment,
            startTime: start,
          )
          .single;
      expect(
        result.estimatedDuration!.inMicroseconds / Duration.microsecondsPerHour,
        closeTo(math.sqrt(0.75 / 1.4), 1e-8),
      );
    });
    test('暫定キャリブレーションありは補正なし相当より早く完了', () {
      final withoutCalibration =
          DryingEstimator(
            config: const DryingModelConfig(
              provisionalDryingCalibrationFactor: 1,
            ),
          ).estimateDryingTime(
            series: seriesOf(rows),
            environment: environment,
            startTime: start,
          );
      final calibrated = estimate(rows);
      for (var index = 0; index < calibrated.length; index++) {
        expect(
          calibrated[index].estimatedCompletionTime!.isBefore(
            withoutCalibration[index].estimatedCompletionTime!,
          ),
          isTrue,
        );
      }
    });
    test('途中開始は経過した乾燥量を含めない', () {
      final a = estimate(rows);
      final b = estimate(rows, from: start.add(const Duration(minutes: 23)));
      expect(b.first.estimatedDuration, a.first.estimatedDuration);
      expect(
        b.first.estimatedCompletionTime!.difference(
          a.first.estimatedCompletionTime!,
        ),
        const Duration(minutes: 23),
      );
    });
    test('夜間・日付跨ぎでも継続し、日射0を欠損にしない', () {
      final night = DateTime.utc(2026, 9, 18, 23);
      final result = estimate(
        List.generate(
          25,
          (i) => sample(night.add(Duration(hours: i)), solar: 0),
        ),
        from: night,
      );
      expect(result.last.estimatedCompletionTime!.day, 19);
    });
    test('湿度100%で予報内に完了しなければ時刻なし', () {
      final result = estimate(
        List.generate(
          25,
          (i) => sample(start.add(Duration(hours: i)), humidity: 100),
        ),
      );
      expect(
        result.every(
          (r) =>
              r.status == DryingEstimateStatus.forecastLimit &&
              r.estimatedCompletionTime == null,
        ),
        isTrue,
      );
    });
    for (final item in <String, List<HourlyForecast>>{
      '空': [],
      '1点': [sample(start)],
      '重複': [sample(start), sample(start)],
      '逆順': [sample(start.add(const Duration(hours: 1))), sample(start)],
      '2時間の穴': [sample(start), sample(start.add(const Duration(hours: 2)))],
      '日射欠損': [
        sample(start),
        sample(start.add(const Duration(hours: 1)), solar: null),
      ],
      'NaN湿度': [
        sample(start, humidity: double.nan),
        sample(start.add(const Duration(hours: 1))),
      ],
    }.entries) {
      test(
        '${item.key}を補完しない',
        () => expect(
          estimate(
            item.value,
          ).every((r) => r.status == DryingEstimateStatus.insufficientData),
          isTrue,
        ),
      );
    }
    test(
      '地点の時差不明で推定しない',
      () => expect(
        estimate(rows, offset: null).first.status,
        DryingEstimateStatus.insufficientData,
      ),
    );
    test('予報の前や後へ外挿しない', () {
      expect(
        estimate(
          rows,
          from: start.subtract(const Duration(minutes: 1)),
        ).first.status,
        DryingEstimateStatus.insufficientData,
      );
      expect(
        estimate(rows, from: rows.last.forecastTimeUtc).first.status,
        DryingEstimateStatus.insufficientData,
      );
    });
    test('先に乾いたカテゴリは後の欠損で失わない', () {
      final result = estimate([
        ...rows.take(4),
        sample(start.add(const Duration(hours: 4)), solar: null),
      ]);
      expect(result.first.status, DryingEstimateStatus.estimated);
      expect(result.last.status, DryingEstimateStatus.insufficientData);
    });
    test('4カテゴリへ設定だけで拡張できる', () {
      final result =
          DryingEstimator(
            config: const DryingModelConfig(
              categories: [
                GarmentCategory('a', 'A', '', 0.1),
                GarmentCategory('b', 'B', '', 0.2),
                GarmentCategory('c', 'C', '', 0.3),
                GarmentCategory('d', 'D', '', 0.4),
              ],
            ),
          ).estimateDryingTime(
            series: seriesOf(rows),
            environment: environment,
            startTime: start,
          );
      expect(result, hasLength(4));
      expect(
        result.every((r) => r.status == DryingEstimateStatus.estimated),
        isTrue,
      );
    });
  });
  group('設定の検証', () {
    test('既定係数・カテゴリID・RequiredDryingを維持', () {
      const config = DryingModelConfig();
      expect(config.provisionalDryingCalibrationFactor, 1.4);
      expect(config.k, 0.1);
      expect(config.windAmplitude, 1);
      expect(config.windScale, 1.5);
      expect(config.solarAmplitude, 1);
      expect(config.solarScale, 300);
      expect(config.categories.map((category) => category.id), [
        'thin',
        'normal',
        'thick',
      ]);
      expect(config.categories.map((category) => category.requiredDrying), [
        0.8,
        1.2,
        1.8,
      ]);
    });
    for (final config in [
      const DryingModelConfig(k: 0),
      const DryingModelConfig(provisionalDryingCalibrationFactor: 0),
      const DryingModelConfig(windScale: 0),
      const DryingModelConfig(solarScale: -1),
      const DryingModelConfig(k: double.nan),
      const DryingModelConfig(goodWindExposure: 2),
      const DryingModelConfig(dayStartHour: 12),
      const DryingModelConfig(categories: []),
      const DryingModelConfig(safetyMargin: Duration(minutes: -1)),
    ]) {
      test(
        '不正設定${config.hashCode}',
        () =>
            expect(() => DryingEstimator(config: config), throwsArgumentError),
      );
    }
  });
}
