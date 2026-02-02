#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
from pathlib import Path


def parse_args() -> tuple[str, int]:
    parser = argparse.ArgumentParser(description="Run ralph.sh with optional tool and iteration count.")
    parser.add_argument("max_iterations", nargs="?", type=int, default=20, help="Number of iterations (default: 20)")
    parser.add_argument(
        "--tool",
        choices=["opencode", "amp", "claude"],
        default="opencode",
        help="AI tool to use (default: opencode)",
    )
    args = parser.parse_args()
    return args.tool, args.max_iterations


def main() -> int:
    tool, max_iterations = parse_args()
    script_dir = Path(__file__).resolve().parent
    ralph_sh = script_dir / "ralph.sh"

    if not ralph_sh.exists():
        print(f"Missing ralph.sh at {ralph_sh}", file=sys.stderr)
        return 1

    env = os.environ.copy()
    if "DEST_REPO" not in env:
        env["DEST_REPO"] = os.getcwd()

    cmd = [str(ralph_sh), "--tool", tool, str(max_iterations)]
    print(f"Running: {' '.join(cmd)} with DEST_REPO={env['DEST_REPO']}")
    result = subprocess.run(cmd, cwd=script_dir, env=env)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
