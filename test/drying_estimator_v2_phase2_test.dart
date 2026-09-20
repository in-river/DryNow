import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/drying_v2/drying_estimator_v2.dart';
import 'package:weather_app/drying_v2/drying_model_v2_config.dart';
import 'package:weather_app/drying_v2/forecast_drying_result_v2.dart';
import 'package:weather_app/drying_v2/forecast_step_cursor.dart';
import 'package:weather_app/drying_v2/garment_profile.dart';
import 'package:weather_app/drying_v2/moisture_state.dart';
import 'package:weather_app/models/weather.dart';

final _start = DateTime.utc(2026, 9, 19, 12);

const _config = DryingModelV2Config(
  hmNaturalMs: 0.001,
  hmForcedMaxMs: 0.001,
  windScaleMs: 0.5,
);

const _standardProfile = GarmentProfile(
  id: 'phase2-standard-fixture',
  fiberKind: FiberKind.cotton,
  dryMassKg: 0.1,
  effectiveAreaM2: 0.4,
  initialMoistureRatio: 0.8,
  criticalMoistureRatio: 0.4,
  targetMoistureRatio: 0.1,
  fallingRateConstantPerSecond: 0.000018,
);

const _fastProfile = GarmentProfile(
  id: 'phase2-fast-fixture',
  fiberKind: FiberKind.cotton,
  dryMassKg: 0.1,
  effectiveAreaM2: 10,
  initialMoistureRatio: 0.41,
  criticalMoistureRatio: 0.4,
  targetMoistureRatio: 0.39,
  fallingRateConstantPerSecond: 0.01,
);

const _slowProfile = GarmentProfile(
  id: 'phase2-slow-fixture',
  fiberKind: FiberKind.cotton,
  dryMassKg: 0.1,
  effectiveAreaM2: 0.0001,
  initialMoistureRatio: 0.8,
  criticalMoistureRatio: 0.4,
  targetMoistureRatio: 0.1,
  fallingRateConstantPerSecond: 0.000001,
);

HourlyForecast _row(
  DateTime time, {
  double? temperature = 25,
  double? humidity = 60,
  double? wind = 0.5,
}) => HourlyForecast(
  forecastTimeUtc: time,
  temperature: temperature,
  humidity: humidity,
  windSpeed: wind,
);

ForecastSeries _series(
  List<HourlyForecast> rows, {
  Duration? offset = Duration.zero,
  String? timezone = 'UTC',
}) => ForecastSeries(
  cityName: 'Phase 2 test',
  forecasts: rows,
  locationUtcOffset: offset,
  timezone: timezone,
);

List<HourlyForecast> _constantRows({
  int hours = 48,
  DateTime? start,
  double temperature = 25,
  double humidity = 60,
  double wind = 0.5,
}) => [
  for (var hour = 0; hour <= hours; hour++)
    _row(
      (start ?? _start).add(Duration(hours: hour)),
      temperature: temperature,
      humidity: humidity,
      wind: wind,
    ),
];

double _constantXeq(ConstantDryingCondition condition, FiberKind fiberKind) =>
    0.05;

DryingEstimatorV2 get _estimator => DryingEstimatorV2(config: _config);

ForecastDryingEstimateV2 _estimate({
  List<HourlyForecast>? rows,
  GarmentProfile profile = _standardProfile,
  DateTime? start,
  Duration? offset = Duration.zero,
  ForecastEquilibriumMoistureFixture xeq = _constantXeq,
}) => _estimator.estimateForecast(
  series: _series(rows ?? _constantRows(), offset: offset),
  profile: profile,
  startTimeUtc: start ?? _start,
  equilibriumMoistureRatioForCondition: xeq,
);

void main() {
  group('時間補間', () {
    final rows = [
      _row(_start, temperature: 20, humidity: 40, wind: 0),
      _row(
        _start.add(const Duration(hours: 1)),
        temperature: 32,
        humidity: 64,
        wind: 2.4,
      ),
    ];

    ForecastSubstep firstStep() => ForecastStepCursor(
      series: _series(rows),
      startTimeUtc: _start,
      integrationStep: const Duration(minutes: 5),
    ).next();

    test('気温を隣接点間で線形補間する', () {
      expect(firstStep().temperatureC, closeTo(20.5, 1e-12));
    });

    test('RHを隣接点間で線形補間する', () {
      expect(firstStep().relativeHumidityPct, closeTo(41, 1e-12));
    });

    test('windを隣接点間で線形補間する', () {
      expect(firstStep().windSpeedMs, closeTo(0.1, 1e-12));
    });
  });

  group('開始時刻', () {
    test('途中開始は開始前の乾燥量を含めず次の5分境界まで短縮する', () {
      final start = _start.add(const Duration(minutes: 23));
      final result = _estimate(start: start);
      expect(result.trace.first.startTimeUtc, start);
      expect(
        result.trace.first.endTimeUtc,
        _start.add(const Duration(minutes: 25)),
      );
      expect(result.trace.first.xBefore, _standardProfile.initialMoistureRatio);
    });

    test('予報先頭から開始できる', () {
      final result = _estimate();
      expect(result.startTimeUtc, _start);
      expect(result.trace.first.startTimeUtc, _start);
    });

    test('時間境界ちょうどから右側区間を使う', () {
      final boundary = _start.add(const Duration(hours: 1));
      final result = _estimate(start: boundary);
      expect(result.trace.first.startTimeUtc, boundary);
    });

    test('予報先頭より前はinsufficientData', () {
      final result = _estimate(
        start: _start.subtract(const Duration(seconds: 1)),
      );
      expect(result.status, DryingPredictionStatus.insufficientData);
    });

    test('予報末尾ちょうどはinsufficientData', () {
      final rows = _constantRows(hours: 2);
      final result = _estimate(rows: rows, start: rows.last.forecastTimeUtc);
      expect(result.status, DryingPredictionStatus.insufficientData);
    });
  });

  group('時間軸とtimezone', () {
    test('内部時刻はUTCを維持する', () {
      final result = _estimate(profile: _fastProfile);
      expect(result.startTimeUtc.isUtc, isTrue);
      expect(result.completionTimeUtc!.isUtc, isTrue);
      expect(result.forecastEndUtc!.isUtc, isTrue);
    });

    test('JST +09:00でも同じ絶対時刻を処理する', () {
      final jstSeries = _series(
        _constantRows(),
        offset: const Duration(hours: 9),
        timezone: 'Asia/Tokyo',
      );
      final result = _estimator.estimateForecast(
        series: jstSeries,
        profile: _fastProfile,
        startTimeUtc: DateTime.parse('2026-09-19T21:00:00+09:00'),
        equilibriumMoistureRatioForCondition: _constantXeq,
      );
      expect(result.startTimeUtc, _start);
      expect(result.status, DryingPredictionStatus.completed);
    });

    test('日付を跨いでもUTC時系列を連続処理する', () {
      final start = DateTime.utc(2026, 9, 19, 23, 30);
      final result = _estimate(
        rows: _constantRows(hours: 3, start: DateTime.utc(2026, 9, 19, 23)),
        start: start,
        profile: _slowProfile,
      );
      expect(result.status, DryingPredictionStatus.notCompletedWithinForecast);
      expect(result.trace.last.endTimeUtc.day, 20);
    });

    test('timezone offset欠損はinsufficientData', () {
      expect(
        _estimate(offset: null).status,
        DryingPredictionStatus.insufficientData,
      );
    });

    test('端末ローカルの曖昧な開始時刻を拒否する', () {
      final local = DateTime(2026, 9, 19, 12);
      expect(local.isUtc, isFalse);
      expect(
        _estimate(start: local).status,
        DryingPredictionStatus.insufficientData,
      );
    });

    test('重複時刻はinsufficientData', () {
      expect(
        _estimate(rows: [_row(_start), _row(_start)]).status,
        DryingPredictionStatus.insufficientData,
      );
    });

    test('逆順はinsufficientData', () {
      expect(
        _estimate(
          rows: [_row(_start.add(const Duration(hours: 1))), _row(_start)],
        ).status,
        DryingPredictionStatus.insufficientData,
      );
    });

    test('1時間を超える穴はinsufficientData', () {
      expect(
        _estimate(
          rows: [_row(_start), _row(_start.add(const Duration(hours: 2)))],
        ).status,
        DryingPredictionStatus.insufficientData,
      );
    });
  });

  group('状態計算と完了境界', () {
    test('forecast全体でXが単調減少する', () {
      final result = _estimate();
      for (final step in result.trace) {
        expect(step.xAfter, lessThanOrEqualTo(step.xBefore));
      }
    });

    test('constantからfallingへ遷移する', () {
      final result = _estimate();
      expect(
        result.trace.any(
          (step) =>
              step.phaseBefore == DryingPhase.constantRate &&
              step.phaseAfter == DryingPhase.fallingRate,
        ),
        isTrue,
      );
    });

    test('1step内でXcを跨ぎ残り時間をfallingへ使う', () {
      final result = _estimate(profile: _fastProfile);
      final crossingIndex = result.trace.indexWhere(
        (step) => step.phaseAfter == DryingPhase.fallingRate,
      );
      expect(crossingIndex, greaterThanOrEqualTo(0));
      expect(
        result.trace[crossingIndex].endTimeUtc.isBefore(
          result.trace.first.startTimeUtc.add(_config.integrationStep),
        ),
        isTrue,
      );
      expect(
        result.trace[crossingIndex + 1].startTimeUtc,
        result.trace[crossingIndex].endTimeUtc,
      );
    });

    test('1step内でXtargetへ到達してcompletedになる', () {
      final result = _estimate(profile: _fastProfile);
      expect(result.status, DryingPredictionStatus.completed);
      expect(result.trace.last.phaseAfter, DryingPhase.completed);
      expect(result.finalState.moistureRatio, _fastProfile.targetMoistureRatio);
    });

    test('完了時刻を5分境界へ丸めない', () {
      final result = _estimate(profile: _fastProfile);
      expect(
        result.duration!.inMicroseconds %
            _config.integrationStep.inMicroseconds,
        isNot(0),
      );
      expect(
        result.completionTimeUtc,
        result.startTimeUtc.add(result.duration!),
      );
    });
  });

  group('結果status', () {
    test('予報内完了はcompleted', () {
      expect(
        _estimate(profile: _fastProfile).status,
        DryingPredictionStatus.completed,
      );
    });

    test('予報末尾未達はnotCompletedWithinForecast', () {
      final result = _estimate(
        rows: _constantRows(hours: 2),
        profile: _slowProfile,
      );
      expect(result.status, DryingPredictionStatus.notCompletedWithinForecast);
      expect(result.completionTimeUtc, isNull);
      expect(result.duration, isNull);
      expect(result.finalState.elapsed, const Duration(hours: 2));
    });

    for (final field in ['temperature', 'humidity', 'wind']) {
      test('$field欠損はinsufficientData', () {
        final rows = _constantRows(hours: 2);
        rows[1] = _row(
          rows[1].forecastTimeUtc,
          temperature: field == 'temperature' ? null : 25,
          humidity: field == 'humidity' ? null : 60,
          wind: field == 'wind' ? null : 0.5,
        );
        expect(
          _estimate(rows: rows).status,
          DryingPredictionStatus.insufficientData,
        );
      });
    }

    test('1点だけの予報はinsufficientData', () {
      expect(
        _estimate(rows: [_row(_start)]).status,
        DryingPredictionStatus.insufficientData,
      );
    });
  });

  group('一時的な高湿度停止', () {
    final rows = [
      _row(_start, humidity: 95),
      _row(_start.add(const Duration(hours: 1)), humidity: 95),
      _row(_start.add(const Duration(hours: 2)), humidity: 95),
      _row(_start.add(const Duration(hours: 3)), humidity: 60),
      _row(_start.add(const Duration(hours: 4)), humidity: 60),
    ];
    double changingXeq(
      ConstantDryingCondition condition,
      FiberKind fiberKind,
    ) => condition.relativeHumidityPct >= 90 ? 0.4 : 0.05;

    test('一時的Xeq >= Xtargetでも即終了しない', () {
      final result = _estimate(
        rows: rows,
        profile: _fastProfile,
        xeq: changingXeq,
      );
      expect(result.status, DryingPredictionStatus.completed);
      expect(result.numberOfSteps, greaterThan(1));
    });

    test('高湿度区間ではXが増えない', () {
      final result = _estimate(
        rows: rows,
        profile: _fastProfile,
        xeq: changingXeq,
      );
      final stalled = result.trace.where(
        (step) => step.phaseAfter == DryingPhase.equilibriumStalled,
      );
      expect(stalled, isNotEmpty);
      expect(stalled.every((step) => step.xAfter == step.xBefore), isTrue);
    });

    test('条件改善後に乾燥が再開する', () {
      final result = _estimate(
        rows: rows,
        profile: _fastProfile,
        xeq: changingXeq,
      );
      final firstProgress = result.trace.firstWhere(
        (step) => step.dryingRatePerSecond > 0,
      );
      expect(firstProgress.relativeHumidityPct, lessThan(90));
      expect(firstProgress.xAfter, lessThan(firstProgress.xBefore));
    });

    test('条件改善後に完了可能ならcompleted', () {
      final result = _estimate(
        rows: rows,
        profile: _fastProfile,
        xeq: changingXeq,
      );
      expect(result.status, DryingPredictionStatus.completed);
      expect(result.completionTimeUtc, isNotNull);
    });
  });

  group('数値検証', () {
    for (final invalid in <(String, double?, double?, double?)>[
      ('temperature NaN', double.nan, 60, 0.5),
      ('temperature Infinity', double.infinity, 60, 0.5),
      ('temperature範囲外', 71, 60, 0.5),
      ('RH NaN', 25, double.nan, 0.5),
      ('RH範囲外', 25, 101, 0.5),
      ('wind Infinity', 25, 60, double.infinity),
      ('wind負値', 25, 60, -0.1),
    ]) {
      test('${invalid.$1}はinsufficientData', () {
        final rows = [
          _row(_start),
          _row(
            _start.add(const Duration(hours: 1)),
            temperature: invalid.$2,
            humidity: invalid.$3,
            wind: invalid.$4,
          ),
        ];
        expect(
          _estimate(rows: rows).status,
          DryingPredictionStatus.insufficientData,
        );
      });
    }

    test('Xeq fixtureのNaNをinsufficientDataとして拒否する', () {
      final result = _estimate(xeq: (condition, fiberKind) => double.nan);
      expect(result.status, DryingPredictionStatus.insufficientData);
    });
  });
}
