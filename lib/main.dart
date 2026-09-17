import 'dart:async';

import 'package:flutter/material.dart';

import 'drying_assessment.dart';
import 'geocoding_api.dart';
import 'location_search_dialog.dart';
import 'models/weather.dart';
import 'models/weather_location.dart';
import 'weather_api.dart';

void main() {
  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DryNow',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const WeatherPage(),
    );
  }
}

class WeatherPage extends StatefulWidget {
  final WeatherApi? api;
  final GeocodingApi? geocodingApi;
  final DateTime Function()? now;
  final WeatherLocation initialLocation;

  const WeatherPage({
    super.key,
    this.api,
    this.geocodingApi,
    this.now,
    this.initialLocation = WeatherLocation.kasukabe,
  });

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> with WidgetsBindingObserver {
  static const _offsetOptions = [1, 2, 3, 6, 9, 12, 18, 24];

  late Future<ForecastResponse> _forecastFuture;
  late final WeatherApi _weatherApi;
  late final GeocodingApi _geocodingApi;
  late final Timer _freshnessTimer;
  late WeatherLocation _selectedLocation;
  late DateTime _plannedTime;
  int _selectedOffsetHours = 1;

  @override
  void initState() {
    super.initState();
    _weatherApi = widget.api ?? WeatherApi();
    _geocodingApi = widget.geocodingApi ?? GeocodingApi();
    _selectedLocation = widget.initialLocation;
    _plannedTime = _currentTime().add(Duration(hours: _selectedOffsetHours));
    _forecastFuture = _fetchForecast(_selectedLocation);
    WidgetsBinding.instance.addObserver(this);
    // 表示中に予報時刻を過ぎた場合も、過去の予報を適性ありで残さない。
    _freshnessTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  DateTime _currentTime() => (widget.now ?? DateTime.now)();

  Future<ForecastResponse> _fetchForecast(WeatherLocation location) =>
      _weatherApi.fetchHourlyForecastByCoordinates(
        location.latitude,
        location.longitude,
        cityName: location.name,
      );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _freshnessTimer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.api == null) _weatherApi.close();
    if (widget.geocodingApi == null) _geocodingApi.close();
    super.dispose();
  }

  void _refreshForecast() {
    setState(() {
      _plannedTime = _currentTime().add(Duration(hours: _selectedOffsetHours));
      _forecastFuture = _fetchForecast(_selectedLocation);
    });
  }

  void _selectOffset(int hours) {
    setState(() {
      _selectedOffsetHours = hours;
      _plannedTime = _currentTime().add(Duration(hours: hours));
    });
  }

  Future<void> _openLocationSearch() async {
    final location = await showDialog<WeatherLocation>(
      context: context,
      builder: (context) => LocationSearchDialog(api: _geocodingApi),
    );
    if (location == null || !mounted) return;
    setState(() {
      _selectedLocation = location;
      _plannedTime = _currentTime().add(Duration(hours: _selectedOffsetHours));
      _forecastFuture = _fetchForecast(location);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DryNow')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('location-button'),
                        onPressed: _openLocationSearch,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_outlined, size: 20),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _selectedLocation.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            const Icon(Icons.chevron_right, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'いつから干しますか？',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final hours in _offsetOptions)
                          ChoiceChip(
                            key: Key('offset-$hours'),
                            label: Text('${hours}h'),
                            selected: _selectedOffsetHours == hours,
                            onSelected: (selected) {
                              if (selected) _selectOffset(hours);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '干す予定 ${_formatDateTime(_plannedTime)}',
                      key: const Key('planned-time'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 20),
                    FutureBuilder<ForecastResponse>(
                      future: _forecastFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return _ForecastLoading(location: _selectedLocation);
                        }
                        if (snapshot.hasError) {
                          return _ForecastError(
                            error: snapshot.error!,
                            onRetry: _refreshForecast,
                          );
                        }
                        return _ForecastContent(
                          response: snapshot.data!,
                          plannedTime: _plannedTime,
                          now: _currentTime(),
                          onRefresh: _refreshForecast,
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '※現在は干し始め時点の予報をもとに判定しています。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      'Weather data by Open-Meteo.com · CC BY 4.0\n'
                      'https://open-meteo.com/ · 取得データを表示用に加工',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _ForecastLoading extends StatelessWidget {
  const _ForecastLoading({required this.location});

  final WeatherLocation location;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('forecast-loading'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text('${location.name}の予報を取得しています…'),
          ],
        ),
      ),
    );
  }
}

class _ForecastError extends StatelessWidget {
  const _ForecastError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('forecast-error'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 10),
            const Text(
              '時間別予報を取得できませんでした',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _readableError(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForecastContent extends StatelessWidget {
  const _ForecastContent({
    required this.response,
    required this.plannedTime,
    required this.now,
    required this.onRefresh,
  });

  final ForecastResponse response;
  final DateTime plannedTime;
  final DateTime now;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final forecast = response.forecastNearestTo(plannedTime);
    final assessment = forecast == null
        ? DryingAssessment(
            status: DryingStatus.unknown,
            reasons: [
              response.series.forecasts.isEmpty
                  ? '時間別予報データがありません。再読み込みしてください。'
                  : '指定した時刻に対応する時間別予報がありません。時刻を変更するか再読み込みしてください。',
            ],
          )
        : const DryingEvaluator().evaluateForecast(
            forecast.dryingConditions,
            now: now,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AssessmentCard(forecast: forecast, assessment: assessment),
        if (assessment.reasons.length > 1) ...[
          const SizedBox(height: 8),
          _AdditionalReasons(reasons: assessment.reasons.skip(1).toList()),
        ],
        const SizedBox(height: 16),
        if (forecast != null) _WeatherMetrics(forecast: forecast),
        if (forecast == null) const Center(child: Text('予報値を表示できません。')),
        const SizedBox(height: 14),
        if (forecast != null)
          Text(
            '降水量 ${forecast.precipitationText}　・　使用予報 ${_formatTime(forecast.forecastTimeUtc)}',
            key: const Key('forecast-supplement'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 6),
        Text(
          'API格子 ${response.series.coordinatesText}　・　取得 ${_formatTime(response.fetchedAt)}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.center,
          child: OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('予報を更新'),
          ),
        ),
      ],
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.forecast, required this.assessment});

  final HourlyForecast? forecast;
  final DryingAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(context, assessment.status);
    return Semantics(
      label:
          '${_assessmentTitle(assessment.status)}。${assessment.reasons.first}',
      child: Card(
        key: const Key('assessment-card'),
        color: style.background,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
          child: Column(
            children: [
              Icon(
                _weatherIcon(forecast?.weatherCode),
                size: 56,
                color: style.foreground,
              ),
              const SizedBox(height: 6),
              Text(
                forecast?.description ?? '予報不明',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(style.statusIcon, color: style.foreground),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _assessmentTitle(assessment.status),
                      key: const Key('assessment-title'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: style.foreground,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _summaryReason(assessment),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdditionalReasons extends StatelessWidget {
  const _AdditionalReasons({required this.reasons});

  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'その他の判定理由',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            for (final reason in reasons) Text('・$reason'),
          ],
        ),
      ),
    );
  }
}

class _WeatherMetrics extends StatelessWidget {
  const _WeatherMetrics({required this.forecast});

  final HourlyForecast forecast;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final twoColumns = constraints.maxWidth >= 480;
        final width = twoColumns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: width,
              child: _WeatherMetricCard(
                key: const Key('metric-temperature'),
                icon: Icons.thermostat,
                label: '気温',
                value: forecast.temperatureText,
              ),
            ),
            SizedBox(
              width: width,
              child: _WeatherMetricCard(
                key: const Key('metric-humidity'),
                icon: Icons.water_drop_outlined,
                label: '湿度',
                value: forecast.humidityText,
              ),
            ),
            SizedBox(
              width: width,
              child: _WeatherMetricCard(
                key: const Key('metric-wind'),
                icon: Icons.air,
                label: '風速',
                value: forecast.windSpeedText,
              ),
            ),
            SizedBox(
              width: width,
              child: _WeatherMetricCard(
                key: const Key('metric-probability'),
                icon: Icons.umbrella_outlined,
                label: '降水確率',
                value: forecast.precipitationProbabilityText,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WeatherMetricCard extends StatelessWidget {
  const _WeatherMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _StatusStyle = ({
  Color background,
  Color foreground,
  IconData statusIcon,
});

_StatusStyle _statusStyle(BuildContext context, DryingStatus status) {
  final colors = Theme.of(context).colorScheme;
  return switch (status) {
    DryingStatus.suitable => (
      background: const Color(0xffe5f5e9),
      foreground: const Color(0xff176b35),
      statusIcon: Icons.check_circle_outline,
    ),
    DryingStatus.caution => (
      background: const Color(0xfffff3d6),
      foreground: const Color(0xff805500),
      statusIcon: Icons.warning_amber_rounded,
    ),
    DryingStatus.notRecommended => (
      background: colors.errorContainer,
      foreground: colors.onErrorContainer,
      statusIcon: Icons.cancel_outlined,
    ),
    DryingStatus.unknown => (
      background: colors.surfaceContainerHighest,
      foreground: colors.onSurfaceVariant,
      statusIcon: Icons.help_outline,
    ),
  };
}

String _assessmentTitle(DryingStatus status) => switch (status) {
  DryingStatus.suitable => '外干しOK',
  DryingStatus.caution => '外干しは注意',
  DryingStatus.notRecommended => '外干しNG',
  DryingStatus.unknown => '判定できません',
};

String _summaryReason(DryingAssessment assessment) =>
    switch (assessment.status) {
      DryingStatus.suitable => '今のところ外干しに適した予報です。',
      _ => assessment.reasons.first,
    };

IconData _weatherIcon(int? code) => switch (code) {
  0 || 1 => Icons.wb_sunny_outlined,
  2 || 3 => Icons.cloud_outlined,
  51 ||
  53 ||
  55 ||
  56 ||
  57 ||
  61 ||
  63 ||
  65 ||
  66 ||
  67 ||
  80 ||
  81 ||
  82 => Icons.umbrella_outlined,
  95 || 96 || 99 => Icons.thunderstorm_outlined,
  71 || 73 || 75 || 77 || 85 || 86 => Icons.ac_unit,
  _ => Icons.cloud_queue,
};

String _formatTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  final local = value.toLocal();
  return '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String _readableError(Object error) => error.toString().replaceFirst(
  RegExp(r'^(Exception|FormatException): '),
  '',
);
