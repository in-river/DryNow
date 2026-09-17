# API比較結果と採用決定

確認日: 2026-09-17。既存の同名ファイルがなかったため新規作成。

## 採用API：Open-Meteo

DryNow本体には **Open-Meteo Forecast API** を採用する。
現段階は非商用の学習・検証用とし、商用公開時は有料customer APIへ移行する。
今回の判断に伴う契約・購入は行っていない。

- 共通標本で湿度・風速のMAEは4社中2位。気温MAEは0.781℃で最良ではないが、現在値による暫定ルールの開発を進める入力として採用する。乾燥結果に対する精度は別途検証する。
- 成功レスポンス内の気温・湿度・風速・降水の欠損は0件。降水の時間窓も明示されている。
- 予報、突風、雲量、露点、日射量を同じForecast APIで拡張できる。モデルの日射と別商品のSatellite Radiation APIは区別する。
- 非商用開発ではキー不要。商用は月間回数ベースの定額契約で、同じ形式のcustomer endpointへ移行できる。データのCC BY 4.0は帰属・加工の明示が必要。[仕様](https://open-meteo.com/en/docs)、[料金・帰属](https://open-meteo.com/en/pricing)

**数値上の最良はTomorrow.ioである。** Open-Meteoの採用は精度だけの順位ではなく、
将来の項目拡張、料金体系、raw保存を伴う検証運用を合わせた開発上の判断である。

| 不採用API | 主な理由 |
|---|---|
| Tomorrow.io | 気温・湿度・風速のMAEと雨の参考指標は最良。ただし商用は契約許諾、日射はEnterprise premiumで、raw保存・ベンチマークに関する規約制限も既存検証運用と要調整。現段階で必要な契約調整が少ないOpen-Meteoを選ぶ。 |
| Visual Crossing | 無料枠で商用利用でき拡張項目も豊富だが、今回の雨判定欠損40.80%、データ経過時間平均28.465分が現在値判定の弱点。 |
| OpenWeather | 気温は良好だが湿度・風速の誤差が今回最大。露点・日射等の拡張がCurrent APIだけでは完結しない。 |

## 再実行条件

- DB: `tools/api_comparison/data/weather_validation.db`（ワークスペース内の最新DB）
- DB全体: 6,818行、`target_time` は2026-09-01 16:47:55～09-17 13:00 JST。
- 比較: 熊谷・東京・静岡・大阪・松山のprimary地点。APIとAMeDASを `target_time + city + point_role` で結合し、両者成功・対象項目ありの行を使う。
- 4API共通標本: **1,210地点時刻（各都市242件）**、09-05 01:30～09-17 13:00 JST。気温・湿度・風速はAPI別利用可能標本と共通標本が同じ。
- 実行: `python tools/api_comparison/compare.py`。DBは読み取り専用のトランザクションで参照し、API呼び出し・保存済み観測の更新なし。
- 出力: `tools/api_comparison/logs/compare_latest.log`（Git管理外）。DBへの継続追記後は集計値が変わる。

## 気温・湿度・風速、鮮度

MAEはAMeDASに対する平均絶対誤差。湿度はパーセントポイント。
鮮度は全取得成功行の `fetched_at - source_time` の符号付き平均で、MAEとは母集団が異なる。

| API | 気温MAE ℃ | 湿度MAE pt | 風速MAE m/s | 平均経過時間 分（n） | AMeDASとの平均絶対時刻差 分 |
|---|---:|---:|---:|---:|---:|
| OpenWeather | 0.689 | 9.183 | 1.726 | 1.025（1,245） | 14.057 |
| Open-Meteo | 0.781 | 5.141 | 1.041 | 5.305（1,243） | 9.835 |
| Visual Crossing | 0.771 | 5.873 | 1.283 | 28.465（1,228） | 13.337 |
| Tomorrow.io | 0.508 | 2.293 | 0.652 | 0.217（1,230） | 14.912 |

時刻欠損は成功行で0件。OpenWeatherには負の経過時間が17件あり、平均から除外・0補正していない。
APIの `source_time` は観測・モデルの有効時刻など意味が異なり、経過時間の短さを実際の観測更新速度と同一視しない。
Open-Meteoのcurrentはモデル値で、日本の15分値には時間別値の補間を含む。[時刻・current仕様](https://open-meteo.com/en/docs)

## 可用性・欠損

| API | 取得成功 / 記録 | 成功率 | 未記録 / 全1,378地点時刻 | 成功行内の気温・湿度・風速欠損 | 成功行内の雨判定欠損 |
|---|---:|---:|---:|---|---:|
| OpenWeather | 1,245 / 1,378 | 90.35% | 0 | 各0% | 0% |
| Open-Meteo | 1,243 / 1,375 | 90.40% | 3 | 各0% | 0% |
| Visual Crossing | 1,228 / 1,360 | 90.29% | 18 | 各0% | 40.80%（501件） |
| Tomorrow.io | 1,230 / 1,360 | 90.44% | 18 | 各0% | 0.41%（5件） |

AMeDAS成功行だけを分母にすると4社とも100%となるが、収集失敗を除外した値になる。
上表の失敗はすべて `URLError`、うち130地点時刻は5ソース同時失敗。ローカル通信等の共通要因も考えられるが原因は断定できず、API固有の障害率やSLAとは解釈しない。
未記録には導入前の枠も含み、取得失敗とは別扱い。全ソース未記録の枠はDBだけでは数えられない。

## 雨判定（参考評価）

4APIとAMeDASの雨判定がすべて有効な共通712件（AMeDAS雨111件）を使用。

| API | 検知 TP | 空振り FP | 見逃し FN | 非雨 TN | 雨検知率 | 雨判定の適合率 |
|---|---:|---:|---:|---:|---:|---:|
| OpenWeather | 102 | 247 | 9 | 354 | 91.89% | 29.23% |
| Open-Meteo | 96 | 267 | 15 | 334 | 86.49% | 26.45% |
| Visual Crossing | 58 | 159 | 53 | 442 | 52.25% | 26.73% |
| Tomorrow.io | 108 | 160 | 3 | 441 | 97.30% | 40.30% |

保存済み降水の意味はAMeDAS=10分mm、Open-Meteo=15分mm、OpenWeather=60分mm、
Visual Crossing=時間窓未確定mm、Tomorrow.io=mm/hrの強度。単位・時間窓を揃えたランキングではない。
共通712件は全APIの欠損がない条件で抽出され、欠損による偏りも残る。
Open-Meteoでも雨の見逃しがあり、v1の「適性あり」は将来の雨や乾燥完了の保証には使わない。

## 料金・利用条件・将来データ（公式資料を2026-09-17確認）

既存v1.0資料には無料枠の概要のみだったため、以下は公式資料で補完した。
アカウント固有の契約内容は未確認。

| API | 無料枠 / 有料料金 | 利用条件 | gust / cloud cover / dew point / solar radiation / 降水確率 |
|---|---|---|---|
| Open-Meteo | 600回/分、5,000回/時、10,000回/日、300,000回/月。Standard 100万回/月の定額。現行の具体的月額は取得した公式本文で確認できず未確定。 | 無料endpointは非商用限定。商用は有料customer endpoint。CC BY 4.0帰属・加工表示。 | Forecastで全項目に対応。Satellite Radiationは別API・商用Professional以上。[料金](https://open-meteo.com/en/pricing)・[規約](https://open-meteo.com/en/terms)・[変数](https://open-meteo.com/en/docs) |
| Visual Crossing | 1,000 records/日無料。Metered超過 $0.0001/record。回数ではなくレコード課金で、返す時間数に注意。 | 無料枠でも商用可、Free/Metered/Professionalは帰属必要。未加工データの再配布に制約。 | Coreに全項目。高度な日射等は別プラン。[料金・条件](https://www.visualcrossing.com/weather-data-pricing/)・[従量課金](https://www.visualcrossing.com/resources/documentation/weather-data/understanding-and-optimizing-the-visual-crossing-weather-pay-as-you-go-plan/)・[変数](https://www.visualcrossing.com/resources/documentation/weather-data/weather-data-documentation/) |
| OpenWeather | Current 2.5無料60回/分、100万回/月。別契約One Call 4.0は1,000回/日無料、超過$0.0015/回（税別）。 | FreeはOpen License、帰属・ShareAlike条件。 | Currentにgust/clouds。露点・確率はOne Call/予報、日射は別Solar API。[無料枠](https://openweathermap.org/full-price)・[One Call料金](https://home.openweathermap.org/subscriptions/unauth_subscribe/onecall_40/base)・[ライセンス](https://openweathermap.org/storage/app/media/documents/License_explainer_25%20Feb_25.pdf)・[Current](https://openweathermap.org/api/current)・[Solar](https://openweathermap.org/api/solar-radiation) |
| Tomorrow.io | 無料500回/日、25回/時、3回/秒。有料Enterpriseは見積もり。 | 自己登録・評価での商用禁止。商用は契約許諾。リンク付き帰属が必要。 | gust/雲量/露点/確率はCore、solarはEnterprise premium。[無料枠](https://support.tomorrow.io/hc/en-us/articles/20273728362644-Free-API-Plan-Rate-Limits)・[Core](https://docs.tomorrow.io/reference/data-layers-core)・[プラン](https://www.tomorrow.io/weather-api/)・[規約](https://www.tomorrow.io/legal/terms-of-service/) |

Tomorrow.io規約§9.1.12と§9.1.14にはベンチマーク公開等と未加工Datafeed保存の制限がある。
既存データや収集設定は変更していないが、継続保存・比較結果の外部公開前には個別契約の許諾を確認する。[規約](https://www.tomorrow.io/legal/terms-of-service/)

## 判断の限界と次の検証

- 約2週間・5都市のprimary地点であり、季節・寒冷時・強風条件を網羅していない。予報精度は今回評価していない。
- AMeDAS比較1,210件中1,175件（97.1%）は `target_time` より10分前の値。完全な同時観測比較ではない。
- 風速は観測高度・露場・モデル格子の差を含む。各都市のwind専用地点は未収集。
- 乾きやすさの正解データはまだなく、MAEから直接乾燥時間の精度を保証できない。
- 外干し判定v1と時間別予報の接続v8を実装した。次は干している期間全体の評価と、実際の乾燥結果での閾値検証を進める。詳しくは[外干し判定v1](DRYING_RULES_V1.md)と[予報ベースの実用化](FORECAST_IMPLEMENTATION_V8.md)。

## 実装・検証

`compare.py` に共通標本・取得時点の経過時間・成功率/未記録/項目欠損の分離を追加。
Flutterは `WeatherApi → Weather → DryingEvaluator → 画面` の形で現在値判定へ接続した。
確認結果:

- `python -m unittest discover -s tools/api_comparison/tests -v`: 57件成功（比較8件を含む、既存DB更新なし）。
- `dart format lib test`: 整形完了。
- `flutter analyze --no-pub`: No issues found。
- `flutter test --no-pub`: 91件成功（閾値境界、欠損/0、不正値、雨雪、鮮度、単位、通信エラー、画面の再読み込み/経時変化）。
- Flutterと同じ `WeatherApi` からOpen-Meteoへキー不要のGETを1回実施。必須値・単位・UTC時刻・900秒の降水時間窓・raw保持・判定接続を確認。DB保存なし。
- デスクトップ/スマートフォン実機での起動・見た目の確認は未実施。判定画面はWidgetテストで確認。

変更ファイル:

| 範囲 | ファイル | 変更理由 |
|---|---|---|
| 比較 | `tools/api_comparison/compare.py`、`tools/api_comparison/tests/test_compare.py` | 読み取り専用化、共通標本・鮮度・可用性の比較を再現可能にする。 |
| API/モデル | `lib/weather_api.dart`、`lib/models/weather.dart` | Open-Meteo接続、単位・時刻・欠損・rawの保持。 |
| 判定/UI | `lib/drying_assessment.dart`、`lib/main.dart`、`pubspec.yaml` | 純粋ルールと理由表示、鮮度再評価、不要な.envアセット同梱を停止。 |
| Flutterテスト | `test/drying_assessment_test.dart`、`test/weather_api_test.dart`、`test/weather_page_test.dart` | 判定・変換・通信失敗・表示まで検証。 |
| 文書 | `docs/API_COMPARISON_RESULT.md`、`docs/DRYING_RULES_V1.md`、`README.md`、`tools/api_comparison/README.md`、`docs/WEATHER_DATA_VALIDATION.md`、`docs/DRYNOW_API_COMPARISON_DESIGN_v1.1.md` | 採用決定と仕様を記録し、過去の未実装記載と現行状態を区別。 |
