import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/environment_store.dart';
import 'package:weather_app/main.dart';
import 'package:weather_app/models/drying_environment.dart';
import 'package:weather_app/models/weather.dart';
import 'package:weather_app/weather_api.dart';

import 'drying_estimator_test.dart' show environment, sample;
import 'weather_page_test.dart' show FakeWeatherApi;

class MemoryEnvironmentStore implements EnvironmentStore {
  MemoryEnvironmentStore([this.value]);
  DryingEnvironment? value;
  bool failLoad = false;
  bool failSave = false;
  int writes = 0;
  @override
  Future<DryingEnvironment?> load() async {
    if (failLoad) throw Exception('読込失敗');
    return value;
  }

  @override
  Future<void> save(DryingEnvironment environment) async {
    if (failSave) throw Exception('保存失敗');
    value = environment;
    writes++;
  }
}

void main() {
  final now = DateTime.utc(2026, 9, 18, 1);
  late FakeWeatherApi api;
  setUp(() {
    api = FakeWeatherApi(
      (lat, lon, city) async => ForecastResponse(
        series: ForecastSeries(
          cityName: city,
          locationUtcOffset: const Duration(hours: 9),
          timezone: 'Asia/Tokyo',
          forecasts: List.generate(
            30,
            (i) => sample(now.add(Duration(hours: i))),
          ),
        ),
        fetchedAt: now,
        rawJson: '{}',
      ),
    );
  });
  tearDown(() => api.close());
  Future<void> pump(
    WidgetTester tester,
    MemoryEnvironmentStore store, {
    DateTime Function()? clock,
  }) async {
    await tester.pumpWidget(
      WeatherApp(environmentStore: store, api: api, now: clock ?? () => now),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label).last;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> setup(WidgetTester tester) async {
    await tap(tester, 'あり');
    await tap(tester, '次へ');
    await tap(tester, '壁に囲まれたベランダ');
    await tap(tester, '次へ');
    expect(find.textContaining('「普通」くらい'), findsOneWidget);
    await tap(tester, '良い');
    await tap(tester, '次へ');
    await tap(tester, '午前のみ日が当たる');
    await tap(tester, '保存してはじめる');
  }

  testWidgets('初回4ステップと候補修正、保存後に3カテゴリを同時表示', (tester) async {
    final store = MemoryEnvironmentStore();
    await pump(tester, store);
    expect(find.text('Step 1 / 4'), findsOneWidget);
    expect(find.byKey(const Key('drying-advice-card')), findsNothing);
    await setup(tester);
    expect(store.value!.roofProtection, isTrue);
    expect(store.value!.dryingPlace, DryingPlace.enclosedBalcony);
    expect(store.value!.windExposure, WindExposure.good);
    expect(store.value!.sunExposurePattern, SunExposurePattern.morningOnly);
    expect(store.writes, 1);
    for (final id in ['thin', 'normal', 'thick']) {
      expect(find.byKey(Key('garment-$id')), findsOneWidget);
    }
    final garmentPositions = [
      'thin',
      'normal',
      'thick',
    ].map((id) => tester.getTopLeft(find.byKey(Key('garment-$id')))).toList();
    expect(garmentPositions[0].dy, garmentPositions[1].dy);
    expect(garmentPositions[1].dy, garmentPositions[2].dy);
    expect(garmentPositions[0].dx, lessThan(garmentPositions[1].dx));
    expect(garmentPositions[1].dx, lessThan(garmentPositions[2].dx));
    expect(find.byKey(const Key('drying-advice-title')), findsOneWidget);
    expect(find.byKey(const Key('prediction-about')), findsNothing);
    expect(find.byKey(const Key('forecast-details-button')), findsOneWidget);
    expect(find.textContaining('暫定モデル'), findsNothing);
    expect(
      tester.widget<ChoiceChip>(find.byKey(const Key('offset-0'))).selected,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('保存済み設定は初回フローを省略し、設定画面で更新できる', (tester) async {
    final store = MemoryEnvironmentStore(environment);
    await pump(tester, store);
    expect(find.text('Step 1 / 4'), findsNothing);
    await tester.tap(find.byKey(const Key('environment-settings')));
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('予測に使う場所'), findsOneWidget);
    expect(find.text('物干し環境'), findsOneWidget);
    expect(find.text('春日部市'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-roof')));
    await tester.pumpAndSettle();
    await tap(tester, 'あり');
    expect(store.writes, 1);
    expect(store.value!.roofProtection, isTrue);
    expect(find.text('設定を更新しました'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drying-advice-card')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, store);
    expect(find.text('Step 1 / 4'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('選択シートを閉じた場合は既存設定を保持する', (tester) async {
    final store = MemoryEnvironmentStore(environment);
    await pump(tester, store);
    await tester.tap(find.byKey(const Key('environment-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-roof')));
    await tester.pumpAndSettle();
    await tap(tester, '閉じる');
    expect(store.value, environment);
    expect(store.writes, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drying-advice-card')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('430x900で設定一覧と選択シートがoverflowしない', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pump(tester, MemoryEnvironmentStore(environment));
    await tester.tap(find.byKey(const Key('environment-settings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('予測に使う場所'), findsOneWidget);
    expect(find.text('DryNowについて'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-place')));
    await tester.pumpAndSettle();
    expect(find.text('閉じる'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('保存失敗は設定画面に残り再試行できる', (tester) async {
    final store = MemoryEnvironmentStore()..failSave = true;
    await pump(tester, store);
    await setup(tester);
    expect(find.textContaining('設定を保存できませんでした'), findsOneWidget);
    expect(store.value, isNull);
    store.failSave = false;
    await tap(tester, '保存してはじめる');
    expect(find.byKey(const Key('drying-advice-card')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('読込失敗を初回と区別し再試行できる', (tester) async {
    final store = MemoryEnvironmentStore(environment)..failLoad = true;
    await pump(tester, store);
    expect(find.textContaining('読み込めませんでした'), findsOneWidget);
    store.failLoad = false;
    await tap(tester, '読み込みを再試行');
    expect(find.byKey(const Key('drying-advice-card')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('今からは時計更新ごとに再計算し過去開始にならない', (tester) async {
    var clock = now;
    await pump(tester, MemoryEnvironmentStore(environment), clock: () => clock);
    clock = now.add(const Duration(minutes: 10));
    await tester.pump(const Duration(minutes: 1));
    final title = tester.widget<Text>(
      find.byKey(const Key('drying-advice-title')),
    );
    expect(title.data, '外干しできます');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('未来の開始チップで乾燥完了予測も更新する', (tester) async {
    await pump(tester, MemoryEnvironmentStore(environment));
    final before = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('garment-thin')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .toList();
    await tester.tap(find.byKey(const Key('offset-3')));
    await tester.pumpAndSettle();
    final after = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('garment-thin')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .toList();
    expect(after, isNot(before));
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [
    const Size(320, 700),
    const Size(430, 900),
    const Size(1400, 900),
  ]) {
    testWidgets('初回設定と予測は幅${size.width}でoverflowせず最大幅を維持', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pump(tester, MemoryEnvironmentStore());
      await setup(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('drying-advice-card'))).width,
        lessThanOrEqualTo(800),
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('320pxで文字を拡大してもアドバイスがoverflowしない', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await pump(tester, MemoryEnvironmentStore(environment));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
