#!/usr/bin/env python3
"""Normalize agent search dates into a UTC half-open interval. Read-only."""
import argparse
from datetime import date, datetime, time, timedelta, timezone
import json
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def normalize(args):
    zone = ZoneInfo(args.timezone)
    if args.last_days is not None:
        if args.last_days < 1:
            raise ValueError("--last-days must be positive")
        now = datetime.fromisoformat(args.now) if args.now else datetime.now(timezone.utc)
        if now.utcoffset() is None:
            raise ValueError("--now requires a timezone offset")
        until = now.astimezone(timezone.utc)
        start = until - timedelta(days=args.last_days)
        first_day = start.astimezone(zone).date()
        last_day = until.astimezone(zone).date()
    else:
        if args.now:
            raise ValueError("--now is only valid with --last-days")
        if args.on:
            if args.to:
                raise ValueError("--to is only valid with --from")
            first_day = last_day = date.fromisoformat(args.on)
        else:
            if not args.to:
                raise ValueError("--from requires --to")
            first_day, last_day = date.fromisoformat(args.from_date), date.fromisoformat(args.to)
        if first_day > last_day:
            raise ValueError("--from must not be after --to")
        start = datetime.combine(first_day, time.min, zone).astimezone(timezone.utc)
        until = datetime.combine(last_day + timedelta(days=1), time.min, zone).astimezone(timezone.utc)
    # The host groups by best event before returning results; exclude the boundary in SQL.
    inclusive = until - timedelta(microseconds=1)
    inclusive = inclusive.replace(microsecond=(inclusive.microsecond // 1000) * 1000)
    return {"from": start.isoformat().replace("+00:00", "Z"),
            "until": until.isoformat().replace("+00:00", "Z"),
            "until_inclusive_ms": inclusive.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "end_exclusive": True, "timezone": args.timezone,
            "date_from": first_day.isoformat(), "date_to": last_day.isoformat()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--on", metavar="YYYY-MM-DD")
    mode.add_argument("--from", dest="from_date", metavar="YYYY-MM-DD")
    mode.add_argument("--last-days", type=int, metavar="N")
    parser.add_argument("--to", metavar="YYYY-MM-DD")
    parser.add_argument("--timezone", default="UTC", help="IANA zone; default UTC, never guessed")
    parser.add_argument("--now", help="Offset-qualified ISO timestamp for reproducible relative searches")
    args = parser.parse_args()
    if args.last_days is not None and args.to:
        parser.error("--to is only valid with --from")
    try:
        result = normalize(args)
    except (ValueError, OverflowError, ZoneInfoNotFoundError) as error:
        parser.error(str(error))
    print(json.dumps(result))


if __name__ == "__main__":
    main()
