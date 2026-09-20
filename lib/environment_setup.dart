import 'package:flutter/material.dart';

import 'environment_store.dart';
import 'models/drying_environment.dart';
import 'models/weather_location.dart';

typedef EnvironmentSaver = Future<bool> Function(DryingEnvironment value);

class EnvironmentSetup extends StatefulWidget {
  const EnvironmentSetup({
    super.key,
    required this.store,
    required this.onSaved,
    this.initialEnvironment,
    this.onCancel,
  });
  final EnvironmentStore store;
  final ValueChanged<DryingEnvironment> onSaved;
  final DryingEnvironment? initialEnvironment;
  final VoidCallback? onCancel;

  @override
  State<EnvironmentSetup> createState() => _EnvironmentSetupState();
}

class _EnvironmentSetupState extends State<EnvironmentSetup> {
  var _step = 0;
  bool? _roof;
  DryingPlace? _place;
  WindExposure? _wind;
  SunExposurePattern? _sun;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEnvironment;
    _roof = initial?.roofProtection;
    _place = initial?.dryingPlace;
    _wind = initial?.windExposure;
    _sun = initial?.sunExposurePattern;
  }

  Future<void> _next() async {
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    final environment = DryingEnvironment(
      roofProtection: _roof!,
      dryingPlace: _place!,
      windExposure: _wind!,
      sunExposurePattern: _sun!,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.save(environment);
      if (mounted) widget.onSaved(environment);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '設定を保存できませんでした。もう一度お試しください。';
        });
      }
    }
  }

  Widget _choices<T>(
    List<T> choices,
    T? selected,
    String Function(T) label,
    ValueChanged<T> change,
  ) => Column(
    children: [
      for (final choice in choices)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _saving ? null : () => setState(() => change(choice)),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(16),
                backgroundColor: choice == selected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    choice == selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label(choice))),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final enabled = switch (_step) {
      0 => _roof != null,
      1 => _place != null,
      2 => _wind != null,
      _ => _sun != null,
    };
    final question = switch (_step) {
      0 => '洗濯物を干す場所に屋根や雨よけはありますか？',
      1 => 'どこに洗濯物を干しますか？',
      2 => '干す場所の風通しはどうですか？',
      _ => '日当たりはどうですか？',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('干す環境の設定'),
        automaticallyImplyLeading: false,
        actions: [
          if (widget.onCancel != null)
            TextButton(
              onPressed: _saving ? null : widget.onCancel,
              child: const Text('キャンセル'),
            ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Step ${_step + 1} / 4', key: const Key('setup-step')),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: (_step + 1) / 4),
                  const SizedBox(height: 24),
                  Text(
                    question,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  if (_step == 0) ...[
                    _choices(
                      [true, false],
                      _roof,
                      (v) => v ? 'あり' : 'なし',
                      (v) => _roof = v,
                    ),
                    const Text('屋根があっても、横からの雨や吹き込みには注意が必要です。'),
                  ],
                  if (_step == 1)
                    _choices(DryingPlace.values, _place, (v) => v.label, (v) {
                      if (_place != v) _wind = v.suggestedWind;
                      _place = v;
                    }),
                  if (_step == 2) ...[
                    Text(
                      '${_place!.label}なら、風通しは「${_place!.suggestedWind.label}」くらいかもしれません。実際の環境に合わせて変更できます。',
                    ),
                    const SizedBox(height: 12),
                    _choices(
                      WindExposure.values,
                      _wind,
                      (v) => v.label,
                      (v) => _wind = v,
                    ),
                  ],
                  if (_step == 3)
                    _choices(
                      SunExposurePattern.values,
                      _sun,
                      (v) => v.label,
                      (v) => _sun = v,
                    ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (_step > 0)
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _step--),
                          child: const Text('戻る'),
                        ),
                      FilledButton(
                        onPressed: enabled && !_saving ? _next : null,
                        child: Text(
                          _saving
                              ? '保存中…'
                              : _step == 3
                              ? '保存してはじめる'
                              : '次へ',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('設定は端末に保存され、あとから変更できます。'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EnvironmentGate extends StatefulWidget {
  const EnvironmentGate({
    super.key,
    required this.store,
    required this.builder,
  });
  final EnvironmentStore store;
  final Widget Function(DryingEnvironment, EnvironmentSaver) builder;
  @override
  State<EnvironmentGate> createState() => _EnvironmentGateState();
}

class _EnvironmentGateState extends State<EnvironmentGate> {
  DryingEnvironment? _environment;
  bool _loading = true;
  bool _loadFailed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _save(DryingEnvironment value) async {
    try {
      await widget.store.save(value);
      if (!mounted) return false;
      setState(() => _environment = value);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final value = await widget.store.load();
      if (mounted) {
        setState(() {
          _environment = value;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('DryNow')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('保存した環境設定を読み込めませんでした。'),
                TextButton(onPressed: _load, child: const Text('読み込みを再試行')),
                TextButton(
                  onPressed: () => setState(() => _loadFailed = false),
                  child: const Text('環境を再設定'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_environment == null) {
      return EnvironmentSetup(
        store: widget.store,
        onSaved: (value) => setState(() => _environment = value),
      );
    }
    return widget.builder(_environment!, _save);
  }
}

class EnvironmentSettingsPage extends StatefulWidget {
  const EnvironmentSettingsPage({
    super.key,
    required this.initialEnvironment,
    required this.initialLocation,
    required this.onSelectLocation,
    required this.onSaveEnvironment,
  });

  final DryingEnvironment initialEnvironment;
  final WeatherLocation initialLocation;
  final Future<WeatherLocation?> Function() onSelectLocation;
  final EnvironmentSaver onSaveEnvironment;

  @override
  State<EnvironmentSettingsPage> createState() =>
      _EnvironmentSettingsPageState();
}

class _EnvironmentSettingsPageState extends State<EnvironmentSettingsPage> {
  late DryingEnvironment _environment;
  late WeatherLocation _location;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _environment = widget.initialEnvironment;
    _location = widget.initialLocation;
  }

  Future<void> _selectLocation() async {
    final location = await widget.onSelectLocation();
    if (location != null && mounted) setState(() => _location = location);
  }

  Future<void> _updateEnvironment(DryingEnvironment value) async {
    if (_saving || value == _environment) return;
    setState(() => _saving = true);
    final saved = await widget.onSaveEnvironment(value);
    if (!mounted) return;
    setState(() {
      if (saved) _environment = value;
      _saving = false;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(saved ? '設定を更新しました' : '設定を保存できませんでした'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<T?> _showChoices<T>({
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required IconData Function(T) icon,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final value in values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    value == selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: value == selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  title: Row(
                    children: [
                      Icon(icon(value), size: 24),
                      const SizedBox(width: 12),
                      Expanded(child: Text(label(value))),
                    ],
                  ),
                  onTap: () => Navigator.of(context).pop(value),
                ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editPlace() async {
    final value = await _showChoices<DryingPlace>(
      title: '干す場所',
      values: DryingPlace.values,
      selected: _environment.dryingPlace,
      label: (value) => value.label,
      icon: (value) => switch (value) {
        DryingPlace.openBalcony ||
        DryingPlace.enclosedBalcony => Icons.balcony_outlined,
        DryingPlace.garden => Icons.park_outlined,
        DryingPlace.underEaves => Icons.roofing_outlined,
      },
    );
    if (value == null) return;
    await _updateEnvironment(
      DryingEnvironment(
        roofProtection: _environment.roofProtection,
        dryingPlace: value,
        windExposure: _environment.windExposure,
        sunExposurePattern: _environment.sunExposurePattern,
      ),
    );
  }

  Future<void> _editRoof() async {
    final value = await _showChoices<bool>(
      title: '雨・屋根よけ',
      values: const [true, false],
      selected: _environment.roofProtection,
      label: (value) => value ? 'あり' : 'なし',
      icon: (value) =>
          value ? Icons.umbrella_outlined : Icons.wb_sunny_outlined,
    );
    if (value == null) return;
    await _updateEnvironment(
      DryingEnvironment(
        roofProtection: value,
        dryingPlace: _environment.dryingPlace,
        windExposure: _environment.windExposure,
        sunExposurePattern: _environment.sunExposurePattern,
      ),
    );
  }

  Future<void> _editWind() async {
    final value = await _showChoices<WindExposure>(
      title: '風通し',
      values: WindExposure.values,
      selected: _environment.windExposure,
      label: (value) => value.label,
      icon: (value) => switch (value) {
        WindExposure.good => Icons.air,
        WindExposure.normal => Icons.air_outlined,
        WindExposure.poor => Icons.horizontal_rule,
      },
    );
    if (value == null) return;
    await _updateEnvironment(
      DryingEnvironment(
        roofProtection: _environment.roofProtection,
        dryingPlace: _environment.dryingPlace,
        windExposure: value,
        sunExposurePattern: _environment.sunExposurePattern,
      ),
    );
  }

  Future<void> _editSun() async {
    final value = await _showChoices<SunExposurePattern>(
      title: '日当たり',
      values: SunExposurePattern.values,
      selected: _environment.sunExposurePattern,
      label: (value) => value.label,
      icon: (value) => switch (value) {
        SunExposurePattern.allDay => Icons.wb_sunny_outlined,
        SunExposurePattern.morningOnly ||
        SunExposurePattern.afternoonOnly => Icons.wb_twilight_outlined,
        SunExposurePattern.shaded => Icons.cloud_outlined,
      },
    );
    if (value == null) return;
    await _updateEnvironment(
      DryingEnvironment(
        roofProtection: _environment.roofProtection,
        dryingPlace: _environment.dryingPlace,
        windExposure: _environment.windExposure,
        sunExposurePattern: value,
      ),
    );
  }

  void _showInfo(String title, String body) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(body),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
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
                  const _SettingsSectionTitle('予測に使う場所'),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      key: const Key('settings-location'),
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(_location.name),
                      subtitle: _location.details.isEmpty
                          ? null
                          : Text(_location.details),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _selectLocation,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SettingsSectionTitle('物干し環境'),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _SettingsTile(
                          tileKey: const Key('settings-place'),
                          icon: Icons.home_outlined,
                          title: '干す場所',
                          value: _environment.dryingPlace.label,
                          onTap: _saving ? null : _editPlace,
                        ),
                        const Divider(height: 1),
                        _SettingsTile(
                          tileKey: const Key('settings-roof'),
                          icon: Icons.umbrella_outlined,
                          title: '雨・屋根よけ',
                          value: _environment.roofProtection ? 'あり' : 'なし',
                          onTap: _saving ? null : _editRoof,
                        ),
                        const Divider(height: 1),
                        _SettingsTile(
                          tileKey: const Key('settings-wind'),
                          icon: Icons.air,
                          title: '風通し',
                          value: _environment.windExposure.label,
                          onTap: _saving ? null : _editWind,
                        ),
                        const Divider(height: 1),
                        _SettingsTile(
                          tileKey: const Key('settings-sun'),
                          icon: Icons.wb_sunny_outlined,
                          title: '日当たり',
                          value: _environment.sunExposurePattern.label,
                          onTap: _saving ? null : _editSun,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _SettingsSectionTitle('DryNowについて'),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _SettingsTile(
                          icon: Icons.menu_book_outlined,
                          title: '予測の仕組み',
                          onTap: () => _showInfo(
                            '予測の仕組み',
                            '気温・湿度・風速・日射と物干し環境から、衣類ごとの乾燥時間と外干し可否を推定します。',
                          ),
                        ),
                        const Divider(height: 1),
                        _SettingsTile(
                          icon: Icons.storage_outlined,
                          title: '使用している気象データ',
                          onTap: () => _showInfo(
                            '使用している気象データ',
                            'Open-Meteoの時間別予報を、表示と乾燥予測に使用しています。',
                          ),
                        ),
                        const Divider(height: 1),
                        _SettingsTile(
                          icon: Icons.help_outline,
                          title: 'アプリについて',
                          onTap: () => _showInfo(
                            'DryNowについて',
                            'DryNowは、洗濯物の外干し可否と乾燥時間の目安を確認するためのアプリです。',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_saving) ...[
                    const SizedBox(height: 18),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    '変更するとすぐに予測へ反映されます',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    this.tileKey,
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
  });

  final Key? tileKey;
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: tileKey,
    leading: Icon(icon),
    title: Text(title),
    subtitle: value == null ? null : Text(value!),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
