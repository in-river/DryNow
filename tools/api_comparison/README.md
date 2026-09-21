# API比較ツール

DryNowで使用する天気APIを選定するために作成した比較ツールです。

複数の天気APIから同じ地点・共通の対象時刻枠の気象データを取得し、気象庁のAMeDAS観測値と比較することで、DryNowに適したAPIを検証することを目的としています。

## 比較対象のAPI

- OpenWeather
- Open-Meteo
- Visual Crossing
- Tomorrow.io

比較地点は、熊谷・東京・静岡・大阪・松山の5地点です。

主に以下の項目を比較します。

- 気温
- 湿度
- 風速
- 降水
- データの取得成功率
- データの鮮度

各APIでは、データが表す時刻や降水量の時間窓などが一致しない場合があります。そのため、単純に数値だけを比較するのではなく、各データの性質も確認した上で評価します。

## 実装・運用状況

Phase 1-Bとして、以下の収集・比較基盤を実装しました。

- 比較地点の定義
- SQLiteデータベースの初期化
- `.env`からのAPIキー読み込み
- APIごとの収集処理を分離する構成
- 取得データ・ログをGit管理から除外する設定
- OpenWeather、Open-Meteo、Visual Crossing、Tomorrow.ioの現在値とAMeDASの取得
- 5都市のprimary地点を対象にしたSQLite保存
- 通常1回につき5都市 × 5ソース = 25レコードの保存
- Windows Task Schedulerによる毎時05分・35分の自動実行
- `compare.py`によるAMeDASとの比較
- 4API共通標本での比較
- データ鮮度、可用性、欠損率の集計
- API collector、AMeDAS、`target_time`丸め、比較処理の単体テスト

Python側の関連テストは57件成功しています。

実API取得とSQLite保存も確認済みです。Task Schedulerによる連続収集では、5都市 × 5ソースの25レコードを共通の`target_time`で保存できることを確認しました。

4APIとAMeDASのcollector・比較処理は実装済みです。

比較結果に加えて、DryNowで必要な気象項目、利用条件、APIキーの扱いやすさなども踏まえ、アプリ本体では**Open-Meteo**を採用しています。

最新の比較結果と選定理由は [API比較結果](../../docs/API_COMPARISON_RESULT.md) を参照してください。

DryNow本体では、Open-Meteoの現在値・時間別予報を取得し、[外干し判定v1](../../docs/DRYING_RULES_V1.md) と乾燥時間予測v1を実装しています。

現在のDryNow全体の実装状況は [README.md](../../README.md) と [V9_VALIDATION.md](../../docs/V9_VALIDATION.md) を参照してください。

APIから取得したデータは、比較用に整形した値だけでなく、元のレスポンスも保存できる構成にしています。

これにより、後から取得項目や変換処理を確認したり、比較方法を変更した場合でも再検証できます。

## 現在値の手動収集

プロジェクトルートまたは`tools/api_comparison`の`.env`へ、以下のAPIキーを設定します。

```text
OPENWEATHER_API_KEY=
VISUAL_CROSSING_API_KEY=
TOMORROW_API_KEY=
```

Open-MeteoとAMeDASはAPIキー不要です。

キー未設定のAPIは収集を試みず、DBに行を保存しません。

設定後、次のコマンドを実行します。

```powershell
python tools/api_comparison/collect_current.py
```

## 保存済みデータの比較とテスト

`compare.py`は`data/weather_validation.db`を読み取り専用で開き、保存済みデータを分析します。

この処理ではAPI通信やDB更新を行いません。

取得成功率は各APIの記録行を分母として計算し、「API自体の記録が存在しない状態」と「取得成功行の中で特定項目が欠損している状態」を区別します。

データ鮮度は、

```text
fetched_at - source_time
```

を基準として確認します。

AMeDASとの時刻差は、データ鮮度とは別の指標として扱います。

比較処理は次のコマンドで実行します。

```powershell
python tools/api_comparison/compare.py
```

Python側のテストは次のコマンドで実行します。

```powershell
python -m unittest discover -s tools/api_comparison/tests -v
```

## Windows Task Schedulerによる自動収集

`run_current_collection.ps1`は、スクリプト自身の位置を基準にプロジェクトルートと`collect_current.py`を解決します。

そのため、Task Scheduler側の作業ディレクトリに依存せず実行できます。

実行ごとの標準出力と標準エラーは`logs/`へ分けて保存します。

### Pythonの実体を確認

登録前に、使用するPythonのパスを確認します。

```powershell
(Get-Command python).Source
```

### 実行用スクリプトの手動確認

Task Schedulerへ登録する前に、実行用スクリプトだけを手動で確認できます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/api_comparison/run_current_collection.ps1 `
  -PythonPath "C:\Path\To\python.exe"
```

### Task Schedulerへの登録前確認

登録スクリプトに`-ValidateOnly`を付けると、Task Schedulerへ実際に登録・更新せず、登録直前までの設定を検証できます。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/api_comparison/register_current_collection_task.ps1 `
  -PythonPath "C:\Path\To\python.exe" `
  -Minute 5 `
  -ValidateOnly
```

### Task Schedulerへ登録

毎時05分・35分に実行する例です。

初回実行時刻を次の05分または35分に設定し、その後30分間隔で実行します。

同名のタスクが存在する場合は更新されるため、内容を確認してから実行してください。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/api_comparison/register_current_collection_task.ps1 `
  -PythonPath "C:\Path\To\python.exe" `
  -Minute 5
```

既定では、ログオン中のユーザーとして動作し、スリープ解除は行いません。

PCの電源が切れている場合や、収集時刻に実行できない状態だった場合は、その時間帯のデータを取得できません。

一時的に実行できなかった場合は、Windowsの設定に応じて復帰後に実行される場合があります。

## スリープ解除を有効にする場合

スリープ中のPCを収集時刻に復帰させる場合は、検証時と登録時の両方に`-WakeToRun`を追加します。

未指定の場合はOFFです。

登録前確認:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/api_comparison/register_current_collection_task.ps1 `
  -PythonPath "C:\Path\To\python.exe" `
  -Minute 5 `
  -WakeToRun `
  -ValidateOnly
```

登録:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/api_comparison/register_current_collection_task.ps1 `
  -PythonPath "C:\Path\To\python.exe" `
  -Minute 5 `
  -WakeToRun
```

`WakeToRun`を有効にしても、PCの電源が完全に切れている場合は実行できません。

また、Windowsの電源プラン、スリープ解除タイマー、端末のファームウェア設定などによっては復帰できない場合があります。

## target_timeの扱い

`collect_current.py`の`target_time`は、JSTの30分境界へ切り捨てます。

例えば、

- 17:05の収集 → `target_time=17:00`
- 17:35の収集 → `target_time=17:30`

として扱います。

同一実行内では、全都市・全APIで同じ`target_time`を共有します。

これにより、実際のHTTP取得時刻がAPIごとに数秒～数十秒ずれても、同じ比較対象時刻枠として扱えます。

## 重複データの扱い

同じ時刻枠で再実行した場合、

```text
source + city + point_role + target_time
```

の一意制約により、既存レコードを上書きしません。

重複するレコードの保存は失敗としてログへ記録し、その後の地点・APIの処理は継続します。

Task Schedulerでは、前回の収集処理がまだ実行中の場合、新しい実行を開始しない設定にしています。

## 保存データについて

比較用の正規化値だけでなく、再検証のためのraw JSONも保存します。

主な目的は次のとおりです。

- APIが実際に返した内容の確認
- フィールド解釈の再確認
- 単位変換や正規化処理の検証
- 比較指標を変更した場合の再分析
- 将来、別の気象項目を利用する場合の再解析

APIキーを含む情報は保存対象から除外します。

SQLiteデータベース、ログ、`.env`などの実データ・秘密情報はGit管理対象外です。

## 今後

API比較については、必要に応じて季節や降雨条件の異なるデータを追加し、気象条件による傾向を確認します。

DryNow本体では、実際の衣類乾燥データを用いた乾燥時間予測v1の検証・補正と、乾燥モデルv2の改善を進めます。

外部APIの収集・保存・公開については、各サービスの利用条件を確認した上で運用します。