from __future__ import annotations

import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


API_COMPARISON_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(API_COMPARISON_DIR))

from compare import (  # noqa: E402
    API_SOURCES,
    calculate_freshness,
    calculate_mae,
    calculate_rain_confusion,
    common_comparisons,
    load_availability,
    load_comparisons,
    open_database,
)


class ComparisonTest(unittest.TestCase):
    def setUp(self):
        self.con = sqlite3.connect(":memory:")
        self.con.row_factory = sqlite3.Row
        self.con.execute("""
            CREATE TABLE observations (
                source TEXT, city TEXT, point_role TEXT, target_time TEXT,
                source_time TEXT, fetched_at TEXT, success INTEGER,
                temperature_c REAL, humidity_pct REAL, wind_speed_ms REAL,
                rain_detected INTEGER,
                UNIQUE(source, city, point_role, target_time)
            )
        """)
        self.addCleanup(self.con.close)

    def insert(self, source, slot="2026-09-17T13:00:00+09:00", **changes):
        row = {
            "source": source, "city": "tokyo", "point_role": "primary",
            "target_time": slot, "source_time": slot,
            "fetched_at": "2026-09-17T13:05:00+09:00", "success": 1,
            "temperature_c": 20, "humidity_pct": 60, "wind_speed_ms": 2,
            "rain_detected": 0,
        }
        row.update(changes)
        self.con.execute(
            f"INSERT INTO observations ({', '.join(row)}) "
            f"VALUES ({', '.join('?' for _ in row)})", tuple(row.values()),
        )

    def test_availability_includes_reference_failures_and_separates_unrecorded(self):
        self.insert("amedas")
        self.insert("open_meteo", temperature_c=0, rain_detected=None)
        self.insert("amedas", slot="second", success=0)
        self.insert("open_meteo", slot="second", success=0)
        self.insert("amedas", slot="third")

        result = load_availability(self.con, "open_meteo")
        self.assertEqual(result["expected"], 3)
        self.assertEqual(result["recorded"], 2)
        self.assertEqual(result["successful"], 1)
        self.assertEqual(result["failed"], 1)
        self.assertEqual(result["unrecorded"], 1)
        self.assertEqual(result["missing"]["temperature_c"], 0)
        self.assertEqual(result["missing"]["rain_detected"], 1)

    def test_empty_availability_does_not_invent_success_or_zero_weather(self):
        result = load_availability(self.con, "open_meteo")
        self.assertEqual(result["expected"], 0)
        self.assertEqual(result["recorded"], 0)
        self.assertEqual(result["successful"], 0)

    def test_join_requires_success_and_same_point_role(self):
        self.insert("amedas")
        self.insert("open_meteo", point_role="wind")
        self.insert("tomorrow_io", success=0)
        self.insert("openweather")
        self.insert("amedas", slot="second", success=0)
        self.insert("openweather", slot="second")
        rows = load_comparisons(self.con)
        self.assertEqual([row["source"] for row in rows], ["openweather"])

    def test_common_samples_require_all_sources_and_metric_values(self):
        self.insert("amedas")
        for source in API_SOURCES:
            self.insert(source, rain_detected=None if source == "visual_crossing" else 0)
        self.insert("amedas", slot="second")
        self.insert("open_meteo", slot="second")
        rows = load_comparisons(self.con)
        self.assertEqual(len(rows), 5)
        self.assertEqual(len(common_comparisons(rows)), 4)
        self.assertEqual(len(common_comparisons(rows, ("api_temp", "amedas_temp"))), 4)
        self.assertEqual(common_comparisons(rows, ("api_rain", "amedas_rain")), [])

    def test_common_samples_do_not_mix_point_roles(self):
        rows = [
            {"source": source, "city": "tokyo", "target_time": "same",
             "point_role": "wind" if i == 0 else "primary"}
            for i, source in enumerate(API_SOURCES)
        ]
        self.assertEqual(common_comparisons(rows), [])

    def test_missing_values_are_excluded_but_zero_is_evaluated(self):
        rows = [
            {"api_temp": 0, "amedas_temp": 1, "api_rain": 0, "amedas_rain": 1},
            {"api_temp": None, "amedas_temp": 5, "api_rain": None, "amedas_rain": 1},
        ]
        self.assertEqual(calculate_mae(rows, "api_temp", "amedas_temp"), (1, 1))
        result = calculate_rain_confusion(rows)
        self.assertEqual(result["evaluated"], 1)
        self.assertEqual(result["fn"], 1)
        self.assertIsNone(result["precision"])
        self.assertEqual(result["recall"], 0)

    def test_freshness_uses_signed_age_with_offsets_and_missing_times(self):
        rows = [
            {"fetched_at": "2026-09-17T13:05:00+09:00", "source_time": "2026-09-17T04:00:00Z"},
            {"fetched_at": "2026-09-17T04:00:00Z", "source_time": "2026-09-17T04:01:00Z"},
            {"fetched_at": "2026-09-17T04:00:00Z", "source_time": None},
            {"fetched_at": "bad", "source_time": "2026-09-17T04:00:00Z"},
            {"fetched_at": "2026-09-17T04:00:00", "source_time": "2026-09-17T04:00:00Z"},
        ]
        self.assertEqual(calculate_freshness(rows), {
            "count": 2, "missing": 3, "mean": 2, "max": 5, "negative": 1,
        })

    def test_read_only_connection_rejects_writes_and_does_not_create_missing_db(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "comparison.db"
            with self.assertRaises(sqlite3.OperationalError):
                open_database(path)
            self.assertFalse(path.exists())
            sqlite3.connect(path).close()
            con = open_database(path)
            try:
                with self.assertRaises(sqlite3.OperationalError):
                    con.execute("CREATE TABLE unexpected (value INTEGER)")
            finally:
                con.close()


if __name__ == "__main__":
    unittest.main()
