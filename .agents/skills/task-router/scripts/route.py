#!/usr/bin/env python3
"""
Task Router — Local, zero-key, zero-hallucination task and risk classifier.
Analyzes user task prompts, git changes, and file paths to determine:
- Model Tier: flash_lite | flash | pro
- Risk Level: low | medium | critical
- Strategy: direct | review | plan_required
"""

import sys
import os
import json
import re
import subprocess
from pathlib import Path

# --- Default Heuristics (can be overridden via .task-router.json) ---

DEFAULT_CRITICAL_PATH_PATTERNS = [
    r"Audio/",
    r"CoreAudio",
    r"RenderCallback",
    r"RingBuffer",
    r"vDSP",
    r"stdatomic",
    r"BiquadFilterVDSP",
    r"IPCServer",
    r"driver",
    r"security",
    r"crypto",
    r"auth",
    r"migration",
]

DEFAULT_LOW_PATH_PATTERNS = [
    r"\.md$",
    r"\.txt$",
    r"\.json$",
    r"\.ya?ml$",
    r"\.xcstrings$",
    r"\.strings$",
    r"Assets/",
    r"Images/",
    r"\.gitignore$",
]

DEFAULT_CRITICAL_KEYWORDS = [
    r"\barchitecture\b",
    r"\brefactor\b",
    r"\block-free\b",
    r"\brace condition\b",
    r"\bdeadlock\b",
    r"\bhot path\b",
    r"\bmemory leak\b",
    r"\brender callback\b",
    r"\bcoreaudio\b",
    r"\bvdsp\b",
    r"\batomic\b",
    r"\bcrash\b",
    r"\bsegfault\b",
]

DEFAULT_LOW_KEYWORDS = [
    r"\btypo\b",
    r"\brename\b",
    r"\bformat\b",
    r"\blint\b",
    r"\bcomment\b",
    r"\bdocs?\b",
    r"\breadme\b",
    r"\btranslation\b",
    r"\btranslate\b",
    r"\bпереклад\b",
    r"\bодрук\b",
    r"\bкоментар\b",
]


def load_project_config():
    """Look for .task-router.json in current directory or git root."""
    search_dirs = [Path.cwd()]
    try:
        git_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True
        ).strip()
        if git_root:
            search_dirs.append(Path(git_root))
    except Exception:
        pass

    for d in search_dirs:
        cfg = d / ".task-router.json"
        if cfg.is_file():
            try:
                with open(cfg, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
    return {}


def get_git_status_files():
    """Get list of modified, staged, or untracked files from git."""
    try:
        out = subprocess.check_output(
            ["git", "status", "--porcelain"],
            stderr=subprocess.DEVNULL,
            text=True
        )
        files = []
        for line in out.splitlines():
            line = line.strip()
            if not line:
                continue
            # Format: 'M file.swift' or '?? file.swift' or 'R  old -> new'
            parts = line.split(maxsplit=1)
            if len(parts) == 2:
                path = parts[1]
                if " -> " in path:
                    path = path.split(" -> ")[1]
                files.append(path.strip('"'))
        return files
    except Exception:
        return []


def extract_paths_from_text(text):
    """Find any file paths mentioned directly in the prompt text."""
    # Match strings like path/to/file.ext or file.swift
    candidates = re.findall(r'[a-zA-Z0-9_\-\.\/]+\.[a-zA-Z0-9]+', text)
    return [c.strip(".,;:()") for c in candidates]


def classify(prompt="", explicit_files=None, ignore_git=False):
    cfg = load_project_config()

    critical_paths = cfg.get("critical_paths", DEFAULT_CRITICAL_PATH_PATTERNS)
    low_paths = cfg.get("low_paths", DEFAULT_LOW_PATH_PATTERNS)
    critical_kw = cfg.get("critical_keywords", DEFAULT_CRITICAL_KEYWORDS)
    low_kw = cfg.get("low_keywords", DEFAULT_LOW_KEYWORDS)

    reasons = []

    # If explicit files not given, check prompt for mentioned files
    prompt_mentioned_files = extract_paths_from_text(prompt)
    
    if explicit_files is not None:
        files_to_check = explicit_files
    elif prompt_mentioned_files:
        files_to_check = prompt_mentioned_files
        reasons.append(f"Знайдено згадані файли у запиті: {', '.join(prompt_mentioned_files)}")
    elif not ignore_git:
        files_to_check = get_git_status_files()
    else:
        files_to_check = []

    # Check for explicit or modified files
    has_critical_file = False
    has_only_low_files = True if files_to_check else False

    matched_critical_files = []
    matched_low_files = []

    for f in files_to_check:
        is_crit = any(re.search(pat, f, re.IGNORECASE) for pat in critical_paths)
        is_low = any(re.search(pat, f, re.IGNORECASE) for pat in low_paths)

        if is_crit:
            has_critical_file = True
            matched_critical_files.append(f)
            has_only_low_files = False
        elif not is_low:
            has_only_low_files = False
        else:
            matched_low_files.append(f)

    if has_critical_file:
        reasons.append(f"Критичний шлях (Hot Path/CoreAudio): {', '.join(matched_critical_files)}")

    # Check prompt keywords
    prompt_crit_matches = [kw for kw in critical_kw if re.search(kw, prompt, re.IGNORECASE)]
    prompt_low_matches = [kw for kw in low_kw if re.search(kw, prompt, re.IGNORECASE)]

    if prompt_crit_matches:
        reasons.append(f"Критичні ключові слова в запиті: {', '.join(prompt_crit_matches)}")

    # Decision Matrix
    if has_critical_file or prompt_crit_matches:
        tier = "pro"
        risk = "critical"
        score = 5 if (has_critical_file and prompt_crit_matches) else 4
        strategy = "plan_required"
        confidence = 0.98 if has_critical_file else 0.92
    elif (has_only_low_files and not prompt_crit_matches) or (prompt_low_matches and not files_to_check):
        tier = "flash_lite"
        risk = "low"
        score = 1
        strategy = "direct"
        confidence = 0.95
        if matched_low_files:
            reasons.append(f"Лише низькоризикові файли: {', '.join(matched_low_files)}")
        if prompt_low_matches:
            reasons.append(f"Низькоризиковий запит: {', '.join(prompt_low_matches)}")
    else:
        # Default standard tier (fail-safe middle ground)
        tier = "flash"
        risk = "medium"
        score = 3
        strategy = "review"
        confidence = 0.88
        reasons.append("Стандартна задача кодингу / розробки")

    return {
        "tier": tier,
        "score": score,
        "risk": risk,
        "confidence": confidence,
        "strategy": strategy,
        "suggested_subagent_model": tier,
        "detected_files": files_to_check,
        "reasons": reasons
    }


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Task Router — Local zero-key classifier")
    parser.add_argument("prompt", nargs="?", default="", help="Task prompt or description")
    parser.add_argument("--files", help="Comma-separated list of target files")
    parser.add_argument("--no-git", action="store_true", help="Ignore git status, evaluate prompt only")
    parser.add_argument("--json", action="store_true", default=True, help="Output pure JSON (default)")
    parser.add_argument("--pretty", action="store_true", help="Output human-readable summary")

    args = parser.parse_args()

    explicit_files = args.files.split(",") if args.files else None
    result = classify(args.prompt, explicit_files, ignore_git=args.no_git)

    if args.pretty:
        print(f"🎯 Рівень моделі: {result['tier'].upper()} (бал: {result['score']}/5)")
        print(f"⚠️  Рівень ризику: {result['risk'].upper()}")
        print(f"📋 Стратегія:    {result['strategy']}")
        print(f"🔒 Впевненість:  {result['confidence'] * 100:.0f}%")
        print("💡 Причини:")
        for r in result["reasons"]:
            print(f"   - {r}")
    else:
        print(json.dumps(result, ensure_ascii=False, indent=2))



if __name__ == "__main__":
    main()
