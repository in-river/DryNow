# API比較ツール

DryNowで使用する天気APIを選定するための比較ツールです。

複数の天気APIから同じ地点・共通の対象時刻枠の気象データを取得し、
気象庁のAMeDAS観測値と比較することで、
DryNowに適したAPIを検証することを目的としています。

## 比較対象のAPI

- OpenWeather
- Open-Meteo
- Visual Crossing
- Tomorrow.io

比較地点は、熊谷・東京・静岡・大阪・松山の5地点です。

主に以下の項目を比較します。各APIのデータ時刻や降水の時間窓は一致しないため、別途確認します。

- 気温
- 湿度
- 風速
- 降水
- データの取得成功率
- データの鮮度

## 現在の実装・運用状況（2026-09-17）

Phase 1-Bとして、以下の収集基盤を実装・運用しています。

- 比較地点の定義
- SQLiteデータベースの初期化
- `.env` からのAPIキー読み込み
- APIごとの収集処理を分離するための構成
- 取得データ・ログをGit管理から除外する設定
- OpenWeather、Open-Meteo、Visual Crossing、Tomorrow.ioの現在値とAMeDASの取得
- 5都市のprimary地点を対象にしたSQLite保存
- 通常1回につき5都市 × 5ソース = 25レコードの保存
- Windows Task Schedulerによる毎時05分・35分の自動実行
- `compare.py`によるAMeDASとの比較、4API共通標本での比較、鮮度・可用性・欠損率の集計
- API collector、AMeDAS、`target_time`丸め、比較処理の単体テスト（57 tests / OK）

実API取得とSQLite保存を確認済みです。また、16:35のTask Scheduler自動実行で、
全レコードが`target_time=16:30`となる25レコードの保存を確認しています。

4APIとAMeDASのcollector・比較処理は実装済みです。採用APIは**Open-Meteo**に決定しました。
最新DBによる比較結果と選定理由は[API比較結果](../../docs/API_COMPARISON_RESULT.md)を参照してください。
FlutterはOpen-Meteoの現在値取得、[外干し判定v1](../../docs/DRYING_RULES_V1.md)、
[時間別予報を使うv8 UI](../../docs/FORECAST_IMPLEMENTATION_V8.md)を実装しています。乾燥時間推定は未実装です。

APIから取得したデータは、比較用に整形した値だけでなく、
元のレスポンスも保存できる構成にしています。

これにより、後から取得項目や変換処理を確認したり、
比較方法を変更した場合でも再検証できるようにします。

## 現在値の手動収集

プロジェクトルートまたは`tools/api_comparison`の`.env`へ
`OPENWEATHER_API_KEY`、`VISUAL_CROSSING_API_KEY`、`TOMORROW_API_KEY`を設定し、次のコマンドを実行します。
Open-MeteoとAMeDASはキー不要です。キー未設定のAPIは収集を試みず、DBに行を保存しません。

```powershell
python tools/api_comparison/collect_current.py
```

## 保存済みデータの比較とテスト

次の比較は`data/weather_validation.db`を読み取り専用で開き、API通信やDB更新を行いません。
取得成功率は各APIの記録行を分母にし、未記録と取得成功行内の項目欠損を区別します。
鮮度は`fetched_at - source_time`、AMeDASとの時刻差は別指標として表示します。

```powershell
python tools/api_comparison/compare.py
python -m unittest discover -s tools/api_comparison/tests -v
```

## Windows Task Schedulerによる自動収集

`run_current_collection.ps1`は、スクリプト自身の位置を基準にプロジェクトと
`collect_current.py`を解決します。Task Schedulerの作業ディレクトリに依存せず、
実行ごとの標準出力と標準エラーを`logs/`へ分けて保存します。

登録前にPythonの実体を確認します。

```powershell
(Get-Command python).Source
```

実行用スクリプトだけを手動確認する例です。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/api_comparison/run_current_collection.ps1 `
  -PythonPath "C:\Path\To\python.exe"
```

Task Schedulerへ毎時5分・35分に登録する例です。初回を次の5分または35分に設定し、
以後30分間隔で実行します。登録スクリプトを実行すると、同名タスクは更新されます。
必要な内容を確認してから実行してください。

登録前に、`-ValidateOnly`を付けて登録直前までの設定を検証できます。この場合、
Task Schedulerへの登録・更新は行いません。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/api_comparison/register_current_collection_task.ps1 `
  -PythonPath "C:\Path\To\python.exe" `
  -Minute 5 `
  -ValidateOnly
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/api_comparison/register_current_collection_task.ps1 `
  -PythonPath "C:\Path\To\python.exe" `
  -Minute 5
```

既定ではログオン中のユーザーとして動作し、スリープ解除は行いません。
PCが停止していた場合は収集できません。スリープ中または一時的に実行できなかった場合は、
復帰後に可能な範囲で実行します。

スリープ中のPCを収集時刻に復帰させる場合は、検証時と登録時の両方に
`-WakeToRun`を追加します。未指定の場合はOFFです。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/api_comparison/register_current_collection_task.ps1 `
  -PythonPath "C:\Path\To\python.exe" `
  -Minute 5 `
  -WakeToRun `
  -ValidateOnly
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/api_comparison/register_current_collection_task.ps1 `
  -PythonPath "C:\Path\To\python.exe" `
  -Minute 5 `
  -WakeToRun
```

WakeToRunを有効にしても、PCの電源が完全に切れている場合は実行できません。
また、Windowsの電源プラン、スリープ解除タイマー、端末のファームウェア設定によっては
復帰できない場合があります。

`collect_current.py`の`target_time`はJSTの30分境界へ切り捨てます。そのため、
17:05の収集は17:00、17:35の収集は17:30として全都市・全APIで共有されます。

同じ時刻枠で再実行すると、`source + city + point_role + target_time`の一意制約により
既存レコードの上書きは行われず、対象レコードの保存は失敗としてログへ残ります。
タスクの前回実行が継続中の場合、新しい実行は開始しません。

## 今後

季節・降雨条件を増やした検証、干している期間全体の予報評価、データ時刻差や収集失敗の分析を進めます。
外部APIの継続収集・保存は各サービスの利用条件に従って運用します。
