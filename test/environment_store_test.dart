import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather_app/environment_store.dart';
import 'package:weather_app/models/drying_environment.dart';

import 'drying_estimator_test.dart' show environment;

class MemoryPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};
  final _failWrite = [false];
  bool get failWrite => _failWrite.single;
  set failWrite(bool value) => _failWrite[0] = value;
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    if (failWrite) throw Exception('保存失敗');
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MemoryPreferences preferences;
  late PreferencesEnvironmentStore store;
  setUp(() {
    preferences = MemoryPreferences();
    store = PreferencesEnvironmentStore(preferences: preferences);
  });
  test('初回は未設定', () async => expect(await store.load(), isNull));
  test('4項目を保存して新しいストアで復元できる', () async {
    await store.save(environment);
    final restored = await PreferencesEnvironmentStore(
      preferences: preferences,
    ).load();
    expect(restored!.toJson(), environment.toJson());
  });
  test('更新は対象キーだけを書き換える', () async {
    preferences.values['unrelated'] = '保持';
    await store.save(environment);
    const changed = DryingEnvironment(
      roofProtection: true,
      dryingPlace: DryingPlace.underEaves,
      windExposure: WindExposure.normal,
      sunExposurePattern: SunExposurePattern.afternoonOnly,
    );
    await store.save(changed);
    expect((await store.load())!.toJson(), changed.toJson());
    expect(preferences.values['unrelated'], '保持');
  });
  for (final value in [
    'broken',
    '{}',
    '{"version":2}',
    '{"version":1,"roofProtection":"true"}',
    '{"version":1,"roofProtection":true,"dryingPlace":"removed"}',
  ]) {
    test('破損設定$valueは初回と区別する', () async {
      preferences.values[PreferencesEnvironmentStore.storageKey] = value;
      await expectLater(store.load(), throwsFormatException);
      expect(preferences.values[PreferencesEnvironmentStore.storageKey], value);
    });
  }
  test('書き込み失敗を成功扱いしない', () async {
    await store.save(environment);
    preferences.failWrite = true;
    await expectLater(store.save(environment), throwsException);
    expect((await store.load())!.toJson(), environment.toJson());
  });
}
