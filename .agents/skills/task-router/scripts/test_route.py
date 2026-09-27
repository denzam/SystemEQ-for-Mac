#!/usr/bin/env python3
"""
Regression and unit tests for Task Router.
Covers:
- Ukrainian & English keyword detection
- Risk levels and strategy selection
- Provider-independent tier output
- File path heuristics
- Whitespace formatting sanity check
"""

import os
import re
import unittest
from pathlib import Path

# Add scripts directory to path
SCRIPTS_DIR = Path(__file__).resolve().parent
import sys
sys.path.insert(0, str(SCRIPTS_DIR))

import route


class TestTaskRouter(unittest.TestCase):

    def test_ukrainian_critical_keywords(self):
        prompts = [
            "рефакторинг аудіо-буфера",
            "рефакторинг кільцевого буфера",
            "витік пам'яті в render callback",
            "стан гонки при зміні аудіо-пристрою",
            "взаємне блокування в IPC",
            "дедлок у потоці обробки",
            "краш при зміні пресету",
            "падіння застосунку на старті",
            "оптимізація гарячого шляху обробки",
            "атомарні операції для atomic int",
        ]
        for p in prompts:
            with self.subTest(prompt=p):
                res = route.classify(prompt=p, ignore_git=True)
                self.assertEqual(res["risk"], "critical", f"Failed critical risk for prompt: {p}")
                self.assertEqual(res["strategy"], "plan_required", f"Failed strategy for prompt: {p}")
                self.assertEqual(res["tier"], "reasoning", f"Failed tier for prompt: {p}")

    def test_english_critical_keywords(self):
        prompts = [
            "refactor audio buffer",
            "race condition in ring buffer",
            "deadlock in IPCServer",
            "memory leak in render callback",
            "crash on device unplug",
        ]
        for p in prompts:
            with self.subTest(prompt=p):
                res = route.classify(prompt=p, ignore_git=True)
                self.assertEqual(res["risk"], "critical", f"Failed critical risk for prompt: {p}")
                self.assertEqual(res["strategy"], "plan_required", f"Failed strategy for prompt: {p}")
                self.assertEqual(res["tier"], "reasoning", f"Failed tier for prompt: {p}")

    def test_low_risk_keywords(self):
        prompts = [
            "виправити одрук у документації",
            "додати переклад для нових кнопок",
            "оновити коментар у коді",
            "fix typo in readme",
            "update translation strings",
        ]
        for p in prompts:
            with self.subTest(prompt=p):
                res = route.classify(prompt=p, ignore_git=True)
                self.assertEqual(res["risk"], "low", f"Failed low risk for prompt: {p}")
                self.assertEqual(res["strategy"], "direct", f"Failed direct strategy for prompt: {p}")
                self.assertEqual(res["tier"], "fast", f"Failed fast tier for prompt: {p}")

    def test_medium_risk_standard_task(self):
        prompt = "додати кнопку налаштувань у меню"
        res = route.classify(prompt=prompt, ignore_git=True)
        self.assertEqual(res["risk"], "medium")
        self.assertEqual(res["strategy"], "review")
        self.assertEqual(res["tier"], "standard")

    def test_explicit_critical_files(self):
        res = route.classify(explicit_files=["Audio/CoreAudioEngine.swift"], ignore_git=True)
        self.assertEqual(res["risk"], "critical")
        self.assertEqual(res["strategy"], "plan_required")
        self.assertEqual(res["tier"], "reasoning")

    def test_explicit_low_files(self):
        res = route.classify(explicit_files=["README.md", "Docs/ARCHITECTURE.md"], ignore_git=True)
        self.assertEqual(res["risk"], "low")
        self.assertEqual(res["strategy"], "direct")
        self.assertEqual(res["tier"], "fast")

    def test_provider_independent_schema(self):
        res = route.classify("будь-яка задача", ignore_git=True)
        # Check provider-independent tier
        self.assertIn(res["tier"], ["fast", "standard", "reasoning"])
        # Ensure fake model name field is absent
        self.assertNotIn("suggested_subagent_model", res)
        # Verify required keys exist
        expected_keys = {"tier", "score", "risk", "confidence", "strategy", "detected_files", "reasons"}
        self.assertTrue(expected_keys.issubset(res.keys()))

    def test_no_trailing_whitespace_in_route_py(self):
        route_py_path = SCRIPTS_DIR / "route.py"
        with open(route_py_path, "r", encoding="utf-8") as f:
            for i, line in enumerate(f, 1):
                raw = line.rstrip("\r\n")
                self.assertEqual(raw, raw.rstrip(), f"Trailing whitespace found on line {i} in {route_py_path}")


if __name__ == "__main__":
    unittest.main()
