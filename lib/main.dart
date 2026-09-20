import 'dart:async';

import 'package:flutter/material.dart';

import 'drying_assessment.dart';
import 'drying_advice.dart';
import 'drying_advice_card.dart';
import 'environment_setup.dart';
import 'environment_store.dart';
import 'geocoding_api.dart';
import 'location_search_dialog.dart';
import 'models/weather.dart';
import 'models/weather_location.dart';
import 'models/drying_environment.dart';
import 'weather_api.dart';

void main() {
  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({
    super.key,
    this.environmentStore,
    this.api,
    this.geocodingApi,
    this.now,
  });
  final EnvironmentStore? environmentStore;
  final WeatherApi? api;
  final GeocodingApi? geocodingApi;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff1479d1),
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DryNow',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xfff8fafc),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfff8fafc),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: EnvironmentGate(
        store: environmentStore ?? PreferencesEnvironmentStore(),
        builder: (environment, saveEnvironment) => WeatherPage(
          environment: environment,
          onSaveEnvironment: saveEnvironment,
          api: api,
          geocodingApi: geocodingApi,
          now: now,
        ),
      ),
    );
  }
}

class WeatherPage extends StatefulWidget {
  final WeatherApi? api;
  final GeocodingApi? geocodingApi;
  final DateTime Function()? now;
  final WeatherLocation initialLocation;
  final DryingEnvironment? environment;
  final EnvironmentSaver? onSaveEnvironment;

  const WeatherPage({
    super.key,
    this.api,
    this.geocodingApi,
    this.now,
    this.environment,
    this.onSaveEnvironment,
    this.initialLocation = WeatherLocation.kasukabe,
  });

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> with WidgetsBindingObserver {
  static const _offsetOptions = [1, 2, 3, 6];

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
    if (widget.environment != null) _selectedOffsetHours = 0;
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

  Future<WeatherLocation?> _selectLocation() async {
    final location = await showDialog<WeatherLocation>(
      context: context,
      builder: (context) => LocationSearchDialog(api: _geocodingApi),
    );
    if (location == null || !mounted) return null;
    setState(() {
      _selectedLocation = location;
      _plannedTime = _currentTime().add(Duration(hours: _selectedOffsetHours));
      _forecastFuture = _fetchForecast(location);
    });
    return location;
  }

  Future<void> _openLocationSearch() async {
    await _selectLocation();
  }

  Future<void> _openSettings() async {
    final environment = widget.environment;
    final saveEnvironment = widget.onSaveEnvironment;
    if (environment == null || saveEnvironment == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EnvironmentSettingsPage(
          initialEnvironment: environment,
          initialLocation: _selectedLocation,
          onSelectLocation: _selectLocation,
          onSaveEnvironment: saveEnvironment,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayNow = _currentTime();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        titleSpacing: 20,
        title: const _DryNowBrand(),
        actions: [
          if (widget.onSaveEnvironment != null)
            IconButton(
              key: const Key('environment-settings'),
              tooltip: '干す環境の設定',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined, size: 28),
            ),
          const SizedBox(width: 12),
        ],
      ),
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
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_outlined, size: 20),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${_selectedLocation.name}の予報を使用中',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          'いつから干しますか？',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule_outlined,
                              size: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                '開始時刻 ${formatRelativeDeviceTime(_selectedOffsetHours == 0 ? displayNow : _plannedTime, displayNow)}',
                                key: const Key('planned-time'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      key: const Key('offset-row'),
                      children: [
                        if (widget.environment != null) ...[
                          Expanded(
                            child: _OffsetChip(
                              chipKey: const Key('offset-0'),
                              label: '今から',
                              selected: _selectedOffsetHours == 0,
                              onSelected: () => _selectOffset(0),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        for (
                          var index = 0;
                          index < _offsetOptions.length;
                          index++
                        ) ...[
                          Expanded(
                            child: _OffsetChip(
                              chipKey: Key('offset-${_offsetOptions[index]}'),
                              label: '+${_offsetOptions[index]}h',
                              selected:
                                  _selectedOffsetHours == _offsetOptions[index],
                              onSelected: () =>
                                  _selectOffset(_offsetOptions[index]),
                            ),
                          ),
                          if (index < _offsetOptions.length - 1)
                            const SizedBox(width: 6),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),
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
                        final now = _currentTime();
                        return _ForecastContent(
                          response: snapshot.data!,
                          plannedTime: _selectedOffsetHours == 0
                              ? now
                              : _plannedTime,
                          now: now,
                          environment: widget.environment,
                          onRefresh: _refreshForecast,
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    if (widget.environment == null) ...[
                      Text(
                        '※現在は干し始め時点の予報をもとに判定しています。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DryNowBrand extends StatelessWidget {
  const _DryNowBrand();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.wb_sunny_outlined,
              size: 39,
              color: const Color(0xffffb52e),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 13, left: 12),
              child: Icon(
                Icons.checkroom_outlined,
                size: 31,
                color: colors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Dry'),
                  TextSpan(
                    text: 'Now',
                    style: TextStyle(color: colors.primary),
                  ),
                ],
              ),
              maxLines: 1,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _OffsetChip extends StatelessWidget {
  const _OffsetChip({
    required this.chipKey,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final Key chipKey;
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      key: chipKey,
      label: SizedBox(
        width: double.infinity,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1),
        ),
      ),
      selected: selected,
      onSelected: (value) {
        if (value) onSelected();
      },
      showCheckmark: false,
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 9),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

String formatRelativeDeviceTime(DateTime value, DateTime reference) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  final local = value.toLocal();
  final localReference = reference.toLocal();
  final date = DateTime.utc(local.year, local.month, local.day);
  final referenceDate = DateTime.utc(
    localReference.year,
    localReference.month,
    localReference.day,
  );
  final dayDifference = date.difference(referenceDate).inDays;
  final dayLabel = switch (dayDifference) {
    0 => '今日',
    1 => '明日',
    _ => '${local.month}/${local.day}',
  };
  return '$dayLabel ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
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
    this.environment,
  });

  final ForecastResponse response;
  final DateTime plannedTime;
  final DateTime now;
  final VoidCallback onRefresh;
  final DryingEnvironment? environment;

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
    final dryingAdvice = environment == null
        ? null
        : DryingAdvisor().advise(
            series: response.series,
            environment: environment!,
            startTime: plannedTime,
            now: now,
            fetchedAt: response.fetchedAt,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dryingAdvice != null) ...[
          DryingAdviceCard(
            advice: dryingAdvice,
            locationUtcOffset: response.series.locationUtcOffset,
            referenceTime: now,
          ),
        ] else
          _AssessmentCard(forecast: forecast, assessment: assessment),
        if (dryingAdvice == null && assessment.reasons.length > 1) ...[
          const SizedBox(height: 8),
          _AdditionalReasons(reasons: assessment.reasons.skip(1).toList()),
        ],
        if (dryingAdvice == null) ...[
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
        ],
        if (dryingAdvice == null) ...[
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
        const SizedBox(height: 24),
        SelectableText(
          'Weather data: Open-Meteo · CC BY 4.0\n'
          '取得データを表示用に加工しています',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (dryingAdvice != null) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            key: const Key('forecast-details-button'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => _ForecastDetailsPage(
                    forecast: forecast,
                    advice: dryingAdvice,
                    response: response,
                    environment: environment!,
                    onRefresh: onRefresh,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.description_outlined),
            label: const Text('予測の根拠を見る'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ForecastDetailsPage extends StatelessWidget {
  const _ForecastDetailsPage({
    required this.forecast,
    required this.advice,
    required this.response,
    required this.environment,
    required this.onRefresh,
  });

  final HourlyForecast? forecast;
  final DryingAdvice advice;
  final ForecastResponse response;
  final DryingEnvironment environment;
  final VoidCallback onRefresh;

  String _locationTime(DateTime value) {
    final offset = response.series.locationUtcOffset;
    if (offset == null) return '不明';
    final local = value.toUtc().add(offset);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }

  String _forecastPeriod() {
    final forecasts = response.series.forecasts;
    if (forecasts.isEmpty) return '予報期間不明';
    return '${_locationTime(forecasts.first.forecastTimeUtc)}〜${_locationTime(forecasts.last.forecastTimeUtc)}';
  }

  String _garmentLabel(String id, String fallback) => switch (id) {
    'thin' => '薄手',
    'normal' => '普通',
    'thick' => '厚手',
    _ => fallback,
  };

  void _showPredictionAbout(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'この予測について',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: '閉じる',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '乾燥時間予測の仕組みと注意点です。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                const _AboutNotice(
                  icon: Icons.description_outlined,
                  title: '予測の概要',
                  text: '気象予報と物干し環境から、乾燥時間と外干し可否を推定します。',
                ),
                const Divider(height: 32),
                const _AboutNotice(
                  icon: Icons.schedule_outlined,
                  title: '乾燥時間は目安です',
                  text: '素材・厚さ・脱水状態・干し方で前後します。',
                ),
                const Divider(height: 32),
                const _AboutNotice(
                  icon: Icons.thunderstorm_outlined,
                  title: '急な天気の変化に注意',
                  text: '急な雨や局地的な変化は、予報に反映されない場合があります。',
                ),
                const Divider(height: 32),
                const _AboutNotice(
                  icon: Icons.checkroom_outlined,
                  title: '衣類カテゴリについて',
                  text: '薄手・普通・厚手は、代表的な衣類を基準にした分類です。',
                ),
                const Divider(height: 32),
                const _AboutNotice(
                  icon: Icons.analytics_outlined,
                  title: '予測精度について',
                  text: '公開データと理論式をもとに予測しています。今後、実測データを用いた検証を進めます。',
                ),
                if (advice.detailMessages.any(
                  (message) =>
                      message.contains('屋根') || message.contains('吹き込み'),
                )) ...[
                  const SizedBox(height: 14),
                  for (final message in advice.detailMessages.where(
                    (message) =>
                        message.contains('屋根') || message.contains('吹き込み'),
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('・$message'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('予測の根拠')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '予測に使った情報と計算方法を確認できます。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _EvidenceSection(
                    title: '気象データ',
                    child: Column(
                      children: [
                        _EvidenceInfoRow(
                          label: '予報地点',
                          value: response.series.cityName,
                        ),
                        const _EvidenceInfoRow(
                          label: 'データ',
                          value: 'Open-Meteo',
                        ),
                        _EvidenceInfoRow(
                          label: '更新',
                          value: _locationTime(response.fetchedAt),
                        ),
                        _EvidenceInfoRow(
                          label: '予報期間',
                          value: _forecastPeriod(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 36),
                  _EvidenceSection(
                    key: const Key('forecast-evidence'),
                    title: '干し始めの予報',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (forecast == null)
                          const Text('予報値を表示できません。')
                        else ...[
                          _EvidenceWeatherMetrics(forecast: forecast!),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            children: [
                              Text(
                                '降水量 ${forecast!.precipitationText}',
                                key: const Key('evidence-precipitation'),
                              ),
                              Text(
                                '降水確率 ${forecast!.precipitationProbabilityText}',
                                key: const Key('metric-probability'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '使用予報時刻 ${_locationTime(forecast!.forecastTimeUtc)}',
                            key: const Key('evidence-forecast-time'),
                          ),
                        ],
                        if (advice.weatherRisks.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          WeatherRiskDetails(
                            risks: advice.weatherRisks,
                            locationUtcOffset:
                                response.series.locationUtcOffset,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 36),
                  _EvidenceSection(
                    title: '物干し環境',
                    child: Column(
                      children: [
                        _EvidenceInfoRow(
                          label: '干す場所',
                          value: environment.dryingPlace.label,
                        ),
                        _EvidenceInfoRow(
                          label: '雨・屋根よけ',
                          value: environment.roofProtection ? 'あり' : 'なし',
                        ),
                        _EvidenceInfoRow(
                          label: '風通し',
                          value: environment.windExposure.label,
                        ),
                        _EvidenceInfoRow(
                          label: '日当たり',
                          value: environment.sunExposurePattern.label,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 36),
                  const _EvidenceSection(
                    title: '乾燥時間について',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('気温・湿度・風・日射と物干し環境から、時間ごとの乾きやすさを計算しています。'),
                      ],
                    ),
                  ),
                  const Divider(height: 36),
                  _EvidenceSection(
                    title: '衣類カテゴリ',
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < advice.garments.length;
                          index++
                        ) ...[
                          if (index > 0) const Divider(height: 20),
                          Row(
                            children: [
                              const Icon(Icons.checkroom_outlined, size: 22),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 58,
                                child: Text(
                                  _garmentLabel(
                                    advice.garments[index].estimate.category.id,
                                    advice
                                        .garments[index]
                                        .estimate
                                        .category
                                        .label,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  advice
                                      .garments[index]
                                      .estimate
                                      .category
                                      .examples,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ForecastFooter(
                    fetchedAt: response.fetchedAt,
                    locationUtcOffset: response.series.locationUtcOffset,
                    onRefresh: () {
                      onRefresh();
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    key: const Key('prediction-about-button'),
                    onPressed: () => _showPredictionAbout(context),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('この予測について'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EvidenceWeatherMetrics extends StatelessWidget {
  const _EvidenceWeatherMetrics({required this.forecast});

  final HourlyForecast forecast;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final width = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: 14,
          children: [
            SizedBox(
              width: width,
              child: _EvidenceWeatherMetric(
                key: const Key('metric-temperature'),
                icon: Icons.thermostat_outlined,
                label: '気温',
                value: forecast.temperatureText,
              ),
            ),
            SizedBox(
              width: width,
              child: _EvidenceWeatherMetric(
                key: const Key('metric-humidity'),
                icon: Icons.water_drop_outlined,
                label: '湿度',
                value: forecast.humidityText,
              ),
            ),
            SizedBox(
              width: width,
              child: _EvidenceWeatherMetric(
                key: const Key('metric-wind'),
                icon: Icons.air,
                label: '風速',
                value: forecast.windSpeedText,
              ),
            ),
            SizedBox(
              key: const Key('evidence-solar'),
              width: width,
              child: _EvidenceWeatherMetric(
                icon: Icons.wb_sunny_outlined,
                label: '日射',
                value: forecast.solarRadiation == null
                    ? '不明'
                    : '${forecast.solarRadiation!.toStringAsFixed(0)} W/m²',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EvidenceWeatherMetric extends StatelessWidget {
  const _EvidenceWeatherMetric({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        icon,
        size: 22,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _EvidenceInfoRow extends StatelessWidget {
  const _EvidenceInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _AboutNotice extends StatelessWidget {
  const _AboutNotice({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(
          icon,
          size: 22,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ForecastFooter extends StatelessWidget {
  const _ForecastFooter({
    required this.fetchedAt,
    required this.locationUtcOffset,
    required this.onRefresh,
  });

  final DateTime fetchedAt;
  final Duration? locationUtcOffset;
  final VoidCallback onRefresh;

  String _locationTime(DateTime value) {
    if (locationUtcOffset == null) return '不明';
    final local = value.toUtc().add(locationUtcOffset!);
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '最終更新 ${_locationTime(fetchedAt)}',
            key: const Key('evidence-fetched-at'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('更新'),
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
