#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parent.parent
    result = subprocess.run(
        ["git", "ls-files", "-z", "-co", "--exclude-standard"],
        cwd=root, check=True, stdout=subprocess.PIPE,
    )
    files = sorted(set(os.fsdecode(name) for name in result.stdout.split(b"\0") if name))
    for name in files:
        path = root / name
        if path.suffix == ".py":
            compile(path.read_bytes(), name, "exec", dont_inherit=True)
        elif path.suffix == ".sh" or name == ".githooks/pre-commit":
            subprocess.run(["bash", "-n", str(path)], check=True)
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    subprocess.run(
        [sys.executable, ".agents/skills/task-router/scripts/test_route.py"],
        cwd=root, env=env, check=True,
    )
    subprocess.run([sys.executable, "Scripts/test_code_quality.py"], cwd=root, env=env, check=True)


if __name__ == "__main__":
    main()
