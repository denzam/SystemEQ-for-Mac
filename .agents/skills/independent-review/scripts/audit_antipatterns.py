#!/usr/bin/env python3
"""
audit_antipatterns.py
Швидкий локальний сканер антипатернів Defensive Theater, Fail-Closed та надійності скриптів.
Використовується навичкою independent-review для швидкого виявлення очевидних дефектів.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

ANTIPATTERNS = [
    {
        "id": "DEFENSIVE_THEATER_PIPE",
        "description": "Глушіння помилок через '|| true'",
        "regex": re.compile(r"(?<!#)\b\|\|\s*true\b"),
        "extensions": [".sh", ".bash", ".zsh"],
        "severity": "High",
    },
    {
        "id": "DEFENSIVE_THEATER_STDERR",
        "description": "Перенаправлення '2>/dev/null' без перевірки статусу",
        # Flag 2>/dev/null unless in an 'if' / 'while' condition or followed by explicit error handling
        "regex": re.compile(r"^(?!\s*(?:if|while|until)\b).*2>/dev/null\s*(?:\|\||;|$)", re.MULTILINE),
        "extensions": [".sh", ".bash", ".zsh"],
        "severity": "High",
    },
    {
        "id": "EXCEPT_PASS",
        "description": "Порожній блок 'except Exception: pass' або 'except: pass'",
        "regex": re.compile(r"except(?:\s+[A-Za-z0-9_]+)?:\s*pass"),
        "extensions": [".py"],
        "severity": "Medium",
    },
    {
        "id": "LOCAL_MASKING",
        "description": "Маскування exit code через 'local var=$(...)'",
        "regex": re.compile(r"^\s*local\s+[a-zA-Z0-9_]+=\$\("),
        "extensions": [".sh", ".bash", ".zsh"],
        "severity": "Medium",
    },
    {
        "id": "SUDO_HANG",
        "description": "Виклик 'sudo' без '-n' або перевірки наявності tty",
        "regex": re.compile(r"^\s*sudo\s+(?!-n\b)"),
        "extensions": [".sh", ".bash", ".zsh"],
        "severity": "Medium",
    },
]


def get_tracked_files(repo_root: Path):
    try:
        res = subprocess.run(
            ["git", "ls-files"],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            check=True,
        )
        return [repo_root / f for f in res.stdout.splitlines()]
    except Exception:
        # Fallback to walk if git not available
        files = []
        for root, _, filenames in os.walk(repo_root):
            if ".git" in root or "DerivedData" in root or "build" in root:
                continue
            for f in filenames:
                files.append(Path(root) / f)
        return files


def audit_repository(repo_root: Path):
    files = get_tracked_files(repo_root)
    findings = []

    for file_path in files:
        if not file_path.is_file():
            continue

        ext = file_path.suffix.lower()
        active_rules = [r for r in ANTIPATTERNS if ext in r["extensions"]]
        if not active_rules:
            continue

        # Skip this script itself
        if file_path.name == "audit_antipatterns.py":
            continue

        try:
            with open(file_path, "r", encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
        except Exception:
            continue

        for idx, line in enumerate(lines, start=1):
            for rule in active_rules:
                if rule["regex"].search(line):
                    findings.append({
                        "file": str(file_path.relative_to(repo_root)),
                        "line": idx,
                        "text": line.strip(),
                        "rule": rule,
                    })

    return findings


def find_repo_root(start_path: Path) -> Path:
    current = start_path.resolve()
    for parent in [current] + list(current.parents):
        if (parent / ".git").is_dir():
            return parent
    return start_path.resolve().parents[4]


def main():
    repo_root = find_repo_root(Path(__file__))
    if len(sys.argv) > 1 and sys.argv[1] != "--check":
        repo_root = Path(sys.argv[1]).resolve()

    print(f"🔍 Запуск аудиту антипатернів у: {repo_root}")
    findings = audit_repository(repo_root)

    if not findings:
        print("✅ Антипатернів Defensive Theater чи глушіння помилок не виявлено.")
        sys.exit(0)

    print(f"⚠️  Знайдено {len(findings)} потенційних дефектів:")
    for f in findings:
        print(
            f"  [{f['rule']['severity']}] {f['file']}:{f['line']} - "
            f"{f['rule']['description']}\n    Рядок: {f['text']}"
        )

    # If --check flag is passed, exit with error code if findings exist
    if "--check" in sys.argv:
        sys.exit(1)


if __name__ == "__main__":
    main()
