# DryNow API比較・リアルタイム検証ツール 設計書

> [!NOTE]
> この文書は2026-09-01時点の気象API比較ツールの初期設計を記録した資料です。
> 後続の設計記録は [DRYNOW_API_COMPARISON_DESIGN_v1.1.md](DRYNOW_API_COMPARISON_DESIGN_v1.1.md)、現在のAPI選定結果は [API_COMPARISON_RESULT.md](API_COMPARISON_RESULT.md) を参照してください。
> 現在のDryNow全体の実装状況は [README.md](../README.md) と [V9_VALIDATION.md](V9_VALIDATION.md) を参照してください。

- **Version:** v1.0
- **作成日:** 2026-09-01
- **対象:** DryNow Phase 1-B
- **状態:** 実装開始用ベースライン設計

## 1. 目的

DryNowで利用する気象APIを、知名度やHistorical APIの見かけ上の精度ではなく、**実際にユーザーへ返されるリアルタイム値**を基準に比較する。

同一時刻・同一地点で4社のCurrent/Realtime APIレスポンスを取得・保存し、同時刻の気象庁AMeDAS公式観測値を評価基準として照合する。収集データを蓄積した後、気温・湿度・風速・降水判定・API安定性・データ鮮度等を比較し、DryNowに最も適したAPIを選定する。

> 注: AMeDASは本設計上の「評価基準（Ground Truthとして扱う参照観測値）」であり、任意地点の絶対的な真値ではない。APIは格子・補間・モデル等で地点値を推定するため、空間代表性の差は残る。

## 2. 背景と方針変更

当初は各APIのHistoricalデータを使って比較する案を検討した。しかし、Historicalデータには観測補間・再解析・過去モデル出力・独自アーカイブ等が混在し、リアルタイム時に返された値と一致しない場合がある。このため、Historicalデータのみで「DryNowに最適なAPI」を決定することは避ける。

Phase 1-Bでは、**各社のリアルタイムレスポンスを自前で保存し、その後AMeDASと照合する方式**を採用する。raw JSONも保持し、後から正規化ルールや比較指標を変更しても再解析できるようにする。

## 3. Phase 1-B のスコープ

### 実施すること
- 4社APIのCurrent/Realtime値を1時間ごとに取得
- 5都市・8座標で取得
- 同一対象時刻のAMeDAS公式観測値を取得
- raw JSONと正規化値をSQLiteへ保存
- HTTPエラー、欠損、レスポンス時間、データ時刻も保存
- 後続分析に必要な形式を固定

### 今回は実施しないこと
- 予報精度の比較
- DryNowの乾燥時間推定アルゴリズム完成
- Flutter UIへの4社API同時接続
- Historicalデータを用いた最終API決定
- 総合点の重み付け確定

## 4. 比較対象

| Source | 使用用途 | 主な特徴 | Phase 1-B |
|---|---|---|---|
| OpenWeather | Current Weather Data | 当時のDryNow基準。複数の観測・モデル等を処理したCurrent値 | 採用 |
| Open-Meteo | Forecast API `current` | 気象モデルベース。Currentは15分モデルデータを基礎とする | 採用 |
| Visual Crossing | Timeline API `currentConditions` | Current Conditions。観測の新しさと距離を考慮したデータ源選択 | 採用 |
| Tomorrow.io | Realtime Weather API | Realtime endpoint。Freeでcore weather parameters利用可 | 採用 |
| 気象庁 AMeDAS | 評価基準 | 現地観測の公式値 | 基準 |

## 5. 当時のAPI呼び出し量の見積り

1時間あたり、1社につき8座標を取得する。

- 8 requests/hour/API
- 192 requests/day/API

Tomorrow.io Freeの25 requests/hour、500 requests/dayの範囲内。Open-Meteo Freeは10,000 calls/day、Visual Crossing Freeは1,000 records/dayの範囲内で運用可能。OpenWeatherも本検証規模では十分小さい。

## 6. AMeDAS基準地点

| 都市 | 観測所番号 | role | 緯度 | 経度 | 標高 | 用途 |
|---|---:|---|---:|---:|---:|---|
| 熊谷 | 43056 | primary | 36.150000 | 139.380000 | 30m | 気温・湿度・降水・風 |
| 東京 | 44132 | primary | 35.691667 | 139.750000 | 25m | 気温・湿度・降水 |
| 東京 | 44132 | wind | 35.691667 | 139.751667 | 20m | 風 |
| 静岡 | 50331 | primary | 34.975000 | 138.403333 | 14m | 気温・湿度・降水・風 |
| 大阪 | 62078 | primary | 34.681667 | 135.518333 | 23m | 気温・湿度・降水 |
| 大阪 | 62078 | wind | 34.675000 | 135.546667 | 1m | 風 |
| 松山 | 73166 | primary | 33.843333 | 132.776667 | 32m | 気温・湿度・降水 |
| 松山 | 73166 | wind | 33.835000 | 132.793333 | 41m | 風 |

東京・大阪・松山は気温/雨等と風の観測位置が分かれているため、API側も風評価時には`wind`座標で別途取得する。熊谷・静岡は同一観測地点を使用する。

## 7. 比較指標

### 7.1 精度

**気温**
- 主指標: MAE (Mean Absolute Error)
- 補助: Bias、最大絶対誤差、都市別MAE

**相対湿度**
- 主指標: MAE
- 補助: Bias、最大絶対誤差、都市別MAE

**風速**
- 主指標: MAE
- 補助: Bias、都市別MAE
- 注意: AMeDASの平均風速とAPIモデル/推定風速は時間平均や代表性が完全一致しないため、気温より解釈に注意する。

**降水**
- 主指標: 雨の見逃し率
- 補助: F1、誤検知率、Precision/Recall
- 降水量そのものはAPIごとに時間窓が異なるため、Phase 1-Bでは無理に同一数値へ変換しない。

### 7.2 実用性
- API成功率
- 変数ごとの欠損率
- データ鮮度 (`fetched_at - source_time`)
- HTTPレスポンス時間
- エラー種別・HTTP status

### 7.3 最終選定で別途見る項目
- 料金・無料枠
- 商用利用条件
- 予報時間
- 日射量・雲量等、DryNowの乾燥推定に有用な変数
- API仕様の安定性・ドキュメント品質

## 8. システム構成

```text
[Windows Task Scheduler / 手動実行]
             |
             v
      collect_current.py
             |
     +-------+-------+----------------+----------------+
     |               |                |                |
 OpenWeather     Open-Meteo     Visual Crossing   Tomorrow.io
     |               |                |                |
     +---------------+----------------+----------------+
                     |
            normalize + raw保持
                     |
                     v
             SQLite database
                     ^
                     |
            collect_amedas.py
                     |
                     v
              気象庁 AMeDAS
```

4社APIの取得とAMeDAS取得は処理を分離する。AMeDAS側の公開タイミングに遅れがあっても、`target_time`を共通キーにして後から結合できる。

## 9. ディレクトリ構成

```text
DryNow/
├─ lib/                       # Flutter本体
├─ docs/
└─ tools/
   └─ api_comparison/
      ├─ collectors/
      │  ├─ openweather.py
      │  ├─ open_meteo.py
      │  ├─ visual_crossing.py
      │  ├─ tomorrow_io.py
      │  └─ amedas.py
      ├─ locations.py
      ├─ database.py
      ├─ collect_current.py
      ├─ collect_amedas.py
      ├─ requirements.txt
      ├─ .env.example
      ├─ README.md
      ├─ data/
      │  └─ weather_validation.db
      └─ logs/
         └─ collector.log
```

AMeDAS取得部は`collectors/amedas.py`へ隔離する。気象庁WebのJSON取得経路は一般向けに仕様保証されたOpenWeather型APIではないため、URLや構造が変わっても他部分へ影響させない。

## 10. 1回の収集サイクル

### Current API
1. `target_time`をJSTの時刻境界（例: 15:00）に固定
2. 5都市・8座標を読み込む
3. 4社のCurrent/Realtime endpointへアクセス
4. `fetched_at`、`source_time`、HTTP情報を取得
5. raw JSONを保持
6. 共通項目へ正規化
7. SQLiteへ保存
8. 失敗時もエラーレコードを保存

### AMeDAS
1. 同じ`target_time`の公式観測値が公開されたことを確認
2. 5地点の観測値を取得
3. 東京・大阪・松山は風観測位置を区別
4. 品質情報を保存
5. SQLiteへ保存
6. 対象時刻の値が未公開ならリトライ可能な状態で終了

## 11. タイムスタンプ設計

すべてISO 8601・タイムゾーン付き文字列で保存する。

| Field | 意味 | 例 |
|---|---|---|
| target_time | 比較対象時刻 | `2026-09-01T15:00:00+09:00` |
| fetched_at | HTTP取得完了時刻 | `2026-09-01T15:00:03+09:00` |
| source_time | API/観測値自身が示す時刻 | `2026-09-01T14:53:00+09:00` |

`target_time`を比較の主キーとし、`fetched_at`は収集タイミング、`source_time`はデータ鮮度評価に使う。

## 12. SQLiteデータモデル

MVPでは、**1 HTTPレスポンス/観測レコード = 1行**の`observations`テーブルを基本とする。rawとnormalizedを同じ行に持ち、再解析可能性と実装の単純さを両立する。

### observations

| Column | Type | 説明 |
|---|---|---|
| id | INTEGER PK | 連番 |
| target_time | TEXT | 比較対象時刻 |
| fetched_at | TEXT | 取得時刻 |
| source_time | TEXT NULL | データ自身の時刻 |
| source | TEXT | openweather / open_meteo / visual_crossing / tomorrow_io / amedas |
| api_version | TEXT NULL | endpoint/API version識別 |
| city | TEXT | kumagaya / tokyo / shizuoka / osaka / matsuyama |
| point_role | TEXT | primary / wind |
| station_id | TEXT NULL | AMeDAS番号 |
| lat | REAL | 取得座標 |
| lon | REAL | 取得座標 |
| temperature_c | REAL NULL | 正規化気温 |
| humidity_pct | REAL NULL | 正規化相対湿度 |
| wind_speed_ms | REAL NULL | 正規化風速 |
| precipitation_value | REAL NULL | API生値に近い降水数値 |
| precipitation_unit | TEXT NULL | mm / mm/h 等 |
| precipitation_window_min | INTEGER NULL | 数値が表す時間幅 |
| rain_detected | INTEGER NULL | 0/1。定義はsourceごとに明示 |
| temp_quality | TEXT NULL | AMeDAS品質情報 |
| humidity_quality | TEXT NULL | AMeDAS品質情報 |
| wind_quality | TEXT NULL | AMeDAS品質情報 |
| precip_quality | TEXT NULL | AMeDAS品質情報 |
| http_status | INTEGER NULL | HTTP status |
| response_ms | INTEGER NULL | 応答時間 |
| success | INTEGER | 0/1 |
| error_type | TEXT NULL | timeout / rate_limit / parse_error 等 |
| endpoint_sanitized | TEXT NULL | API keyを除去したendpoint情報 |
| raw_json | TEXT NULL | 元レスポンス全文 |
| collector_version | TEXT | 収集コードのschema/collector version |

### 推奨制約
- 同一`source + city + point_role + target_time`の重複挿入を原則禁止
- リトライで成功した場合は履歴を残すか、`attempt`列を追加する余地を残す

## 13. rawデータ保存方針

正規化値だけでなく、各社レスポンスの**元JSONを必ず保存**する。

目的:
- 単位変換ミスの再検証
- フィールド解釈ミスの修正
- 比較指標変更時の再分析
- 将来、雲量・気圧・露点・日射等を追加する際の再利用
- 「その時APIが実際に返した値」の証拠保全

ただしAPIキーを含むURL全文は保存しない。`endpoint_sanitized`にはキーをマスクしたendpointのみ保存する。

## 14. 正規化ルール

### 共通単位
- temperature: ℃
- humidity: %RH
- wind speed: m/s
- precipitation: 元の意味を保持し、unitとwindowを別カラムで保存

### 原則
- APIから返された値を勝手に補間しない
- 欠損は`NULL`として保存
- `0`と`NULL`を区別する
- 変換前の値はraw JSONで復元できる状態を維持
- source固有の変換処理は各`collectors/*.py`内部へ閉じ込める

## 15. 降水の扱い

降水はAPIによって「過去1時間」「現在の強度」「モデル15分値」等が異なるため、1つの`rain_mm`へ強制統一しない。

保持するもの:
- precipitation_value
- precipitation_unit
- precipitation_window_min
- rain_detected
- raw_json

最終比較では、まず「雨を見逃したか」を重視する。`rain_detected`の厳密な閾値は初回サンプル取得後に各APIのフィールド意味を確認して固定する。rawを保存するため、後から閾値を変更して再計算可能。

## 16. エラーハンドリング

成功データだけでなく、**失敗自体を観測データとして保存**する。

想定分類:
- timeout
- connection_error
- dns_error
- http_4xx
- rate_limit
- http_5xx
- invalid_json
- parse_error
- missing_required_field
- amedas_not_published_yet

`success=0`でも`target_time/source/city/point_role/fetched_at/error_type`を保存し、API成功率の計算に利用する。

## 17. APIキー・セキュリティ

`.env`:

```text
OPENWEATHER_API_KEY=
VISUAL_CROSSING_API_KEY=
TOMORROW_API_KEY=
```

Open-Meteo Free APIはキー不要。

`.gitignore`追加対象:

```text
.env
tools/api_comparison/data/*.db
tools/api_comparison/data/*.db-*
tools/api_comparison/logs/*.log
```

`.env.example`には変数名のみ記載し、実キーは絶対にGitへcommitしない。

## 18. 実行方式

### MVP
- まず手動実行で各collectorのレスポンス確認
- 5都市・8座標 × 4社が1サイクル保存できることを確認
- AMeDAS同時刻データとの結合確認

### 連続収集
Windows環境ではTask Schedulerで1時間ごとに`collect_current.py`を実行する。AMeDASは同一`target_time`を指定して別ジョブで取得する。

初期実装ではシンプルさを優先し逐次取得でもよい。1サイクルの所要時間が長くなる場合は非同期化/並列化する。ただしTomorrow.io Freeは3 requests/second制限があるため、並列化時はsource別rate limiterを設ける。

## 19. 分析時の基本式

**MAE**

`MAE = mean(abs(API - AMeDAS))`

**Bias**

`Bias = mean(API - AMeDAS)`

**雨の見逃し率**

`Miss Rate = False Negative / Actual Rain Cases`

分析は全都市合計と都市別の両方を出す。欠損・品質不良のAMeDAS値は評価対象から除外し、その除外数を記録する。

## 20. 完了条件（Definition of Done）

Phase 1-Bの比較基盤は、以下を満たした時点で完成とする。

- 4社APIのCurrent/Realtime取得が動く
- 8座標すべてで取得できる
- AMeDASの同一対象時刻を保存できる
- raw JSONとnormalized値が両方SQLiteへ残る
- APIキーがGit/DB/logへ漏れない
- エラー時にも履歴が残る
- 同一`target_time`でAPI値とAMeDAS値をJOINできる
- 1時間ごとの自動収集を開始できる

## 21. リスクと注意点

1. **AMeDASの空間代表性**  
   APIの座標値は格子・補間・モデル値であり、観測所一点と完全同義ではない。

2. **風の観測条件差**  
   センサー高さ・平均時間・周辺地形等の差があるため、風速MAEは参考指標として解釈する。

3. **AMeDAS取得経路の仕様変更**  
   Web表示用JSONは一般開発者向けAPI契約ではないため、`amedas.py`へ隔離する。

4. **API仕様変更**  
   `api_version`と`collector_version`を保存し、期間途中の仕様変更を追跡できるようにする。

5. **降水の時間窓差**  
   値を無理に同一量へ正規化せず、rawとwindow metadataを保持する。

6. **データ量不足**  
   雨天ケースが少ない場合、収集期間延長または取得間隔変更を検討する。

## 22. 実装順序

1. `tools/api_comparison/`の骨組み作成
2. SQLite schema作成
3. `locations.py`作成
4. OpenWeather collector
5. Open-Meteo collector
6. Visual Crossing collector
7. Tomorrow.io collector
8. `collect_current.py`統合
9. AMeDAS collector
10. `collect_amedas.py`統合
11. 1サイクル手動テスト
12. raw/normalizedの確認
13. Task Schedulerで1時間収集開始

## 23. 参考公式資料

- OpenWeather API: https://openweathermap.org/api
- Open-Meteo Forecast API: https://open-meteo.com/en/docs
- Open-Meteo Pricing/Free limits: https://open-meteo.com/en/pricing
- Visual Crossing Timeline API: https://www.visualcrossing.com/resources/documentation/weather-api/timeline-weather-api/
- Visual Crossing Current Conditions: https://www.visualcrossing.com/resources/documentation/weather-api/how-to-look-up-the-current-weather-conditions-in-the-weather-api/
- Tomorrow.io Realtime Weather: https://docs.tomorrow.io/reference/realtime-weather
- Tomorrow.io Free rate limits: https://support.tomorrow.io/hc/en-us/articles/20273728362644-Free-API-Plan-Rate-Limits
- 気象庁 AMeDAS観測所一覧: https://www.jma.go.jp/jma/kishou/know/amedas/ame_master.pdf

---

**設計上の最重要原則:**  
**raw = 証拠データ / normalized = 比較用データ**  
Historicalの後処理に依存せず、「その瞬間にユーザーへ返り得た情報」を自前で保存して評価する。
