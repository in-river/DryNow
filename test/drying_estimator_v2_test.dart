import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/drying_v2/drying_estimator_v2.dart';
import 'package:weather_app/drying_v2/drying_model_v2_config.dart';
import 'package:weather_app/drying_v2/garment_profile.dart';
import 'package:weather_app/drying_v2/moisture_state.dart';

DryingModelV2Config config({
  double hmNatural = 0.001,
  double hmForcedMax = 0.001,
  double windScale = 1,
  Duration step = const Duration(minutes: 5),
  double epsilon = 1e-10,
}) => DryingModelV2Config(
  hmNaturalMs: hmNatural,
  hmForcedMaxMs: hmForcedMax,
  windScaleMs: windScale,
  integrationStep: step,
  numericEpsilon: epsilon,
);

GarmentProfile profile({
  String id = 'test',
  FiberKind fiber = FiberKind.cotton,
  double dryMass = 0.1,
  double area = 0.1,
  double x0 = 0.8,
  double xc = 0.4,
  double target = 0.1,
  double k2 = 0.0002,
}) => GarmentProfile(
  id: id,
  fiberKind: fiber,
  dryMassKg: dryMass,
  effectiveAreaM2: area,
  initialMoistureRatio: x0,
  criticalMoistureRatio: xc,
  targetMoistureRatio: target,
  fallingRateConstantPerSecond: k2,
);

const normalCondition = (
  airTemperatureC: 25.0,
  relativeHumidityPct: 60.0,
  windSpeedMs: 0.5,
);

DryingEstimateV2 estimate({
  DryingModelV2Config? modelConfig,
  GarmentProfile? garment,
  ConstantDryingCondition condition = normalCondition,
  double xeq = 0.05,
}) => DryingEstimatorV2(config: modelConfig ?? config()).estimate(
  profile: garment ?? profile(),
  condition: condition,
  equilibriumMoistureRatio: xeq,
);

void main() {
  group('Phase 1 状態遷移', () {
    test('Xは乾燥中に単調減少する', () {
      final result = estimate();
      expect(result.trace, isNotEmpty);
      for (final step in result.trace) {
        expect(step.xAfter, lessThanOrEqualTo(step.xBefore));
      }
      for (var i = 1; i < result.trace.length; i++) {
        expect(
          result.trace[i].xBefore,
          closeTo(result.trace[i - 1].xAfter, 1e-12),
        );
      }
    });

    test('XがXcより大きい間はconstantRate', () {
      final constantSteps = estimate().trace.where(
        (step) => step.xBefore > step.xc,
      );
      expect(constantSteps, isNotEmpty);
      expect(
        constantSteps.every(
          (step) => step.phaseBefore == DryingPhase.constantRate,
        ),
        isTrue,
      );
    });

    test('XcでfallingRateへ遷移する', () {
      final trace = estimate().trace;
      final crossing = trace.firstWhere(
        (step) =>
            step.phaseBefore == DryingPhase.constantRate &&
            step.phaseAfter == DryingPhase.fallingRate,
      );
      expect(crossing.xAfter, closeTo(crossing.xc, 1e-12));
      final next = trace[trace.indexOf(crossing) + 1];
      expect(next.phaseBefore, DryingPhase.fallingRate);
    });

    test('減率期では乾燥速度が徐々に低下する', () {
      final falling = estimate().trace
          .where((step) => step.phaseBefore == DryingPhase.fallingRate)
          .take(4)
          .toList();
      expect(falling, hasLength(4));
      for (var i = 1; i < falling.length; i++) {
        expect(
          falling[i].dryingRatePerSecond,
          lessThan(falling[i - 1].dryingRatePerSecond),
        );
      }
    });

    test('Xeq以下へ進まない', () {
      const xeq = 0.05;
      final result = estimate(xeq: xeq);
      expect(result.trace.every((step) => step.xAfter >= xeq), isTrue);
    });

    test('Xtarget到達でcompletedになる', () {
      final result = estimate();
      expect(result.status, DryingPredictionStatus.completed);
      expect(result.duration, isNotNull);
      expect(result.finalState.phase, DryingPhase.completed);
      expect(result.finalState.moistureRatio, closeTo(0.1, 1e-12));
    });

    test('Xtarget到達時刻を5分末尾へ丸めない', () {
      final result = estimate();
      expect(
        result.duration!.inMicroseconds %
            const Duration(minutes: 5).inMicroseconds,
        isNot(0),
      );
      expect(result.trace.last.phaseAfter, DryingPhase.completed);
    });

    test('XeqがXtarget以上ならequilibriumLimited', () {
      final result = estimate(xeq: 0.12);
      expect(result.status, DryingPredictionStatus.equilibriumLimited);
      expect(result.duration, isNull);
      expect(result.trace, isEmpty);
    });

    test('0m/sでも自然対流床により乾燥する', () {
      final result = estimate(
        condition: (
          airTemperatureC: 25,
          relativeHumidityPct: 60,
          windSpeedMs: 0,
        ),
      );
      expect(result.trace.first.massTransferVelocityMs, config().hmNaturalMs);
      expect(result.trace.first.dryingRatePerSecond, greaterThan(0));
    });

    test('風速増加で恒率期乾燥速度が増える', () {
      final calm = estimate(
        condition: (
          airTemperatureC: 25,
          relativeHumidityPct: 60,
          windSpeedMs: 0,
        ),
      );
      final windy = estimate(
        condition: (
          airTemperatureC: 25,
          relativeHumidityPct: 60,
          windSpeedMs: 2,
        ),
      );
      expect(
        windy.trace.first.dryingRatePerSecond,
        greaterThan(calm.trace.first.dryingRatePerSecond),
      );
    });

    test('RH増加で恒率期乾燥速度が低下する', () {
      final dry = estimate(
        condition: (
          airTemperatureC: 25,
          relativeHumidityPct: 40,
          windSpeedMs: 0.5,
        ),
      );
      final humid = estimate(
        condition: (
          airTemperatureC: 25,
          relativeHumidityPct: 80,
          windSpeedMs: 0.5,
        ),
      );
      expect(
        humid.trace.first.dryingRatePerSecond,
        lessThan(dry.trace.first.dryingRatePerSecond),
      );
    });

    test('RH100%かつTs=Tairでは駆動力が0', () {
      final result = estimate(
        condition: (
          airTemperatureC: 25,
          relativeHumidityPct: 100,
          windSpeedMs: 0.5,
        ),
      );
      expect(result.status, DryingPredictionStatus.equilibriumLimited);
      expect(result.trace.single.vaporDensityDifferenceKgM3, 0);
      expect(result.trace.single.dryingRatePerSecond, 0);
    });

    test('5分stepと2.5分stepは同じ解析解へ収束する', () {
      final five = estimate();
      final twoAndHalf = estimate(
        modelConfig: config(step: const Duration(seconds: 150)),
      );
      expect(
        twoAndHalf.duration!.inMicroseconds,
        closeTo(five.duration!.inMicroseconds, 2),
      );
      expect(
        twoAndHalf.finalState.moistureRatio,
        closeTo(five.finalState.moistureRatio, 1e-12),
      );
    });

    test('1ステップ内でXcを跨ぎ残り時間を減率期へ使う', () {
      final result = estimate(garment: profile(x0: 0.401, xc: 0.4));
      final crossing = result.trace.first;
      expect(crossing.phaseAfter, DryingPhase.fallingRate);
      expect(crossing.endElapsed, lessThan(const Duration(minutes: 5)));
      expect(result.trace[1].startElapsed, crossing.endElapsed);
      expect(result.trace[1].phaseBefore, DryingPhase.fallingRate);
    });

    test('1ステップ内でXtargetを跨ぎ解析時刻で完了する', () {
      final result = estimate(
        garment: profile(x0: 0.401, xc: 0.4, target: 0.39, k2: 0.001),
      );
      expect(result.status, DryingPredictionStatus.completed);
      expect(result.trace.last.phaseAfter, DryingPhase.completed);
      expect(
        result.duration!.inMicroseconds %
            const Duration(minutes: 5).inMicroseconds,
        isNot(0),
      );
      expect(result.finalState.moistureRatio, closeTo(0.39, 1e-12));
    });

    test('除去水分量はXの変化と乾燥質量に一致する', () {
      final garment = profile(dryMass: 0.2);
      final result = estimate(garment: garment);
      expect(
        result.finalState.removedWaterKg,
        closeTo(
          (garment.initialMoistureRatio - garment.targetMoistureRatio) *
              garment.dryMassKg,
          1e-12,
        ),
      );
      expect(
        result.trace.last.cumulativeRemovedWaterKg,
        closeTo(result.finalState.removedWaterKg, 1e-12),
      );
    });
  });

  group('文献Xeq prototype', () {
    test('95%RHの綿とPESを別fixtureとして保持する', () {
      final modelConfig = config();
      expect(
        modelConfig.prototypeEquilibriumMoistureRatio(FiberKind.cotton, 95),
        0.1367,
      );
      expect(
        modelConfig.prototypeEquilibriumMoistureRatio(FiberKind.polyester, 95),
        0.0059,
      );
      expect(DryingModelV2Config.parameterSetId, contains('prototype'));
    });

    test('95%RH以外を2点から勝手に生成しない', () {
      expect(
        () => config().prototypeEquilibriumMoistureRatio(FiberKind.cotton, 60),
        throwsArgumentError,
      );
    });
  });

  group('Validation', () {
    for (final invalid in <(String, GarmentProfile)>[
      ('空ID', profile(id: '')),
      ('mdry=0', profile(dryMass: 0)),
      ('mdry NaN', profile(dryMass: double.nan)),
      ('Aeff=0', profile(area: 0)),
      ('Aeff Infinity', profile(area: double.infinity)),
      ('X0=0', profile(x0: 0)),
      ('Xc=0', profile(xc: 0)),
      ('Xtarget負値', profile(target: -0.1)),
      ('X0<=Xc', profile(x0: 0.4, xc: 0.4)),
      ('Xc<=Xtarget', profile(xc: 0.1, target: 0.1)),
      ('k2=0', profile(k2: 0)),
      ('k2 Infinity', profile(k2: double.infinity)),
    ]) {
      test(invalid.$1, () {
        expect(() => estimate(garment: invalid.$2), throwsArgumentError);
      });
    }

    for (final invalid in <(String, ConstantDryingCondition)>[
      (
        '温度NaN',
        (airTemperatureC: double.nan, relativeHumidityPct: 60, windSpeedMs: 1),
      ),
      (
        '温度Infinity',
        (
          airTemperatureC: double.infinity,
          relativeHumidityPct: 60,
          windSpeedMs: 1,
        ),
      ),
      (
        '温度範囲外',
        (airTemperatureC: 71.0, relativeHumidityPct: 60, windSpeedMs: 1),
      ),
      (
        'RH負値',
        (airTemperatureC: 25.0, relativeHumidityPct: -1, windSpeedMs: 1),
      ),
      (
        'RH上限超過',
        (airTemperatureC: 25.0, relativeHumidityPct: 101, windSpeedMs: 1),
      ),
      (
        'RH NaN',
        (airTemperatureC: 25, relativeHumidityPct: double.nan, windSpeedMs: 1),
      ),
      (
        '風速負値',
        (airTemperatureC: 25.0, relativeHumidityPct: 60, windSpeedMs: -1),
      ),
      (
        '風速Infinity',
        (
          airTemperatureC: 25,
          relativeHumidityPct: 60,
          windSpeedMs: double.infinity,
        ),
      ),
    ]) {
      test(invalid.$1, () {
        expect(() => estimate(condition: invalid.$2), throwsArgumentError);
      });
    }

    for (final invalid in <(String, double)>[
      ('Xeq負値', -0.1),
      ('Xeq NaN', double.nan),
      ('Xeq Infinity', double.infinity),
    ]) {
      test(invalid.$1, () {
        expect(() => estimate(xeq: invalid.$2), throwsArgumentError);
      });
    }

    for (final invalid in <(String, DryingModelV2Config)>[
      ('hmNatural=0', config(hmNatural: 0)),
      ('hmNatural NaN', config(hmNatural: double.nan)),
      ('hmForcedMax負値', config(hmForcedMax: -1)),
      ('hmForcedMax Infinity', config(hmForcedMax: double.infinity)),
      ('windScale=0', config(windScale: 0)),
      ('windScale Infinity', config(windScale: double.infinity)),
      ('step=0', config(step: Duration.zero)),
      ('epsilon=0', config(epsilon: 0)),
    ]) {
      test(invalid.$1, () {
        expect(
          () => DryingEstimatorV2(config: invalid.$2),
          throwsArgumentError,
        );
      });
    }
  });
}
