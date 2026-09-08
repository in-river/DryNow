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


def main():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row

    rows = load_comparisons(con)

    grouped = defaultdict(list)

    for row in rows:
        grouped[row["source"]].append(row)

    print("=== API vs AMeDAS Comparison ===")
    print(f"Database: {DB_PATH}")
    print(f"Comparison rows: {len(rows)}")

    for source in API_SOURCES:
        source_rows = grouped[source]

        print()
        print(f"--- {source} ---")
        print(f"  paired rows         : {len(source_rows)}")

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

        print_metric("temperature MAE", temp_mae, temp_n, " C")
        print_metric("temperature bias", temp_bias, unit=" C")

        print_metric(
            "humidity MAE",
            humidity_mae,
            humidity_n,
            " %",
        )
        print_metric(
            "humidity bias",
            humidity_bias,
            unit=" %",
        )

        print_metric("wind MAE", wind_mae, wind_n, " m/s")
        print_metric("wind bias", wind_bias, unit=" m/s")

        print_metric(
            "rain agreement",
            rain_agreement,
            rain_n,
            " %",
        )

        print_metric(
            "source time gap",
            time_gap,
            unit=" min",
        )

    con.close()


if __name__ == "__main__":
    main()