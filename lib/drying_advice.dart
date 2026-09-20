import 'dart:math' as math;

import 'drying_assessment.dart';
import 'drying_estimator.dart';
import 'drying_model_config.dart';
import 'models/drying_environment.dart';
import 'models/weather.dart';

enum WeatherRiskKind { rain, wind }

class WeatherRisk {
  const WeatherRisk({
    required this.kind,
    required this.status,
    required this.riskStartTime,
    required this.endTime,
    required this.sourceTime,
    this.precipitationMm,
    this.precipitationProbabilityPct,
    this.weatherCodes = const [],
    this.windSpeedMs,
    this.windThresholdMs,
  });
  final WeatherRiskKind kind;
  final DryingStatus status;
  final DateTime riskStartTime;
  final DateTime endTime;
  final DateTime sourceTime;
  final double? precipitationMm;
  final double? precipitationProbabilityPct;
  final List<int> weatherCodes;
  final double? windSpeedMs;
  final double? windThresholdMs;
}

String weatherCodeRiskLabel(int code) {
  if ({51, 53, 55, 80, 81, 82}.contains(code)) return '雨';
  if ({56, 57, 66, 67}.contains(code)) return '着氷性の雨';
  if ({61, 63, 65}.contains(code)) return '雨';
  if ({71, 73, 75, 77, 85, 86}.contains(code)) return '雪';
  if ({95, 96, 99}.contains(code)) return '雷雨';
  return '降水を伴う天気';
}

class GarmentAdvice {
  GarmentAdvice({
    required this.estimate,
    required this.status,
    required List<String> reasons,
  }) : reasons = List.unmodifiable(reasons);
  final GarmentDryingEstimate estimate;
  final DryingStatus status;
  final List<String> reasons;
}

class DryingAdvice {
  DryingAdvice({
    required this.overallStatus,
    required List<GarmentAdvice> garments,
    required List<WeatherRisk> weatherRisks,
    required this.primaryMessage,
    required List<String> detailMessages,
  }) : garments = List.unmodifiable(garments),
       weatherRisks = List.unmodifiable(weatherRisks),
       detailMessages = List.unmodifiable(detailMessages);
  final DryingStatus overallStatus;
  final List<GarmentAdvice> garments;
  final List<WeatherRisk> weatherRisks;
  final String primaryMessage;
  final List<String> detailMessages;
}

class DryingAdvisor {
  DryingAdvisor({DryingModelConfig config = const DryingModelConfig()})
    : estimator = DryingEstimator(config: config);
  final DryingEstimator estimator;
  DryingModelConfig get config => estimator.config;

  DryingAdvice advise({
    required ForecastSeries series,
    required DryingEnvironment environment,
    required DateTime startTime,
    required DateTime now,
    required DateTime fetchedAt,
  }) {
    final start = startTime.toUtc();
    final age = now.toUtc().difference(fetchedAt.toUtc());
    final invalidTime =
        start.isBefore(now.toUtc()) ||
        age > config.maximumForecastAge ||
        age < -DryingEvaluator.maximumFutureOffset;
    final estimates = estimator.estimateDryingTime(
      series: series,
      environment: environment,
      startTime: start,
    );
    final risks =
        assessWeatherRisks(
            series.forecasts,
          ).where((r) => !r.endTime.isBefore(start)).toList()
          ..sort((a, b) => a.riskStartTime.compareTo(b.riskStartTime));
    final garments = <GarmentAdvice>[];
    for (final estimate in estimates) {
      if (invalidTime) {
        garments.add(
          GarmentAdvice(
            estimate: GarmentDryingEstimate(
              category: estimate.category,
              status: DryingEstimateStatus.insufficientData,
            ),
            status: DryingStatus.unknown,
            reasons: ['開始時刻または予報の鮮度を確認し、予報を更新してください。'],
          ),
        );
        continue;
      }
      final completion = estimate.estimatedCompletionTime;
      // 完了不明のときも、開始時に確認できる危険を欠損で隠さない。
      final end = completion ?? start;
      final marginEnd = end.add(config.safetyMargin);
      final during = risks
          .where(
            (r) => !r.endTime.isBefore(start) && !r.riskStartTime.isAfter(end),
          )
          .toList();
      final nearby = risks
          .where(
            (r) =>
                r.riskStartTime.isAfter(end) &&
                !r.riskStartTime.isAfter(marginEnd),
          )
          .toList();
      final severe = during.any((r) => r.status == DryingStatus.notRecommended);
      final completeRiskData =
          completion != null &&
          _hasRiskCoverage(series.forecasts, start, marginEnd);
      final reasons = <String>[];
      if (estimate.status != DryingEstimateStatus.estimated) {
        reasons.add(
          estimate.status == DryingEstimateStatus.forecastLimit
              ? '予測可能な時間内では乾燥完了を確認できません。'
              : '気象データの欠損・時刻の途切れにより乾燥時間を推定できません。',
        );
      }
      for (final kind in WeatherRiskKind.values) {
        final matching = during.where((r) => r.kind == kind).toList();
        if (matching.isNotEmpty) {
          reasons.add(_riskReason(matching.first));
        }
      }
      if (nearby.isNotEmpty) {
        reasons.add('乾燥完了と悪天候が近く、余裕が少ない見込みです。');
      }
      if (completion != null && !completeRiskData) {
        reasons.add('乾燥後の余裕時間まで雨・風の予報を確認できません。');
      }
      final status = severe
          ? DryingStatus.notRecommended
          : !completeRiskData
          ? DryingStatus.unknown
          : during.isNotEmpty || nearby.isNotEmpty
          ? DryingStatus.caution
          : DryingStatus.suitable;
      if (status == DryingStatus.suitable) reasons.add('雨・強風の前に乾く見込みです。');
      if (status == DryingStatus.notRecommended) reasons.add('室内干しがおすすめです。');
      garments.add(
        GarmentAdvice(estimate: estimate, status: status, reasons: reasons),
      );
    }
    final states = garments.map((g) => g.status).toSet();
    final overall = states.length == 1 ? states.single : DryingStatus.caution;
    final details = <String>[];
    final suitable = garments
        .where((g) => g.status == DryingStatus.suitable)
        .map((g) => g.estimate.category.label)
        .join('・');
    if (suitable.isNotEmpty) details.add('$suitableは雨・強風の前に乾く見込みです。');
    final indoors = garments
        .where((g) => g.status == DryingStatus.notRecommended)
        .map((g) => g.estimate.category.label)
        .join('・');
    if (indoors.isNotEmpty) details.add('$indoorsは室内干しがおすすめです。');
    for (final garment in garments.where(
      (g) => g.status == DryingStatus.unknown,
    )) {
      details.add(
        '${garment.estimate.category.label}は予報範囲内で判定できません。'
        '${garment.reasons.first}',
      );
    }
    if (environment.roofProtection) {
      details.add('屋根・雨よけは雨の影響を軽減しますが、吹き込みには注意が必要です。');
    }
    final relevantEnd = garments
        .fold<DateTime>(start, (end, garment) {
          final completion = garment.estimate.estimatedCompletionTime;
          return completion != null && completion.isAfter(end)
              ? completion
              : end;
        })
        .add(config.safetyMargin);
    return DryingAdvice(
      overallStatus: overall,
      garments: garments,
      weatherRisks: invalidTime
          ? []
          : risks.where((r) => !r.riskStartTime.isAfter(relevantEnd)).toList(),
      primaryMessage: switch (overall) {
        DryingStatus.suitable => '外干しOK',
        DryingStatus.caution =>
          states.contains(DryingStatus.unknown)
              ? '一部の衣類は判定できません（注意）'
              : '外干しできますが注意',
        DryingStatus.notRecommended => '外干し非推奨',
        DryingStatus.unknown => '判定不能',
      },
      detailMessages: details,
    );
  }

  String _riskReason(WeatherRisk risk) {
    if (risk.kind == WeatherRiskKind.wind) {
      final threshold = risk.windThresholdMs ?? risk.windSpeedMs;
      return threshold == null
          ? '乾燥前に強い風が予想されます。'
          : '乾燥前に風速${threshold.toStringAsFixed(0)}m/s以上となる見込みです。';
    }
    final causes = <String>[];
    if (risk.precipitationMm != null) {
      causes.add('${risk.precipitationMm!.toStringAsFixed(1)}mmの降水');
    }
    if (risk.precipitationProbabilityPct != null) {
      causes.add(
        '降水確率${risk.precipitationProbabilityPct!.toStringAsFixed(0)}%',
      );
    }
    if (risk.weatherCodes.isNotEmpty) {
      causes.add(weatherCodeRiskLabel(risk.weatherCodes.first));
    }
    return causes.isEmpty
        ? '乾燥前に降水の可能性があります。'
        : '乾燥前に${causes.join('・')}の予報があります。';
  }

  bool _valid(double? value, [double maximum = double.infinity]) =>
      value != null && value.isFinite && value >= 0 && value <= maximum;

  // 乾燥時間が不明でも、予報自体のリスク区間は独立に検証できる。
  List<WeatherRisk> assessWeatherRisks(List<HourlyForecast> rows) =>
      List.unmodifiable(_mergeRisks(_risks(rows)));

  Iterable<WeatherRisk> _risks(List<HourlyForecast> rows) sync* {
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final time = row.forecastTimeUtc;
      final probability = row.precipitationProbability;
      final rain = _valid(row.precipitationMm) && row.precipitationMm! > 0;
      final highProbability =
          _valid(probability, 100) &&
          probability! >= DryingEvaluator.highPrecipitationProbabilityPct;
      final cautionProbability =
          _valid(probability, 100) &&
          probability! >= DryingEvaluator.cautionPrecipitationProbabilityPct;
      if (rain || cautionProbability) {
        // 降水量・確率は直前1時間の値。時間窓の先頭から注意する。
        yield WeatherRisk(
          kind: WeatherRiskKind.rain,
          status: rain || highProbability
              ? DryingStatus.notRecommended
              : DryingStatus.caution,
          riskStartTime: time.subtract(const Duration(hours: 1)),
          endTime: time,
          sourceTime: time,
          precipitationMm: rain ? row.precipitationMm : null,
          precipitationProbabilityPct: cautionProbability ? probability : null,
        );
      }
      if (row.weatherCode != null && _wetCode(row.weatherCode!)) {
        yield WeatherRisk(
          kind: WeatherRiskKind.rain,
          status: DryingStatus.notRecommended,
          riskStartTime: time,
          endTime: time.add(const Duration(hours: 1)),
          sourceTime: time,
          weatherCodes: [row.weatherCode!],
        );
      }
      final wind = row.windSpeed;
      final next = index + 1 < rows.length ? rows[index + 1] : null;
      final nextWind = next?.windSpeed;
      final interval = next?.forecastTimeUtc.difference(time);
      if (_valid(wind, DryingEvaluator.maximumReasonableWindSpeedMs) &&
          _valid(nextWind, DryingEvaluator.maximumReasonableWindSpeedMs) &&
          interval != null &&
          interval > Duration.zero &&
          interval <= const Duration(hours: 1)) {
        for (final threshold in [
          DryingEvaluator.cautionWindMs,
          DryingEvaluator.strongWindMs,
        ]) {
          if (wind! < threshold && nextWind! < threshold) continue;
          var from = time;
          var to = next!.forecastTimeUtc;
          if (wind != nextWind && (wind < threshold || nextWind! < threshold)) {
            final fraction = (threshold - wind) / (nextWind! - wind);
            final crossing = time.add(
              Duration(
                microseconds: (interval.inMicroseconds * fraction).round(),
              ),
            );
            if (wind < threshold) {
              from = crossing;
            } else {
              to = crossing;
            }
          }
          yield WeatherRisk(
            kind: WeatherRiskKind.wind,
            status: threshold == DryingEvaluator.strongWindMs
                ? DryingStatus.notRecommended
                : DryingStatus.caution,
            riskStartTime: from,
            endTime: to,
            sourceTime: next.forecastTimeUtc,
            windSpeedMs: math.max(wind, nextWind!),
            windThresholdMs: threshold,
          );
        }
        continue;
      }
      // 補間できない場合は有効な単独予報だけを使い、架空の到達時刻を作らない。
      if (_valid(wind, DryingEvaluator.maximumReasonableWindSpeedMs) &&
          wind! >= DryingEvaluator.cautionWindMs) {
        yield WeatherRisk(
          kind: WeatherRiskKind.wind,
          status: wind >= DryingEvaluator.strongWindMs
              ? DryingStatus.notRecommended
              : DryingStatus.caution,
          riskStartTime: time,
          endTime: time.add(const Duration(hours: 1)),
          sourceTime: time,
          windSpeedMs: wind,
          windThresholdMs: wind >= DryingEvaluator.strongWindMs
              ? DryingEvaluator.strongWindMs
              : DryingEvaluator.cautionWindMs,
        );
      }
    }
  }

  List<WeatherRisk> _mergeRisks(Iterable<WeatherRisk> input) {
    final rows = input.toList();
    final result = <WeatherRisk>[];
    int severity(WeatherRisk risk) =>
        risk.status == DryingStatus.notRecommended ? 2 : 1;
    for (final kind in WeatherRiskKind.values) {
      final events = rows.where((r) => r.kind == kind).toList();
      final boundaries =
          events.expand((r) => [r.riskStartTime, r.endTime]).toSet().toList()
            ..sort();
      final merged = <WeatherRisk>[];
      for (var i = 0; i < boundaries.length - 1; i++) {
        final from = boundaries[i];
        final to = boundaries[i + 1];
        final active =
            events
                .where(
                  (r) =>
                      r.riskStartTime.isBefore(to) && r.endTime.isAfter(from),
                )
                .toList()
              ..sort((a, b) {
                final order = severity(b).compareTo(severity(a));
                return order != 0
                    ? order
                    : a.sourceTime.compareTo(b.sourceTime);
              });
        if (active.isEmpty) continue;
        final strongest = active.first;
        final combined = _combineEvidence(active);
        if (merged.isNotEmpty &&
            merged.last.endTime == from &&
            merged.last.status == strongest.status) {
          final previous = merged.removeLast();
          merged.add(
            WeatherRisk(
              kind: kind,
              status: previous.status,
              riskStartTime: previous.riskStartTime,
              endTime: to,
              sourceTime: previous.sourceTime.isBefore(strongest.sourceTime)
                  ? previous.sourceTime
                  : strongest.sourceTime,
              precipitationMm: _maxNullable(
                previous.precipitationMm,
                combined.precipitationMm,
              ),
              precipitationProbabilityPct: _maxNullable(
                previous.precipitationProbabilityPct,
                combined.precipitationProbabilityPct,
              ),
              weatherCodes: {
                ...previous.weatherCodes,
                ...combined.weatherCodes,
              }.toList(),
              windSpeedMs: _maxNullable(
                previous.windSpeedMs,
                combined.windSpeedMs,
              ),
              windThresholdMs: _maxNullable(
                previous.windThresholdMs,
                combined.windThresholdMs,
              ),
            ),
          );
        } else {
          merged.add(
            WeatherRisk(
              kind: kind,
              status: strongest.status,
              riskStartTime: from,
              endTime: to,
              sourceTime: strongest.sourceTime,
              precipitationMm: combined.precipitationMm,
              precipitationProbabilityPct: combined.precipitationProbabilityPct,
              weatherCodes: combined.weatherCodes,
              windSpeedMs: combined.windSpeedMs,
              windThresholdMs: combined.windThresholdMs,
            ),
          );
        }
      }
      // 閾値ちょうどに触れて下がる瞬間も、非推奨の到達として残す。
      for (final point in events.where((r) => r.riskStartTime == r.endTime)) {
        if (!merged.any(
          (r) =>
              !r.riskStartTime.isAfter(point.riskStartTime) &&
              !r.endTime.isBefore(point.endTime) &&
              severity(r) >= severity(point),
        )) {
          merged.add(point);
        }
      }
      result.addAll(merged);
    }
    return result..sort((a, b) => a.riskStartTime.compareTo(b.riskStartTime));
  }

  WeatherRisk _combineEvidence(List<WeatherRisk> risks) {
    final codes = risks.expand((risk) => risk.weatherCodes).toSet().toList()
      ..sort();
    double? maximum(double? Function(WeatherRisk risk) value) {
      final values = risks.map(value).whereType<double>();
      return values.isEmpty ? null : values.reduce(math.max);
    }

    final first = risks.first;
    return WeatherRisk(
      kind: first.kind,
      status: first.status,
      riskStartTime: first.riskStartTime,
      endTime: first.endTime,
      sourceTime: first.sourceTime,
      precipitationMm: maximum((risk) => risk.precipitationMm),
      precipitationProbabilityPct: maximum(
        (risk) => risk.precipitationProbabilityPct,
      ),
      weatherCodes: codes,
      windSpeedMs: maximum((risk) => risk.windSpeedMs),
      windThresholdMs: maximum((risk) => risk.windThresholdMs),
    );
  }

  double? _maxNullable(double? left, double? right) {
    if (left == null) return right;
    if (right == null) return left;
    return math.max(left, right);
  }

  bool _wetCode(int code) => const {
    51,
    53,
    55,
    56,
    57,
    61,
    63,
    65,
    66,
    67,
    71,
    73,
    75,
    77,
    80,
    81,
    82,
    85,
    86,
    95,
    96,
    99,
  }.contains(code);

  bool _hasRiskCoverage(
    List<HourlyForecast> rows,
    DateTime start,
    DateTime end,
  ) {
    var covered = start;
    for (var i = 0; i < rows.length - 1; i++) {
      final a = rows[i];
      final b = rows[i + 1];
      if (!b.forecastTimeUtc.isAfter(start)) continue;
      if (a.forecastTimeUtc.isAfter(end)) break;
      final interval = b.forecastTimeUtc.difference(a.forecastTimeUtc);
      if (a.forecastTimeUtc.isAfter(covered) ||
          interval <= Duration.zero ||
          interval > const Duration(hours: 1)) {
        return false;
      }
      // 日射や温湿度とは独立に、降水の時間窓と瞬間の風・天気を検証する。
      if (!_valid(b.precipitationMm) ||
          !_valid(b.precipitationProbability, 100) ||
          !_valid(a.windSpeed, DryingEvaluator.maximumReasonableWindSpeedMs) ||
          !_valid(b.windSpeed, DryingEvaluator.maximumReasonableWindSpeedMs) ||
          !_knownCode(a.weatherCode) ||
          !_knownCode(b.weatherCode)) {
        return false;
      }
      covered = b.forecastTimeUtc;
      if (!covered.isBefore(end)) return true;
    }
    return false;
  }

  bool _knownCode(int? code) =>
      code != null &&
      (const {0, 1, 2, 3, 45, 48}.contains(code) || _wetCode(code));
}
