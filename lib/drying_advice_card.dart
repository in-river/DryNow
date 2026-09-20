import 'package:flutter/material.dart';

import 'drying_advice.dart';
import 'drying_assessment.dart';
import 'drying_estimator.dart';

class DryingAdviceCard extends StatelessWidget {
  const DryingAdviceCard({
    super.key,
    required this.advice,
    required this.locationUtcOffset,
    this.referenceTime,
  });

  final DryingAdvice advice;
  final Duration? locationUtcOffset;
  final DateTime? referenceTime;

  DateTime? _local(DateTime time) =>
      locationUtcOffset == null ? null : time.toUtc().add(locationUtcOffset!);

  String _clock(DateTime utc) {
    final local = _local(utc);
    if (local == null) return '時刻不明';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String _completionTime(DateTime utc) {
    final local = _local(utc);
    final reference = _local(referenceTime ?? DateTime.now());
    if (local == null || reference == null) return '時刻不明';
    final localDate = DateTime.utc(local.year, local.month, local.day);
    final referenceDate = DateTime.utc(
      reference.year,
      reference.month,
      reference.day,
    );
    final days = localDate.difference(referenceDate).inDays;
    final day = switch (days) {
      0 => '今日',
      1 => '明日',
      2 => 'あさって',
      _ => '${local.month}/${local.day}',
    };
    return '$day ${_clock(utc)}';
  }

  String _duration(Duration value) {
    final minutes = (value.inSeconds / 60).ceil();
    return minutes < 60 ? '約$minutes分' : '約${minutes ~/ 60}時間${minutes % 60}分';
  }

  DryingStatus get _displayStatus {
    final states = advice.garments.map((garment) => garment.status).toList();
    if (states.contains(DryingStatus.notRecommended)) {
      return DryingStatus.notRecommended;
    }
    if (states.isNotEmpty &&
        states.every((state) => state == DryingStatus.unknown)) {
      return DryingStatus.unknown;
    }
    if (states.contains(DryingStatus.caution) ||
        states.contains(DryingStatus.unknown)) {
      return DryingStatus.caution;
    }
    return states.isEmpty ? advice.overallStatus : DryingStatus.suitable;
  }

  String _actionTitle(DryingStatus status) => switch (status) {
    DryingStatus.suitable => '外干しできます',
    DryingStatus.caution => '外干しできますが注意',
    DryingStatus.notRecommended => '室内干しがおすすめ',
    DryingStatus.unknown => '今回は判定できません',
  };

  String _actionReason(DryingStatus status) {
    final hasRain = advice.weatherRisks.any(
      (risk) => risk.kind == WeatherRiskKind.rain,
    );
    final hasWind = advice.weatherRisks.any(
      (risk) => risk.kind == WeatherRiskKind.wind,
    );
    final hasSevereRain = advice.weatherRisks.any(
      (risk) =>
          risk.kind == WeatherRiskKind.rain &&
          risk.status == DryingStatus.notRecommended,
    );
    final hasSevereWind = advice.weatherRisks.any(
      (risk) =>
          risk.kind == WeatherRiskKind.wind &&
          risk.status == DryingStatus.notRecommended,
    );
    return switch (status) {
      DryingStatus.suitable => '雨や強風の前に乾く見込みです',
      DryingStatus.notRecommended when hasSevereRain => '乾き切る前に雨の予報があります',
      DryingStatus.notRecommended when hasSevereWind => '乾くまでに強い風の予報があります',
      DryingStatus.notRecommended => '外干しに適さない予報があります',
      DryingStatus.caution when hasRain => '雨の予報が近く、外干しには余裕がありません',
      DryingStatus.caution when hasWind => '風が強まる予報に注意してください',
      DryingStatus.caution => '一部の衣類は予報範囲内で確認できません',
      DryingStatus.unknown => '予報範囲内で乾燥完了を確認できません',
    };
  }

  IconData _icon(DryingStatus status) => switch (status) {
    DryingStatus.suitable => Icons.wb_sunny_outlined,
    DryingStatus.caution => Icons.warning_amber_rounded,
    DryingStatus.notRecommended => Icons.home_outlined,
    DryingStatus.unknown => Icons.help_outline,
  };

  String _label(DryingStatus status) => switch (status) {
    DryingStatus.suitable => '外干しOK',
    DryingStatus.caution => '注意',
    DryingStatus.notRecommended => '外干し非推奨',
    DryingStatus.unknown => '判定不能',
  };

  String _garmentLabel(GarmentAdvice garment) =>
      switch (garment.estimate.category.id) {
        'thin' => '薄手',
        'normal' => '普通',
        'thick' => '厚手',
        _ => garment.estimate.category.label,
      };

  ({Color background, Color foreground}) _garmentColors(
    BuildContext context,
    GarmentAdvice garment,
  ) => switch (garment.estimate.category.id) {
    'thin' => (
      background: const Color(0xffedf9f2),
      foreground: const Color(0xff138a5b),
    ),
    'normal' => (
      background: const Color(0xffeef6ff),
      foreground: const Color(0xff287fc4),
    ),
    'thick' => (
      background: const Color(0xfff5f1fb),
      foreground: const Color(0xff6953a6),
    ),
    _ => (
      background: Theme.of(context).colorScheme.surfaceContainerLow,
      foreground: Theme.of(context).colorScheme.primary,
    ),
  };

  Widget _garmentCard(BuildContext context, GarmentAdvice garment) {
    final colors = Theme.of(context).colorScheme;
    final completion = garment.estimate.estimatedCompletionTime;
    final estimateStatus = garment.estimate.status;
    final unavailableTitle =
        estimateStatus == DryingEstimateStatus.forecastLimit
        ? '乾燥予想　予報範囲外'
        : '乾燥予想　表示できません';
    final unavailableReason =
        estimateStatus == DryingEstimateStatus.forecastLimit
        ? '予報範囲内では乾燥完了を確認できません'
        : '気象データが足りないため乾燥予想を表示できません';
    final garmentColors = _garmentColors(context, garment);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: garmentColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Semantics(
        label: '${garment.estimate.category.label}、${_label(garment.status)}',
        child: Padding(
          key: Key('garment-${garment.estimate.category.id}'),
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.checkroom_outlined,
                size: 28,
                color: garmentColors.foreground,
              ),
              const SizedBox(height: 7),
              Text(
                _garmentLabel(garment),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                garment.estimate.category.examples,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: garmentColors.foreground.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 11),
              if (completion != null) ...[
                Text(
                  '乾燥完了',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _completionTime(completion),
                    key: Key('completion-${garment.estimate.category.id}'),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 15,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _duration(garment.estimate.estimatedDuration!),
                          key: Key('duration-${garment.estimate.category.id}'),
                          maxLines: 1,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  unavailableTitle,
                  key: Key('completion-${garment.estimate.category.id}'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unavailableReason,
                  key: Key('unavailable-${garment.estimate.category.id}'),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = _displayStatus;
    final summaryBackground = switch (status) {
      DryingStatus.suitable => const Color(0xffeaf4ff),
      DryingStatus.caution => const Color(0xfffff5dc),
      DryingStatus.notRecommended => const Color(0xffeaf4ff),
      DryingStatus.unknown => colors.surfaceContainerHighest,
    };
    final summaryForeground = colors.onSurface;
    final summaryAccent = switch (status) {
      DryingStatus.suitable => colors.primary,
      DryingStatus.caution => const Color(0xff9a6700),
      DryingStatus.notRecommended => colors.primary,
      DryingStatus.unknown => colors.outline,
    };

    return Column(
      key: const Key('drying-advice-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: const Key('drying-summary-card'),
          margin: EdgeInsets.zero,
          color: summaryBackground,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon(status), size: 29, color: summaryAccent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '総合判定',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _actionTitle(status),
                        key: const Key('drying-advice-title'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: summaryForeground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _actionReason(status),
                        key: const Key('drying-advice-summary'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (advice.garments.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.schedule_outlined, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                '乾燥予測',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (
                  var index = 0;
                  index < advice.garments.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _garmentCard(context, advice.garments[index]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class DryingDetailsTile extends StatelessWidget {
  const DryingDetailsTile({
    super.key,
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: tileKey,
        initiallyExpanded: initiallyExpanded,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: children,
      ),
    );
  }
}

class WeatherRiskDetails extends StatelessWidget {
  const WeatherRiskDetails({
    super.key,
    required this.risks,
    required this.locationUtcOffset,
    this.initiallyExpanded = false,
  });

  final List<WeatherRisk> risks;
  final Duration? locationUtcOffset;
  final bool initiallyExpanded;

  DateTime? _local(DateTime utc) =>
      locationUtcOffset == null ? null : utc.toUtc().add(locationUtcOffset!);

  String _clock(DateTime utc) {
    final local = _local(utc);
    if (local == null) return '時刻不明';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  String _timeRange(DateTime startUtc, DateTime endUtc) {
    final start = _local(startUtc);
    final end = _local(endUtc);
    if (start == null || end == null) return '時刻不明';
    final sameDate =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (startUtc == endUtc) return '${_clock(startUtc)}ごろ';
    if (sameDate) return '${_clock(startUtc)}〜${_clock(endUtc)}ごろ';
    return '${start.month}/${start.day} ${_clock(startUtc)}〜'
        '${end.month}/${end.day} ${_clock(endUtc)}ごろ';
  }

  double? _maximum(Iterable<double?> values) {
    double? result;
    for (final value in values) {
      if (value != null && (result == null || value > result)) result = value;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final rainRisks = risks
        .where((risk) => risk.kind == WeatherRiskKind.rain)
        .toList();
    final windRisks = risks
        .where((risk) => risk.kind == WeatherRiskKind.wind)
        .toList();
    final rainStart = rainRisks.isEmpty
        ? null
        : rainRisks
              .map((risk) => risk.riskStartTime)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    final rainEnd = rainRisks.isEmpty
        ? null
        : rainRisks
              .map((risk) => risk.endTime)
              .reduce((a, b) => a.isAfter(b) ? a : b);
    final maxProbability = _maximum(
      rainRisks.map((risk) => risk.precipitationProbabilityPct),
    );
    final maxPrecipitation = _maximum(
      rainRisks.map((risk) => risk.precipitationMm),
    );
    final windStart = windRisks.isEmpty
        ? null
        : windRisks
              .map((risk) => risk.riskStartTime)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    final maxWind = _maximum(
      windRisks.expand((risk) => [risk.windSpeedMs, risk.windThresholdMs]),
    );
    return DryingDetailsTile(
      tileKey: const Key('weather-risk-details'),
      icon: Icons.warning_amber_rounded,
      title: '雨・風の注意',
      initiallyExpanded: initiallyExpanded,
      children: [
        if (rainStart != null && rainEnd != null)
          _WeatherRiskSummary(
            key: const Key('weather-risk-rain-summary'),
            icon: Icons.umbrella_outlined,
            title: '雨',
            message: '${_timeRange(rainStart, rainEnd)}まで雨の可能性があります',
            details: [
              if (maxProbability != null) '最大降水確率 ${_number(maxProbability)}%',
              if (maxPrecipitation != null && maxPrecipitation > 0)
                '予想降水量 最大${_number(maxPrecipitation)}mm',
            ],
          ),
        if (rainRisks.isNotEmpty && windRisks.isNotEmpty)
          const Divider(height: 28),
        if (windStart != null)
          _WeatherRiskSummary(
            key: const Key('weather-risk-wind-summary'),
            icon: Icons.air,
            title: '風',
            message: '${_clock(windStart)}ごろから風が強まる見込みです',
            details: [if (maxWind != null) '最大風速 ${_number(maxWind)}m/s程度'],
          ),
      ],
    );
  }
}

class _WeatherRiskSummary extends StatelessWidget {
  const _WeatherRiskSummary({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.details,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<String> details;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(
          icon,
          size: 22,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(message),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                details.join('・'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class DryingPredictionAbout extends StatelessWidget {
  const DryingPredictionAbout({
    super.key,
    required this.advice,
    required this.locationUtcOffset,
    required this.timezone,
    this.referenceTime,
    this.initiallyExpanded = false,
  });

  final DryingAdvice advice;
  final Duration? locationUtcOffset;
  final String? timezone;
  final DateTime? referenceTime;
  final bool initiallyExpanded;

  bool _needsNightNotice(GarmentAdvice garment) {
    final completion = garment.estimate.estimatedCompletionTime;
    if (completion == null || locationUtcOffset == null) return false;
    final localCompletion = completion.toUtc().add(locationUtcOffset!);
    final localReference = (referenceTime ?? DateTime.now()).toUtc().add(
      locationUtcOffset!,
    );
    final nextDay =
        DateTime.utc(
          localCompletion.year,
          localCompletion.month,
          localCompletion.day,
        ).isAfter(
          DateTime.utc(
            localReference.year,
            localReference.month,
            localReference.day,
          ),
        );
    return nextDay || localCompletion.hour < 6 || localCompletion.hour >= 18;
  }

  @override
  Widget build(BuildContext context) {
    final hasNightPrediction = advice.garments.any(_needsNightNotice);
    final roofMessages = advice.detailMessages.where(
      (message) => message.contains('屋根') || message.contains('吹き込み'),
    );
    return DryingDetailsTile(
      tileKey: const Key('prediction-about'),
      icon: Icons.info_outline,
      title: 'この予測について',
      initiallyExpanded: initiallyExpanded,
      children: [
        if (hasNightPrediction)
          const _AboutText(
            key: Key('night-limitation'),
            text: '夜間の再吸湿・結露を考慮していないため、夜間・翌日の時刻は参考値です。',
          ),
        const _AboutText(
          key: Key('model-limitation'),
          text: '乾燥時間は公開データと理論式をもとにした目安で、素材・脱水・干し方により変わります。',
        ),
        const _AboutText(
          key: Key('rewetting-limitation'),
          text: '雨による濡れ直しは乾燥時間へ計算していません。',
        ),
        for (final message in roofMessages) _AboutText(text: message),
        _AboutText(
          key: const Key('timezone-note'),
          text: '時刻は選択地点（${timezone ?? '時差不明'}）の時刻です。',
        ),
      ],
    );
  }
}

class _AboutText extends StatelessWidget {
  const _AboutText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Align(alignment: Alignment.centerLeft, child: Text('・$text')),
  );
}
