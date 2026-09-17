enum DryingStatus { suitable, caution, notRecommended, unknown }

class DryingConditions {
  const DryingConditions({
    this.temperatureC,
    this.humidityPct,
    this.windSpeedMs,
    this.precipitationMm,
    this.precipitationProbabilityPct,
    this.precipitationDetected,
    this.sourceTime,
  });

  final double? temperatureC;
  final double? humidityPct;
  final double? windSpeedMs;
  final double? precipitationMm;
  final double? precipitationProbabilityPct;
  final bool? precipitationDetected;
  final DateTime? sourceTime;
}

class DryingAssessment {
  DryingAssessment({required this.status, required List<String> reasons})
    : reasons = List.unmodifiable(reasons);

  final DryingStatus status;
  final List<String> reasons;
}

class DryingEvaluator {
  const DryingEvaluator();

  // v1の暫定閾値。実際の乾き方を検証しながら調整する。
  static const double strongWindMs = 8;
  static const double cautionWindMs = 5;
  static const double weakWindMs = 1;
  static const double lowTemperatureC = 10;
  static const double highHumidityPct = 80;
  static const double highPrecipitationProbabilityPct = 60;
  static const double cautionPrecipitationProbabilityPct = 30;
  static const double minimumReasonableTemperatureC = -100;
  static const double maximumReasonableTemperatureC = 70;
  static const double maximumReasonableWindSpeedMs = 150;
  static const Duration maximumAge = Duration(minutes: 60);
  static const Duration maximumFutureOffset = Duration(minutes: 5);

  DryingAssessment evaluate(
    DryingConditions conditions, {
    required DateTime now,
  }) {
    final sourceTime = conditions.sourceTime;
    if (sourceTime == null) {
      return DryingAssessment(
        status: DryingStatus.unknown,
        reasons: ['データ時刻が不明なため、現在の外干し適性を判定できません。'],
      );
    }
    final age = now.toUtc().difference(sourceTime.toUtc());
    if (age > maximumAge) {
      return DryingAssessment(
        status: DryingStatus.unknown,
        reasons: ['データが60分より古いため、最新情報を取得してください。'],
      );
    }
    if (age < -maximumFutureOffset) {
      return DryingAssessment(
        status: DryingStatus.unknown,
        reasons: ['データ時刻が現在より5分を超えて先のため、判定できません。'],
      );
    }
    return _evaluateValues(
      conditions,
      requirePrecipitationProbability: false,
      suitableReason: '現在の気温・湿度・風速と降水状況は、外干しに適した条件です。',
    );
  }

  DryingAssessment evaluateForecast(
    DryingConditions conditions, {
    required DateTime now,
  }) {
    final forecastTime = conditions.sourceTime;
    if (forecastTime == null) {
      return DryingAssessment(
        status: DryingStatus.unknown,
        reasons: ['予報時刻が不明なため、外干し適性を判定できません。'],
      );
    }
    if (forecastTime.toUtc().isBefore(now.toUtc())) {
      return DryingAssessment(
        status: DryingStatus.unknown,
        reasons: ['選択された予報時刻が過去のため、未来の時刻を選択してください。'],
      );
    }
    return _evaluateValues(
      conditions,
      requirePrecipitationProbability: true,
      suitableReason: '選択した時間の予報は、外干しに適した条件です。',
    );
  }

  DryingAssessment _evaluateValues(
    DryingConditions conditions, {
    required bool requirePrecipitationProbability,
    required String suitableReason,
  }) {
    final temperature = conditions.temperatureC;
    final humidity = conditions.humidityPct;
    final wind = conditions.windSpeedMs;
    final precipitation = conditions.precipitationMm;
    final probability = conditions.precipitationProbabilityPct;
    final hasTemperature = _isTemperature(temperature);
    final hasHumidity = _isPercentage(humidity);
    final hasWind = _isWindSpeed(wind);
    final hasPrecipitation = _isNonnegative(precipitation);
    final hasProbability = _isPercentage(probability);

    final issues = <String>[];
    if (!hasTemperature) {
      issues.add('気温が欠損または不正なため、乾きやすさを判定できません。');
    }
    if (!hasHumidity) {
      issues.add('湿度が欠損または不正なため、乾きやすさを判定できません。');
    }
    if (!hasWind) {
      issues.add('風速が欠損または不正なため、風の影響を判定できません。');
    }
    if (precipitation != null && !hasPrecipitation) {
      issues.add('降水量が不正です。');
    }
    if (probability != null && !hasProbability) {
      issues.add('降水確率が不正です。');
    } else if (requirePrecipitationProbability && probability == null) {
      issues.add('降水確率が欠損しているため、予報を判定できません。');
    }
    // 降水確率だけでは、現在の雨・雪の有無は確定できない。
    if (!hasPrecipitation && conditions.precipitationDetected == null) {
      issues.add('雨・雪の有無が不明です。');
    }

    final stops = <String>[];
    final cautions = <String>[];
    if (conditions.precipitationDetected == true ||
        (hasPrecipitation && precipitation! > 0)) {
      stops.add('雨・雪などの降水があるため、外干しには適していません。');
    }
    if (hasWind) {
      if (wind! >= strongWindMs) {
        stops.add('風速が8 m/s以上で、洗濯物が飛ばされるおそれがあります。');
      } else if (wind >= cautionWindMs) {
        cautions.add('風速が5 m/s以上のため、洗濯物をしっかり固定してください。');
      } else if (wind < weakWindMs) {
        cautions.add('風速が1 m/s未満で、洗濯物が乾きにくい条件です。');
      }
    }
    if (hasProbability) {
      if (probability! >= highPrecipitationProbabilityPct) {
        stops.add('降水確率が60%以上のため、外干しを控えてください。');
      } else if (probability >= cautionPrecipitationProbabilityPct) {
        cautions.add('降水確率が30%以上のため、天候の変化に注意してください。');
      }
    }
    if (hasTemperature && temperature! < lowTemperatureC) {
      cautions.add('気温が10℃未満で、洗濯物が乾きにくい条件です。');
    }
    if (hasHumidity && humidity! >= highHumidityPct) {
      cautions.add('湿度が80%以上で、洗濯物が乾きにくい条件です。');
    }

    // 独立に確認できた降水・強風のNGを、他項目の欠損で隠さない。
    if (stops.isNotEmpty) {
      return DryingAssessment(
        status: DryingStatus.notRecommended,
        reasons: [...stops, ...issues, ...cautions],
      );
    }
    if (issues.isNotEmpty) {
      return DryingAssessment(
        status: DryingStatus.unknown,
        reasons: [...issues, ...cautions],
      );
    }
    if (cautions.isNotEmpty) {
      return DryingAssessment(status: DryingStatus.caution, reasons: cautions);
    }
    return DryingAssessment(
      status: DryingStatus.suitable,
      reasons: [suitableReason],
    );
  }

  bool _isFinite(double? value) => value != null && value.isFinite;

  bool _isNonnegative(double? value) => _isFinite(value) && value! >= 0;

  bool _isPercentage(double? value) => _isNonnegative(value) && value! <= 100;

  bool _isTemperature(double? value) =>
      _isFinite(value) &&
      value! >= minimumReasonableTemperatureC &&
      value <= maximumReasonableTemperatureC;

  bool _isWindSpeed(double? value) =>
      _isNonnegative(value) && value! <= maximumReasonableWindSpeedMs;
}
