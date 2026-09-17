import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/drying_assessment.dart';

void main() {
  const evaluator = DryingEvaluator();
  final now = DateTime.utc(2026, 9, 17, 3);

  DryingConditions conditions({
    double? temperature = 25,
    double? humidity = 50,
    double? wind = 2,
    double? precipitation = 0,
    double? probability,
    bool? detected,
    DateTime? sourceTime,
  }) => DryingConditions(
    temperatureC: temperature,
    humidityPct: humidity,
    windSpeedMs: wind,
    precipitationMm: precipitation,
    precipitationProbabilityPct: probability,
    precipitationDetected: detected,
    sourceTime: sourceTime ?? now,
  );

  DryingAssessment evaluate(DryingConditions input) =>
      evaluator.evaluate(input, now: now);

  test('通常条件では降水確率がなくても現在値の適性を判定する', () {
    final result = evaluate(conditions());
    expect(result.status, DryingStatus.suitable);
    expect(result.reasons.single, contains('現在'));
  });

  test('実測の0を欠損と扱わず、低温と無風の注意を返す', () {
    final result = evaluate(
      conditions(temperature: 0, humidity: 0, wind: 0, probability: 0),
    );
    expect(result.status, DryingStatus.caution);
    expect(result.reasons, hasLength(2));
    expect(result.reasons.join(), contains('気温'));
    expect(result.reasons.join(), contains('風速'));
  });

  group('降水', () {
    test('わずかな正の降水量でもNG', () {
      expect(
        evaluate(conditions(precipitation: 0.001)).status,
        DryingStatus.notRecommended,
      );
    });

    test('降水量がなくても雨・雪の検知でNG', () {
      expect(
        evaluate(conditions(precipitation: null, detected: true)).status,
        DryingStatus.notRecommended,
      );
    });

    test('降水量0よりも雨・雪の検知を優先する', () {
      expect(
        evaluate(conditions(detected: true)).status,
        DryingStatus.notRecommended,
      );
    });

    test('非降水コードがあっても正の降水量を優先する', () {
      expect(
        evaluate(conditions(precipitation: 1, detected: false)).status,
        DryingStatus.notRecommended,
      );
    });

    test('明示的に降水なしと分かれば降水量欠損でも判定できる', () {
      expect(
        evaluate(conditions(precipitation: null, detected: false)).status,
        DryingStatus.suitable,
      );
    });

    test('降水確率0だけでは現在の降水なしとみなさない', () {
      final result = evaluate(conditions(precipitation: null, probability: 0));
      expect(result.status, DryingStatus.unknown);
      expect(result.reasons.join(), contains('雨・雪の有無が不明'));
    });
  });

  group('閾値', () {
    for (final scenario in <(double, DryingStatus)>[
      (0.999, DryingStatus.caution),
      (1, DryingStatus.suitable),
      (4.999, DryingStatus.suitable),
      (5, DryingStatus.caution),
      (7.999, DryingStatus.caution),
      (8, DryingStatus.notRecommended),
    ]) {
      test('風速 ${scenario.$1} m/s', () {
        expect(evaluate(conditions(wind: scenario.$1)).status, scenario.$2);
      });
    }

    for (final scenario in <(double, DryingStatus)>[
      (0, DryingStatus.suitable),
      (29.999, DryingStatus.suitable),
      (30, DryingStatus.caution),
      (59.999, DryingStatus.caution),
      (60, DryingStatus.notRecommended),
      (100, DryingStatus.notRecommended),
    ]) {
      test('降水確率 ${scenario.$1} %', () {
        expect(
          evaluate(conditions(probability: scenario.$1)).status,
          scenario.$2,
        );
      });
    }

    test('気温は10℃未満で注意', () {
      expect(
        evaluate(conditions(temperature: 9.999)).status,
        DryingStatus.caution,
      );
      expect(
        evaluate(conditions(temperature: 10)).status,
        DryingStatus.suitable,
      );
    });

    test('湿度は80%以上で注意、100%も有効', () {
      expect(
        evaluate(conditions(humidity: 79.999)).status,
        DryingStatus.suitable,
      );
      expect(evaluate(conditions(humidity: 80)).status, DryingStatus.caution);
      expect(evaluate(conditions(humidity: 100)).status, DryingStatus.caution);
    });
  });

  group('欠損と不正値', () {
    final cases = <String, DryingConditions Function()>{
      '気温欠損': () => conditions(temperature: null),
      '湿度欠損': () => conditions(humidity: null),
      '風速欠損': () => conditions(wind: null),
      '降水情報欠損': () => conditions(precipitation: null),
      '気温NaN': () => conditions(temperature: double.nan),
      '気温無限大': () => conditions(temperature: double.infinity),
      '湿度NaN': () => conditions(humidity: double.nan),
      '湿度負数': () => conditions(humidity: -1),
      '湿度100超': () => conditions(humidity: 101),
      '風速NaN': () => conditions(wind: double.nan),
      '風速無限大': () => conditions(wind: double.infinity),
      '風速負数': () => conditions(wind: -1),
      '降水量NaN': () => conditions(precipitation: double.nan),
      '降水量無限大': () => conditions(precipitation: double.infinity),
      '降水量負数': () => conditions(precipitation: -1),
      '降水確率NaN': () => conditions(probability: double.nan),
      '降水確率負数': () => conditions(probability: -1),
      '降水確率100超': () => conditions(probability: 101),
      '異常な低温': () => conditions(temperature: -101),
      '異常な高温': () => conditions(temperature: 71),
      '異常な風速': () => conditions(wind: 151),
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(evaluate(entry.value()).status, DryingStatus.unknown);
      });
    }

    test('降水なしコードでも不正な降水量は隠さない', () {
      expect(
        evaluate(conditions(precipitation: -1, detected: false)).status,
        DryingStatus.unknown,
      );
    });
  });

  group('複数の理由と優先順位', () {
    test('降水・強風・高降水確率のNG理由をすべて返す', () {
      final result = evaluate(
        conditions(precipitation: 1, wind: 8, probability: 60),
      );
      expect(result.status, DryingStatus.notRecommended);
      expect(result.reasons, hasLength(3));
    });

    test('低温・高湿度・弱風の理由をすべて返す', () {
      final result = evaluate(
        conditions(temperature: 5, humidity: 90, wind: 0),
      );
      expect(result.status, DryingStatus.caution);
      expect(result.reasons, hasLength(3));
    });

    test('他入力の欠損があっても確認できた降水のNGを保持する', () {
      final result = evaluate(
        conditions(
          temperature: null,
          humidity: null,
          wind: null,
          detected: true,
        ),
      );
      expect(result.status, DryingStatus.notRecommended);
      expect(result.reasons.first, contains('降水'));
      expect(result.reasons.join(), contains('欠損'));
    });

    test('他入力が不正でも有効な強風のNGを保持する', () {
      final result = evaluate(
        conditions(humidity: double.nan, wind: 8, precipitation: null),
      );
      expect(result.status, DryingStatus.notRecommended);
      expect(result.reasons.first, contains('8 m/s'));
    });

    test('注意条件より必須入力の欠損を優先する', () {
      final result = evaluate(conditions(temperature: null, humidity: 90));
      expect(result.status, DryingStatus.unknown);
      expect(result.reasons.join(), contains('80%以上'));
    });

    test('判定後に理由を書き換えられない', () {
      final result = evaluate(conditions());
      expect(() => result.reasons.clear(), throwsUnsupportedError);
    });
  });

  group('データ鮮度', () {
    test('sourceTimeがなければ降水があっても現在の判定は不明', () {
      final result = evaluate(
        const DryingConditions(precipitationDetected: true),
      );
      expect(result.status, DryingStatus.unknown);
      expect(result.reasons.single, contains('データ時刻'));
    });

    test('60分前ちょうどは許容し、それより古ければ不明', () {
      expect(
        evaluate(
          conditions(sourceTime: now.subtract(const Duration(minutes: 60))),
        ).status,
        DryingStatus.suitable,
      );
      expect(
        evaluate(
          conditions(
            sourceTime: now.subtract(const Duration(minutes: 60, seconds: 1)),
            precipitation: 1,
            wind: 8,
          ),
        ).status,
        DryingStatus.unknown,
      );
    });

    test('5分先ちょうどは許容し、それより未来なら不明', () {
      expect(
        evaluate(
          conditions(sourceTime: now.add(const Duration(minutes: 5))),
        ).status,
        DryingStatus.suitable,
      );
      expect(
        evaluate(
          conditions(
            sourceTime: now.add(const Duration(minutes: 5, seconds: 1)),
          ),
        ).status,
        DryingStatus.unknown,
      );
    });

    test('UTCとJST表現が異なっても同じ瞬間として鮮度を計算する', () {
      final input = conditions(
        sourceTime: DateTime.parse('2026-09-17T11:30:00+09:00'),
      );
      expect(evaluate(input).status, DryingStatus.suitable);
      expect(
        evaluator
            .evaluate(input, now: DateTime.parse('2026-09-17T12:00:00+09:00'))
            .status,
        DryingStatus.suitable,
      );
      expect(
        evaluator.evaluate(input, now: now.toLocal()).status,
        DryingStatus.suitable,
      );
    });
  });

  group('予報時刻', () {
    DryingAssessment evaluateForecast(DryingConditions input) =>
        evaluator.evaluateForecast(input, now: now);

    test('未来の予報には現在値の60分鮮度ルールを適用しない', () {
      final result = evaluateForecast(
        conditions(
          sourceTime: now.add(const Duration(hours: 12)),
          probability: 0,
        ),
      );
      expect(result.status, DryingStatus.suitable);
      expect(result.reasons.single, contains('選択した時間'));
    });

    test('過去時刻と時刻欠損は判定不能', () {
      expect(
        evaluateForecast(
          conditions(
            sourceTime: now.subtract(const Duration(seconds: 1)),
            probability: 0,
          ),
        ).status,
        DryingStatus.unknown,
      );
      expect(
        evaluator
            .evaluateForecast(
              const DryingConditions(
                temperatureC: 25,
                humidityPct: 50,
                windSpeedMs: 2,
                precipitationMm: 0,
                precipitationProbabilityPct: 0,
              ),
              now: now,
            )
            .status,
        DryingStatus.unknown,
      );
    });

    test('予報では降水確率が必須', () {
      final result = evaluateForecast(
        conditions(sourceTime: now.add(const Duration(hours: 1))),
      );
      expect(result.status, DryingStatus.unknown);
      expect(result.reasons.join(), contains('降水確率'));
    });

    for (final scenario in <(double, DryingStatus)>[
      (0, DryingStatus.suitable),
      (30, DryingStatus.caution),
      (60, DryingStatus.notRecommended),
    ]) {
      test('予報の降水確率 ${scenario.$1}%', () {
        expect(
          evaluateForecast(
            conditions(
              sourceTime: now.add(const Duration(hours: 1)),
              probability: scenario.$1,
            ),
          ).status,
          scenario.$2,
        );
      });
    }
  });
}
