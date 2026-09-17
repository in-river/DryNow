# DryNow API比較・リアルタイム検証ツール 設計書

- **Version:** v1.1
- **作成日:** 2026-09-04
- **ベース:** `DRYNOW_API_COMPARISON_DESIGN_v1.0.md`
- **対象:** DryNow Phase 1-B
- **状態:** 2026-09-04時点の設計記録（現行との差分は以下を参照）

## 2026-09-17 更新：現行実装との差分

以下の第1～13節はv1.1作成時点の仕様・実装状況を保存したものです。
本文の「現在」「未実装」は当時の記載であり、現在の状態は次のとおりです。

- OpenWeather、Open-Meteo、Visual Crossing、Tomorrow.io、AMeDASのcollectorを実装済み。
- `compare.py`による気温・湿度・風速、鮮度、可用性・欠損率、雨判定の参考評価と共通標本比較を実装済み。
- 比較はDBを読み取り専用で開く。Pythonの関連テストは57件成功。
- 採用APIは**Open-Meteo**。Flutterの現在値と時間別予報の取得、純粋Dartの外干し判定v1、予報ベースのv8 UIを実装。
- 乾燥時間推定、干している期間全体の評価、`wind`地点を含む収集は未実装。

最新の比較結果と選定理由は[API比較結果](API_COMPARISON_RESULT.md)、
判定仕様は[外干し判定v1](DRYING_RULES_V1.md)、予報接続は[予報ベースの実用化](FORECAST_IMPLEMENTATION_V8.md)を正本として参照してください。

## 1. この文書の位置付け

v1.0で定めた「各APIがリアルタイムに返した値を自前保存し、後からAMeDASと比較する」方針を維持し、現在の実装範囲と30分自動収集の運用を反映する。

v1.0は当初設計の履歴として変更せず保持する。本書に未実装と記載した項目は、v1.0の将来計画に含まれていても完成扱いしない。

## 2. 目的

同一の比較対象時刻・地点について複数のCurrent APIレスポンスを保存し、気温・湿度・風速・降水・データ鮮度・API安定性を後から評価できるデータを蓄積する。

正規化値だけでなくraw JSONを保持し、フィールド解釈や比較指標を変更した場合にも再解析できるようにする。

## 3. 現在の実装範囲

### 実装・確認済み

- OpenWeather Current Weather API
- Open-Meteo Forecast API `current`
- 5都市の`primary`地点を対象とする収集
- 1回につき5都市 × 5ソース = 25レコード
- SQLite `observations`テーブルへの正規化値・raw JSON保存
- HTTPエラー、ネットワークエラー、JSONデコードエラーの記録
- Windows Task Schedulerによる30分間隔の自動実行
- stdout・stderrのログ保存
- API collector・AMeDASの正規化テスト
- `target_time`の30分丸めテスト
- 49 tests / OK
- 16:35の自動実行で`target_time=16:30`の25レコード保存

### 未実装

- Visual Crossing collector
- Tomorrow.io collector
- AMeDAS collectorと同時刻データの保存
- `wind`地点を含む8座標でのCurrent API収集
- API値とAMeDAS値の結合・精度分析
- Flutter本体へのAPI比較機能の統合
- 外干し判定と乾燥時間推定

## 4. 現在の比較対象地点

`locations.py`に定義された次の5都市について、`point_role == "primary"`の地点だけを使用する。

| city | station_id | latitude | longitude |
|---|---:|---:|---:|
| kumagaya | 43056 | 36.150000 | 139.380000 |
| tokyo | 44132 | 35.691667 | 139.750000 |
| shizuoka | 50331 | 34.975000 | 138.403333 |
| osaka | 62078 | 34.681667 | 135.518333 |
| matsuyama | 73166 | 33.843333 | 132.776667 |

東京・大阪・松山の`wind`地点は定義済みだが、現在の自動収集対象には含めない。

## 5. 現在の比較対象API

| source | endpoint種別 | 状態 | 認証 |
|---|---|---|---|
| openweather | Current Weather API | 実装済み・自動収集中 | APIキー必須 |
| open_meteo | Forecast API `current` | 実装済み・自動収集中 | APIキー不要 |
| visual_crossing | Timeline Current Conditions | 未実装 | APIキー必須予定 |
| tomorrow_io | Realtime Weather API | 未実装 | APIキー必須予定 |
| amedas | 気象庁AMeDAS全国マップ | 実装済み・自動収集中 | 不要 |

## 6. 1回の収集サイクル

1. 実行開始時刻から`target_time`を1回だけ生成する。
2. JSTへ変換し、00分または30分の境界へ切り捨てる。
3. 5都市の`primary`地点を読み込む。
4. AMeDAS全国マップを1回取得し、各都市の観測所を正規化する。
5. 各都市についてOpenWeather、Open-Meteo、Visual Crossing、Tomorrow.ioを逐次実行する。
6. collectorが返した正規化値とraw JSONを`observations`へ保存する。
7. 取得・保存失敗があっても、残りの都市・APIを継続する。
8. 各レコードの取得値、成功状態、保存状態を標準出力へ記録する。

通常は1サイクル25レコードとなる。APIキー欠損、予期しない取得例外、SQLite一意制約違反などがある場合は25件未満になる可能性がある。

## 7. タイムスタンプ設計

| Field | 意味 |
|---|---|
| `target_time` | 比較用の共通時刻。JSTの00分・30分境界 |
| `fetched_at` | collectorがHTTPレスポンスを受け取った時刻 |
| `source_time` | APIレスポンス自身が示すデータ時刻 |

例:

- 17:05実行 → `target_time=17:00`
- 17:35実行 → `target_time=17:30`
- 18:05実行 → `target_time=18:00`

同一実行内では、全都市・全APIへ同じ`datetime`を渡す。`fetched_at`と`source_time`はAPIごとに異なってよい。

## 8. 保存モデル

SQLiteの`observations`を使用し、1 HTTPレスポンスを1行として扱う。主要な保存項目は次のとおり。

- 比較時刻: `target_time`、`fetched_at`、`source_time`
- 識別: `source`、`city`、`point_role`、座標
- 気象値: 気温、湿度、風速、降水量、降水時間窓、降水検知
- 運用品質: HTTP status、応答時間、成功状態、エラー種別
- 再解析情報: `endpoint_sanitized`、`raw_json`、collector version

一意制約は次の組み合わせに設定する。

```text
source + city + point_role + target_time
```

同じ時刻枠を再実行しても既存行は上書きしない。重複した行の保存は失敗し、その後の地点・APIの処理は継続する。

## 9. 正規化と降水

- 気温: ℃
- 相対湿度: %RH
- 風速: m/s
- 降水量: APIの意味を保持し、値・単位・時間窓を分離
- 欠損: `NULL`
- 観測またはAPI応答の`0`: 0のまま保持

OpenWeatherでは雨・雪の`1h`を扱い、時間窓は60分とする。Open-Meteoでは`current.precipitation`をmmで保持し、`current.interval`の秒数から`precipitation_window_min`を算出する。API間の降水量を無理に同じ時間幅へ換算しない。

## 10. 自動実行

Windows Task Schedulerから`run_current_collection.ps1`を呼び出す。

- 実行時刻: 毎時05分・35分
- 反復間隔: 30分
- 多重起動: `IgnoreNew`
- 実行ユーザー: 現在ログオン中のInteractiveユーザー
- ネットワーク: 利用可能な場合に実行
- 実行可能になった後の開始: 有効
- スリープ解除: `-WakeToRun`指定時のみ有効
- 定義確認: `-ValidateOnly`指定時は登録・更新しない

登録スクリプトはPython実行ファイルとプロジェクトルートを絶対パスへ正規化する。同名タスクの登録は`-Force`で更新する。

## 11. ログ

成功時の`raw_json`にはAPIの元レスポンス全文を保存する。HTTPエラー、通信エラー、JSONデコードエラーでは、現在のcollectorが生成したエラー情報のJSONを保存するため、APIのエラーレスポンス本文または不正な原文そのものとは限らない。

実行用PowerShellスクリプトは、作業ディレクトリに依存せず`collect_current.py`を起動し、実行ごとに次のログを`tools/api_comparison/logs/`へ保存する。

- `collect_current_<timestamp>_stdout.log`
- `collect_current_<timestamp>_stderr.log`

ログとSQLite DBはGit管理対象外とする。APIキーを引数・ログ・sanitized endpointへ出さない。

## 12. テスト・動作確認

テストは`tools/api_comparison/tests/`に置く。

- OpenWeather降水正規化: 8件
- Open-Meteo正規化: 6件
- `target_time`30分丸め: 4件
- AMeDAS時刻フォールバックを含む合計: 49 tests / OK

実運用確認として、Task Schedulerの16:35実行で5都市 × 5ソースを取得し、共通の`target_time=16:30`として25レコードがSQLiteへ保存されたことを確認済みである。

## 13. 次の実装候補

1. 継続収集したデータの欠損・鮮度・成功率確認
2. Visual Crossing collector
3. Tomorrow.io collector
4. `wind`地点を含めた収集範囲の検討
5. API値とAMeDAS値の時刻結合・評価

実装順序はAPI利用条件や収集データの状況に応じて見直す。未実装項目を完成扱いしない。

---

**設計上の最重要原則:**  
**raw = 証拠データ / normalized = 比較用データ**
