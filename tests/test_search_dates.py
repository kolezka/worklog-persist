"""Date bounds shared by Outline and conversation searches."""
import json
from pathlib import Path
import subprocess
import sys

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/search_dates.py"


def run(*args):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True)


def bounds(*args):
    result = run(*args)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_inclusive_day_across_dst():
    result = bounds("--on", "2026-03-29", "--timezone", "Europe/Warsaw")
    assert result["from"] == "2026-03-28T23:00:00Z"
    assert result["until"] == "2026-03-29T22:00:00Z"


def test_inclusive_range():
    result = bounds("--from", "2026-11-01", "--to", "2026-11-03", "--timezone", "UTC")
    assert result["from"] == "2026-11-01T00:00:00Z"
    assert result["until"] == "2026-11-04T00:00:00Z"
    assert result["date_from"] == "2026-11-01"
    assert result["date_to"] == "2026-11-03"


def test_last_seven_days_is_elapsed_time():
    result = bounds("--last-days", "7", "--now", "2026-03-30T12:00:00+02:00", "--timezone", "Europe/Warsaw")
    assert result["from"] == "2026-03-23T10:00:00Z"
    assert result["until"] == "2026-03-30T10:00:00Z"
    assert result["end_exclusive"] is True


def test_upper_bound_is_next_local_day_in_autumn():
    result = bounds("--on", "2026-10-25", "--timezone", "Europe/Warsaw")
    assert result["from"] == "2026-10-24T22:00:00Z"
    assert result["until"] == "2026-10-25T23:00:00Z"


def test_default_timezone_is_explicit_utc():
    assert bounds("--on", "2026-11-09")["timezone"] == "UTC"


def test_inclusive_host_upper_bound_never_selects_exclusive_boundary():
    result = bounds("--on", "2026-11-09")
    assert result["until_inclusive_ms"] == "2026-11-09T23:59:59.999Z"
    fractional = bounds("--last-days", "7", "--now", "2026-11-09T12:00:00.123456Z")
    assert fractional["until_inclusive_ms"] == "2026-11-09T12:00:00.123Z"


def test_bad_input_fails_without_bounds():
    cases = [[], ["--on", "2026-02-30"], ["--from", "2026-11-03"],
             ["--from", "2026-11-03", "--to", "2026-11-01"],
             ["--last-days", "0"], ["--last-days", "-1"],
             ["--on", "2026-11-09", "--last-days", "7"],
             ["--on", "2026-11-09", "--timezone", "Not/AZone"],
             ["--last-days", "7", "--now", "2026-11-09T12:00:00"]]
    for args in cases:
        result = run(*args)
        assert result.returncode == 2, args
        assert not result.stdout, args
        assert "error:" in result.stderr, args
