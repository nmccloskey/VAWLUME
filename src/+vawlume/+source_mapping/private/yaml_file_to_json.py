"""Convert a YAML file to JSON for the MATLAB profile loader."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: yaml_file_to_json.py <profile.yaml>", file=sys.stderr)
        return 64

    profile_path = Path(sys.argv[1])
    try:
        with profile_path.open("r", encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
        json.dump(data, sys.stdout, ensure_ascii=True, sort_keys=False)
        return 0
    except Exception as exc:  # pragma: no cover - exercised through MATLAB.
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
