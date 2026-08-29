#!/usr/bin/env python3
"""Utilization gate for SPECTRUM SENTRY CI.

Parses Vivado report_utilization output; fails the pipeline if any major
category exceeds 80% (spec Section 5.8 gate #3).
Usage: python ci/gates/util_gate.py build/
"""
import re
import sys
from pathlib import Path

LIMIT = 0.80
CATEGORIES = {
    "CLB LUTs": re.compile(r"^\|\s*CLB LUTs\s*\|\s*(\d+)"),
    "CLB Registers": re.compile(r"^\|\s*CLB Registers\s*\|\s*(\d+)"),
    "Block RAM Tile": re.compile(r"^\|\s*Block RAM Tile\s*\|\s*[\d.]+\s*\|.*?\|\s*([\d.]+)"),
    "DSPs": re.compile(r"^\|\s*DSPs\s*\|\s*(\d+)"),
}


def parse_report(path: Path) -> dict:
    """Return {category: (used, available)} from a utilization report."""
    results = {}
    lines = path.read_text().splitlines()
    for i, line in enumerate(lines):
        for cat, pat in CATEGORIES.items():
            if cat in results:
                continue
            if pat.match(line):
                nums = re.findall(r"[\d,]+", line)
                nums = [int(n.replace(",", "")) for n in nums]
                if len(nums) >= 2:
                    results[cat] = (nums[0], nums[1])
    return results


def main() -> int:
    build_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "build")
    reports = sorted(build_dir.glob("*_util_impl.rpt"))
    if not reports:
        print("FAIL: no implementation utilization reports found")
        return 1

    failed = False
    for rpt in reports:
        for cat, (used, avail) in parse_report(rpt).items():
            frac = used / avail if avail else 1.0
            status = "PASS" if frac < LIMIT else "FAIL"
            print(f"{status}: {rpt.name} {cat}: {used}/{avail} ({frac:.0%})")
            if frac >= LIMIT:
                failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
