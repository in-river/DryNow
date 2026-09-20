import 'models/drying_environment.dart';

class GarmentCategory {
  const GarmentCategory(
    this.id,
    this.label,
    this.examples,
    this.requiredDrying,
  );
  final String id;
  final String label;
  final String examples;
  final double requiredDrying;
}

class DryingModelConfig {
  // 乾燥時間との対応は未検証。以下は今後文献・実測で変更する暫定値。
  const DryingModelConfig({
    this.k = 0.1,
    // v1の過大評価傾向を緩和する暫定値。2026/9/18の観察と感度分析から1.4を仮採用する。
    // 正式な実測校正値ではなく、v2で再評価または廃止する。
    this.provisionalDryingCalibrationFactor = 1.4,
    this.windAmplitude = 1,
    this.windScale = 1.5,
    this.solarAmplitude = 1,
    this.solarScale = 300,
    this.goodWindExposure = 1,
    this.normalWindExposure = 0.7,
    this.poorWindExposure = 0.4,
    this.sunnyExposure = 1,
    this.shadedExposure = 0.2,
    this.dayStartHour = 6,
    this.afternoonStartHour = 12,
    this.dayEndHour = 18,
    this.safetyMargin = const Duration(minutes: 30),
    this.maximumForecastAge = const Duration(hours: 3),
    this.maximumSolarRadiation = 1500,
    this.categories = const [
      GarmentCategory('thin', '薄手・速乾', '肌着・靴下・速乾ウェア', 0.8),
      GarmentCategory('normal', '標準', '綿Tシャツ・シャツ・フェイスタオル', 1.2),
      GarmentCategory('thick', '厚手・乾きにくい', 'パーカー・デニム・バスタオル', 1.8),
    ],
  });

  final double k;
  final double provisionalDryingCalibrationFactor;
  final double windAmplitude;
  final double windScale;
  final double solarAmplitude;
  final double solarScale;
  final double goodWindExposure;
  final double normalWindExposure;
  final double poorWindExposure;
  final double sunnyExposure;
  final double shadedExposure;
  final int dayStartHour;
  final int afternoonStartHour;
  final int dayEndHour;
  final Duration safetyMargin;
  final Duration maximumForecastAge;
  final double maximumSolarRadiation;
  final List<GarmentCategory> categories;

  double windExposure(WindExposure value) => switch (value) {
    WindExposure.good => goodWindExposure,
    WindExposure.normal => normalWindExposure,
    WindExposure.poor => poorWindExposure,
  };

  double sunExposure(SunExposurePattern pattern, DateTime locationTime) {
    final hour = locationTime.hour;
    if (hour < dayStartHour || hour >= dayEndHour) return 0;
    final sunny = switch (pattern) {
      SunExposurePattern.allDay => true,
      SunExposurePattern.morningOnly => hour < afternoonStartHour,
      SunExposurePattern.afternoonOnly => hour >= afternoonStartHour,
      SunExposurePattern.shaded => false,
    };
    return sunny ? sunnyExposure : shadedExposure;
  }

  void validate() {
    final positive = [
      k,
      provisionalDryingCalibrationFactor,
      windScale,
      solarScale,
      maximumSolarRadiation,
    ];
    final nonnegative = [windAmplitude, solarAmplitude];
    final fractions = [
      goodWindExposure,
      normalWindExposure,
      poorWindExposure,
      sunnyExposure,
      shadedExposure,
    ];
    if (positive.any((v) => !v.isFinite || v <= 0) ||
        nonnegative.any((v) => !v.isFinite || v < 0) ||
        fractions.any((v) => !v.isFinite || v < 0 || v > 1) ||
        dayStartHour < 0 ||
        dayStartHour >= afternoonStartHour ||
        afternoonStartHour >= dayEndHour ||
        dayEndHour > 24 ||
        safetyMargin.isNegative ||
        maximumForecastAge <= Duration.zero ||
        categories.isEmpty ||
        categories.map((c) => c.id).toSet().length != categories.length ||
        categories.any(
          (c) =>
              c.id.isEmpty ||
              !c.requiredDrying.isFinite ||
              c.requiredDrying <= 0,
        )) {
      throw ArgumentError('乾燥モデルの設定値が不正です。');
    }
  }
}
