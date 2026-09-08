import sqlite3
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from statistics import mean


DB_PATH = Path(__file__).parent / "data" / "weather_validation.db"

API_SOURCES = (
    "openweather",
    "open_meteo",
    "visual_crossing",
    "tomorrow_io",
)

CITY_NAMES = {
    "kumagaya": "熊谷",
    "tokyo": "東京",
    "shizuoka": "静岡",
    "osaka": "大阪",
    "matsuyama": "松山",
}


def parse_time(value):
    if value is None:
        return None

    return datetime.fromisoformat(value)


def calculate_mae(rows, api_key, ref_key):
    values = []

    for row in rows:
        api_value = row[api_key]
        ref_value = row[ref_key]

        if api_value is None or ref_value is None:
            continue

        values.append(abs(api_value - ref_value))

    if not values:
        return None, 0

    return mean(values), len(values)


def calculate_bias(rows, api_key, ref_key):
    values = []

    for row in rows:
        api_value = row[api_key]
        ref_value = row[ref_key]

        if api_value is None or ref_value is None:
            continue

        values.append(api_value - ref_value)

    if not values:
        return None

    return mean(values)


def calculate_rain_agreement(rows):
    results = []

    for row in rows:
        api_rain = row["api_rain"]
        amedas_rain = row["amedas_rain"]

        if api_rain is None or amedas_rain is None:
            continue

        results.append(api_rain == amedas_rain)

    if not results:
        return None, 0

    agreement = sum(results) / len(results) * 100

    return agreement, len(results)


def calculate_time_gap(rows):
    gaps = []

    for row in rows:
        api_time = parse_time(row["api_source_time"])
        amedas_time = parse_time(row["amedas_source_time"])

        if api_time is None or amedas_time is None:
            continue

        gap_min = abs((api_time - amedas_time).total_seconds()) / 60
        gaps.append(gap_min)

    if not gaps:
        return None

    return mean(gaps)


def load_comparisons(con):
    placeholders = ", ".join("?" for _ in API_SOURCES)

    sql = f"""
        SELECT
            api.source,
            api.city,
            api.target_time,

            api.source_time AS api_source_time,
            amedas.source_time AS amedas_source_time,

            api.temperature_c AS api_temp,
            amedas.temperature_c AS amedas_temp,

            api.humidity_pct AS api_humidity,
            amedas.humidity_pct AS amedas_humidity,

            api.wind_speed_ms AS api_wind,
            amedas.wind_speed_ms AS amedas_wind,

            api.rain_detected AS api_rain,
            amedas.rain_detected AS amedas_rain

        FROM observations AS api

        INNER JOIN observations AS amedas
            ON api.target_time = amedas.target_time
            AND api.city = amedas.city
            AND api.point_role = amedas.point_role

        WHERE
            api.source IN ({placeholders})
            AND amedas.source = 'amedas'
            AND api.success = 1
            AND amedas.success = 1

        ORDER BY
            api.source,
            api.target_time,
            api.city
    """

    return con.execute(sql, API_SOURCES).fetchall()


def print_metric(name, value, count=None, unit=""):
    if value is None:
        print(f"  {name:<20}: N/A")
        return

    count_text = ""

    if count is not None:
        count_text = f"  (n={count})"

    print(f"  {name:<20}: {value:.3f}{unit}{count_text}")

def print_city_comparison(rows):
    cities = sorted({row["city"] for row in rows})

    print()
    print("=== 都市別比較 ===")

    for city in cities:
        print()
        print(f"### {CITY_NAMES.get(city, city)} ###")

        city_rows = [
            row for row in rows
            if row["city"] == city
        ]

        grouped = defaultdict(list)

        for row in city_rows:
            grouped[row["source"]].append(row)

        for source in API_SOURCES:
            source_rows = grouped[source]

            temp_mae, temp_n = calculate_mae(
                source_rows,
                "api_temp",
                "amedas_temp",
            )

            humidity_mae, humidity_n = calculate_mae(
                source_rows,
                "api_humidity",
                "amedas_humidity",
            )

            wind_mae, wind_n = calculate_mae(
                source_rows,
                "api_wind",
                "amedas_wind",
            )

            rain_agreement, rain_n = calculate_rain_agreement(
                source_rows
            )

            time_gap = calculate_time_gap(source_rows)

            print()
            print(f"--- {source} ---")
            print(f"  比較件数             : {len(source_rows)}")

            print_metric(
                "気温 MAE",
                temp_mae,
                temp_n,
                " C",
            )

            print_metric(
                "湿度 MAE",
                humidity_mae,
                humidity_n,
                " %",
            )

            print_metric(
                "風速 MAE",
                wind_mae,
                wind_n,
                " m/s",
            )

            print_metric(
                "降水一致率",
                rain_agreement,
                rain_n,
                " %",
            )

            print_metric(
                "観測時刻差",
                time_gap,
                unit=" min",
            )

def print_availability(con):
    print()
    print("=== データ可用性 ===")

    for source in API_SOURCES:
        row = con.execute(
            """
            SELECT
                COUNT(*) AS expected,

                SUM(
                    CASE
                        WHEN api.id IS NOT NULL THEN 1
                        ELSE 0
                    END
                ) AS paired,

                SUM(
                    CASE
                        WHEN api.success = 1 THEN 1
                        ELSE 0
                    END
                ) AS successful,

                SUM(
                    CASE
                        WHEN api.temperature_c IS NOT NULL THEN 1
                        ELSE 0
                    END
                ) AS temperature_available,

                SUM(
                    CASE
                        WHEN api.humidity_pct IS NOT NULL THEN 1
                        ELSE 0
                    END
                ) AS humidity_available,

                SUM(
                    CASE
                        WHEN api.wind_speed_ms IS NOT NULL THEN 1
                        ELSE 0
                    END
                ) AS wind_available,

                SUM(
                    CASE
                        WHEN api.rain_detected IS NOT NULL THEN 1
                        ELSE 0
                    END
                ) AS rain_available

            FROM observations AS amedas

            LEFT JOIN observations AS api
                ON api.target_time = amedas.target_time
                AND api.city = amedas.city
                AND api.point_role = amedas.point_role
                AND api.source = ?

            WHERE
                amedas.source = 'amedas'
                AND amedas.success = 1
            """,
            (source,),
        ).fetchone()

        (
            expected,
            paired,
            successful,
            temperature_available,
            humidity_available,
            wind_available,
            rain_available,
        ) = row

        def rate(value):
            if expected == 0:
                return 0.0

            return value / expected * 100

        print()
        print(f"--- {source} ---")
        print(f"  比較基準件数             : {expected}")
        print(
            f"  比較可能                 : {paired}/{expected} "
            f"({rate(paired):.2f}%)"
        )
        print(
            f"  取得成功                 : {successful}/{expected} "
            f"({rate(successful):.2f}%)"
        )
        print(
            f"  気温                 : {temperature_available}/{expected} "
            f"({rate(temperature_available):.2f}%)"
        )
        print(
            f"  湿度                 : {humidity_available}/{expected} "
            f"({rate(humidity_available):.2f}%)"
        )
        print(
            f"  風速                 : {wind_available}/{expected} "
            f"({rate(wind_available):.2f}%)"
        )
        print(
            f"  雨判定               : {rain_available}/{expected} "
            f"({rate(rain_available):.2f}%)"
        )

def calculate_rain_confusion(rows):
    tp = 0
    fp = 0
    fn = 0
    tn = 0

    for row in rows:
        api_rain = row["api_rain"]
        amedas_rain = row["amedas_rain"]

        if api_rain is None or amedas_rain is None:
            continue

        if api_rain == 1 and amedas_rain == 1:
            tp += 1

        elif api_rain == 1 and amedas_rain == 0:
            fp += 1

        elif api_rain == 0 and amedas_rain == 1:
            fn += 1

        elif api_rain == 0 and amedas_rain == 0:
            tn += 1

    evaluated = tp + fp + fn + tn

    precision = None
    if tp + fp > 0:
        precision = tp / (tp + fp) * 100

    recall = None
    if tp + fn > 0:
        recall = tp / (tp + fn) * 100

    miss_rate = None
    if tp + fn > 0:
        miss_rate = fn / (tp + fn) * 100

    return {
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "tn": tn,
        "evaluated": evaluated,
        "precision": precision,
        "recall": recall,
        "miss_rate": miss_rate,
    }


def print_rain_confusion_analysis(rows):
    print()
    print("=== 雨判定の当たり方・見逃し分析 ===")

    grouped = defaultdict(list)

    for row in rows:
        grouped[row["source"]].append(row)

    for source in API_SOURCES:
        result = calculate_rain_confusion(grouped[source])

        print()
        print(f"--- {source} ---")
        print(f"  評価件数             : {result['evaluated']}")
        print(f"  雨を正しく検知       : {result['tp']}")
        print(f"  雨の空振り           : {result['fp']}")
        print(f"  雨の見逃し           : {result['fn']}")
        print(f"  雨なしを正しく判定   : {result['tn']}")

        print_metric(
            "雨判定の正確さ",
            result["precision"],
            unit=" %",
        )

        print_metric(
            "雨の検知率",
            result["recall"],
            unit=" %",
        )

        print_metric(
            "雨の見逃し率",
            result["miss_rate"],
            unit=" %",
        )

def print_precipitation_definitions(con):
    print()
    print("=== 降水データの比較条件 ===")

    rows = con.execute("""
        SELECT
            source,
            precipitation_unit,
            precipitation_window_min,
            COUNT(*) AS count
        FROM observations
        WHERE success = 1
        GROUP BY
            source,
            precipitation_unit,
            precipitation_window_min
        ORDER BY source
    """).fetchall()

    for source, unit, window, count in rows:
        window_text = (
            f"{window} 分"
            if window is not None
            else "未定義"
        )

        print(
            f"  {source:<16} "
            f"単位={unit:<6} "
            f"観測時間幅={window_text:<12} "
            f"件数={count}"
        )

    print()
    print(
        "注意: 雨判定の評価値は参考値です。"
    )
    print(
        "ソースごとに降水の観測時間幅が異なるため、降水ランキングは表示しません。"
    )

def print_overall_summary(rows):
    print()
    print("=== 総合サマリー ===")

    grouped = defaultdict(list)

    for row in rows:
        grouped[row["source"]].append(row)

    metrics = {
        "気温 MAE": (
            "api_temp",
            "amedas_temp",
            " C",
        ),
        "湿度 MAE": (
            "api_humidity",
            "amedas_humidity",
            " %",
        ),
        "風速 MAE": (
            "api_wind",
            "amedas_wind",
            " m/s",
        ),
    }

    for title, (api_key, amedas_key, unit) in metrics.items():
        ranking = []

        for source in API_SOURCES:
            value, count = calculate_mae(
                grouped[source],
                api_key,
                amedas_key,
            )

            if value is not None:
                ranking.append(
                    (value, source, count)
                )

        ranking.sort()

        print()
        print(f"--- {title} ---")

        for rank, (value, source, count) in enumerate(
            ranking,
            start=1,
        ):
            print(
                f"  {rank}. {source:<16} "
                f"{value:.3f}{unit} (n={count})"
            )

    freshness_ranking = []

    for source in API_SOURCES:
        value = calculate_time_gap(
            grouped[source]
        )

        if value is not None:
            freshness_ranking.append(
                (value, source)
            )

    freshness_ranking.sort()

    print()
    print("--- 観測時刻差 ---")

    for rank, (value, source) in enumerate(
        freshness_ranking,
        start=1,
    ):
        print(
            f"  {rank}. {source:<16} "
            f"{value:.3f} min"
        )

    print()
    print("--- 降水 ---")
    print(
        "  ソースごとに降水の観測時間幅が異なるため、"
        "ランキングは表示しません。"
    )
    print(
        "  降水一致率と雨の当たり方・見逃し分析は"
        "参考値として扱います。"

    )

def main():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row

    rows = load_comparisons(con)

    grouped = defaultdict(list)

    for row in rows:
        grouped[row["source"]].append(row)

    print("=== API と AMeDAS の全体比較 ===")
    print(f"データベース: {DB_PATH}")
    print(f"比較対象行数: {len(rows)}")

    for source in API_SOURCES:
        source_rows = grouped[source]

        print()
        print(f"--- {source} ---")
        print(f"  比較件数             : {len(source_rows)}")

        temp_mae, temp_n = calculate_mae(
            source_rows,
            "api_temp",
            "amedas_temp",
        )

        temp_bias = calculate_bias(
            source_rows,
            "api_temp",
            "amedas_temp",
        )

        humidity_mae, humidity_n = calculate_mae(
            source_rows,
            "api_humidity",
            "amedas_humidity",
        )

        humidity_bias = calculate_bias(
            source_rows,
            "api_humidity",
            "amedas_humidity",
        )

        wind_mae, wind_n = calculate_mae(
            source_rows,
            "api_wind",
            "amedas_wind",
        )

        wind_bias = calculate_bias(
            source_rows,
            "api_wind",
            "amedas_wind",
        )

        rain_agreement, rain_n = calculate_rain_agreement(source_rows)

        time_gap = calculate_time_gap(source_rows)

        print_metric("気温 MAE", temp_mae, temp_n, " C")
        print_metric("気温 bias", temp_bias, unit=" C")

        print_metric(
            "湿度 MAE",
            humidity_mae,
            humidity_n,
            " %",
        )
        print_metric(
            "湿度 bias",
            humidity_bias,
            unit=" %",
        )

        print_metric("風速 MAE", wind_mae, wind_n, " m/s")
        print_metric("風速 bias", wind_bias, unit=" m/s")

        print_metric(
            "降水一致率",
            rain_agreement,
            rain_n,
            " %",
        )

        print_metric(
            "観測時刻差",
            time_gap,
            unit=" min",
        )

    print_city_comparison(rows)
    print_availability(con)
    print_precipitation_definitions(con)
    print_rain_confusion_analysis(rows)
    print_overall_summary(rows)

    con.close()


if __name__ == "__main__":
    main()