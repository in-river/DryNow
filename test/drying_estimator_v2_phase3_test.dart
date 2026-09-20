import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/drying_v2/drying_estimator_v2.dart';
import 'package:weather_app/drying_v2/drying_model_v2_config.dart';
import 'package:weather_app/drying_v2/equilibrium_moisture_model.dart';
import 'package:weather_app/drying_v2/forecast_drying_result_v2.dart';
import 'package:weather_app/drying_v2/garment_profile.dart';
import 'package:weather_app/drying_v2/moisture_state.dart';
import 'package:weather_app/models/weather.dart';

final _start = DateTime.utc(2026, 9, 19, 12);
const _model = TabulatedEquilibriumMoistureModel();
const _config = DryingModelV2Config(
  hmNaturalMs: 0.001,
  hmForcedMaxMs: 0.001,
  windScaleMs: 0.5,
);

GarmentProfile _profile({
  FiberKind material = FiberKind.cotton,
  double target = 0.08,
  double area = 0.4,
  double k2 = 0.0002,
  double? cottonFraction,
  double? polyesterFraction,
}) => GarmentProfile(
  id: 'phase3-${material.name}',
  fiberKind: material,
  dryMassKg: 0.1,
  effectiveAreaM2: area,
  initialMoistureRatio: 0.3,
  criticalMoistureRatio: 0.2,
  targetMoistureRatio: target,
  fallingRateConstantPerSecond: k2,
  cottonFraction: cottonFraction,
  polyesterFraction: polyesterFraction,
);

HourlyForecast _row(DateTime time, double rh) => HourlyForecast(
  forecastTimeUtc: time,
  temperature: 25,
  humidity: rh,
  windSpeed: 0.5,
);

List<HourlyForecast> _rows(List<double> humidity) => [
  for (var index = 0; index < humidity.length; index++)
    _row(_start.add(Duration(hours: index)), humidity[index]),
];

ForecastDryingEstimateV2 _estimate({
  required List<double> humidity,
  GarmentProfile? profile,
  EquilibriumMoistureModel model = _model,
}) => DryingEstimatorV2(config: _config).estimateForecastWithEquilibriumModel(
  series: ForecastSeries(
    cityName: 'Phase 3 test',
    forecasts: _rows(humidity),
    locationUtcOffset: Duration.zero,
    timezone: 'UTC',
  ),
  profile: profile ?? _profile(),
  startTimeUtc: _start,
  equilibriumMoistureModel: model,
);

void main() {
  group('文献Xeq table', () {
    double xeq(FiberKind material, double rh) => _model
        .equilibriumMoistureRatio(
          temperatureC: 25,
          relativeHumidityPct: rh,
          material: material,
        )
        .value!;

    test('cottonの65%節点をdry basisで返す', () {
      expect(xeq(FiberKind.cotton, 65), 0.049);
    });

    test('cottonの95%節点をdry basisで返す', () {
      expect(xeq(FiberKind.cotton, 95), 0.1367);
    });

    test('polyesterの65%節点をdry basisで返す', () {
      expect(xeq(FiberKind.polyester, 65), 0.005);
    });

    test('polyesterの95%節点をdry basisで返す', () {
      expect(xeq(FiberKind.polyester, 95), 0.0059);
    });

    test('節点間だけを線形補間する', () {
      expect(xeq(FiberKind.cotton, 80), closeTo(0.09285, 1e-12));
      expect(xeq(FiberKind.polyester, 80), closeTo(0.00545, 1e-12));
    });

    test('65%未満はunsupportedで外挿しない', () {
      expect(
        _model
            .equilibriumMoistureRatio(
              temperatureC: 25,
              relativeHumidityPct: 64.9,
              material: FiberKind.cotton,
            )
            .isSupported,
        isFalse,
      );
    });

    test('95%超はunsupportedで外挿しない', () {
      expect(
        _model
            .equilibriumMoistureRatio(
              temperatureC: 25,
              relativeHumidityPct: 95.1,
              material: FiberKind.cotton,
            )
            .isSupported,
        isFalse,
      );
    });

    test('NaN、Infinity、RH範囲外を拒否する', () {
      for (final rh in [double.nan, double.infinity, -1.0, 101.0]) {
        expect(
          () => _model.equilibriumMoistureRatio(
            temperatureC: 25,
            relativeHumidityPct: rh,
            material: FiberKind.cotton,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => _model.equilibriumMoistureRatio(
          temperatureC: double.nan,
          relativeHumidityPct: 80,
          material: FiberKind.cotton,
        ),
        throwsArgumentError,
      );
    });

    test('metadataがprototypeと出典条件を追跡できる', () {
      expect(_model.metadata.parameterSetId, 'literature-xeq-prototype-v1');
      expect(_model.metadata.source, contains('Martí'));
      expect(_model.metadata.basis, contains('dry basis'));
      expect(_model.metadata.relativeHumidityNodesPct, [65, 95]);
      expect(_model.metadata.temperatureCondition, contains('25°C'));
      expect(_model.metadata.isPrototype, isTrue);
    });
  });

  group('素材差と混紡', () {
    EquilibriumMoistureResult result(
      FiberKind material, {
      double? cotton,
      double? polyester,
    }) => _model.equilibriumMoistureRatio(
      temperatureC: 25,
      relativeHumidityPct: 95,
      material: material,
      cottonFraction: cotton,
      polyesterFraction: polyester,
    );

    test('高RHでcotton Xeqがpolyesterより高い', () {
      expect(
        result(FiberKind.cotton).value!,
        greaterThan(result(FiberKind.polyester).value!),
      );
    });

    test('blendは両素材の範囲内になる', () {
      final blend = result(FiberKind.blend, cotton: 0.6, polyester: 0.4).value!;
      expect(blend, inInclusiveRange(0.0059, 0.1367));
    });

    test('cottonFraction=1はcottonと一致する', () {
      expect(
        result(FiberKind.blend, cotton: 1, polyester: 0).value,
        result(FiberKind.cotton).value,
      );
    });

    test('polyesterFraction=1はpolyesterと一致する', () {
      expect(
        result(FiberKind.blend, cotton: 0, polyester: 1).value,
        result(FiberKind.polyester).value,
      );
    });

    test('不正な混紡比率を拒否する', () {
      for (final fractions in [(0.7, 0.4), (-0.1, 1.1), (double.nan, 0.0)]) {
        expect(
          () => result(
            FiberKind.blend,
            cotton: fractions.$1,
            polyester: fractions.$2,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('ForecastSeries動的Xeq', () {
    test('RH変化に応じて各stepのXeqが変化する', () {
      final result = _estimate(
        humidity: [65, 75, 85, 95],
        profile: _profile(area: 0.00001, k2: 0.000001),
      );
      expect(
        result.trace.map((step) => step.xeq).toSet().length,
        greaterThan(2),
      );
    });

    test('Xeq上昇時もXは増加しない', () {
      final result = _estimate(
        humidity: [65, 65, 95, 95],
        profile: _profile(target: 0.04),
      );
      expect(result.trace.every((step) => step.xAfter <= step.xBefore), isTrue);
    });

    test('Xeqが現在X以上ならequilibriumStalledになる', () {
      final result = _estimate(
        humidity: [65, 65, 95, 95],
        profile: _profile(target: 0.04, area: 2, k2: 0.001),
      );
      final stalled = result.trace.where(
        (step) => step.phaseAfter == DryingPhase.equilibriumStalled,
      );
      expect(stalled, isNotEmpty);
      expect(stalled.every((step) => step.xAfter == step.xBefore), isTrue);
    });

    test('高湿度後の条件改善で乾燥が再開する', () {
      final result = _estimate(
        humidity: [95, 95, 65, 65, 65],
        profile: _profile(area: 2, k2: 0.001),
      );
      expect(result.status, DryingPredictionStatus.completed);
      final firstLowRhStep = result.trace.firstWhere(
        (step) => step.relativeHumidityPct < 90,
      );
      expect(firstLowRhStep.dryingRatePerSecond, greaterThan(0));
    });

    test('再吸湿を行わず全stepで単調非増加を保つ', () {
      final result = _estimate(
        humidity: [65, 65, 95, 95, 65],
        profile: _profile(target: 0.04),
      );
      for (final step in result.trace) {
        expect(step.xAfter, lessThanOrEqualTo(step.xBefore));
      }
    });
  });

  group('Phase 3 status分類', () {
    test('一時的高湿度の後に回復すればcompletedになれる', () {
      expect(
        _estimate(
          humidity: [95, 95, 65, 65, 65],
          profile: _profile(area: 2, k2: 0.001),
        ).status,
        DryingPredictionStatus.completed,
      );
    });

    test('全予報でXeqがtarget以上ならequilibriumLimited', () {
      final result = _estimate(
        humidity: [65, 75, 85, 95],
        profile: _profile(target: 0.04, area: 0.00001),
      );
      expect(result.status, DryingPredictionStatus.equilibriumLimited);
    });

    test('target到達可能区間があって時間不足ならnotCompleted', () {
      final result = _estimate(
        humidity: [95, 80, 65],
        profile: _profile(target: 0.08, area: 0.000001, k2: 0.000001),
      );
      expect(result.status, DryingPredictionStatus.notCompletedWithinForecast);
    });

    test('unsupported RHはinsufficientDataと診断情報を返す', () {
      final result = _estimate(humidity: [65, 60, 65]);
      expect(result.status, DryingPredictionStatus.insufficientData);
      expect(result.issue, isNotNull);
      expect(result.issue!.relativeHumidityPct, lessThan(65));
      expect(result.issue!.material, FiberKind.cotton.name);
      expect(result.issue!.reason, contains('outside documented nodes'));
    });

    test('最後の1stepだけ高XeqでもequilibriumLimitedにしない', () {
      final result = _estimate(
        humidity: [65, 65, 65, 95],
        profile: _profile(target: 0.08, area: 0.000001, k2: 0.000001),
      );
      expect(result.status, DryingPredictionStatus.notCompletedWithinForecast);
    });

    test('結果にXeq parameter set IDを保持する', () {
      final result = _estimate(
        humidity: [65, 75],
        profile: _profile(target: 0.04, area: 0.000001),
      );
      expect(result.parameterSetId, _model.metadata.parameterSetId);
    });
  });
}
