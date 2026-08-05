#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Summarize an optional eRISCV testbench performance-profile CSV trace."""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="CSV from +perf_profile_trace")
    parser.add_argument("--event-prefix", default="", help="only events with this prefix")
    parser.add_argument("--top", type=int, default=10, help="PCs per event (default: 10)")
    return parser.parse_args()


def parse_hex(value: str, field: str, row_number: int) -> int:
    try:
        return int(value, 16)
    except ValueError as exc:
        raise ValueError(f"row {row_number}: invalid {field} {value!r}") from exc


def main() -> int:
    args = parse_args()
    if args.top < 1:
        raise SystemExit("--top must be positive")

    events: Counter[str] = Counter()
    event_pcs: defaultdict[str, Counter[int]] = defaultdict(Counter)
    with args.trace.open(newline="", encoding="utf-8") as trace_file:
        reader = csv.DictReader(trace_file)
        required = {"cycle", "event", "pc", "value0", "value1"}
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise SystemExit(f"{args.trace}: expected columns {', '.join(sorted(required))}")
        for row_number, row in enumerate(reader, start=2):
            event = row["event"]
            if not event.startswith(args.event_prefix):
                continue
            pc = parse_hex(row["pc"], "pc", row_number)
            events[event] += 1
            event_pcs[event][pc] += 1

    print(f"trace={args.trace} event_prefix={args.event_prefix or '<all>'}")
    print(f"events={sum(events.values())} event_kinds={len(events)}")
    for event, count in events.most_common():
        print(f"{event}: count={count}")
        for pc, pc_count in event_pcs[event].most_common(args.top):
            print(f"  pc=0x{pc:08x} count={pc_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
