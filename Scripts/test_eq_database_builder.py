#!/usr/bin/env python3
import hashlib
import json
import os
from contextlib import closing
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
import textwrap
import unittest


@unittest.skipUnless(sys.platform == "darwin", "Requires macOS Swift and SQLite3")
class EQDatabaseBuilderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parent.parent
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-database-builder-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        cls.builder = cls.compile(cls.root / "Scripts/build_eq_database.swift", "builder")
        cls.indexer = cls.compile(cls.root / "Scripts/generate_autoeq_index.swift", "indexer")

    @classmethod
    def compile(cls, source, name):
        output = cls.directory / name
        result = subprocess.run(
            ["xcrun", "swiftc", "-module-cache-path", str(cls.directory / "module-cache"), str(source), "-o", str(output)],
            capture_output=True, text=True, timeout=90,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        return output

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=self.directory)
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.autoeq = self.work / "AutoEq"
        self.inputs = self.autoeq / "results/source/over-ear/Acme Model"
        self.inputs.mkdir(parents=True)
        self.fixed = self.inputs / "Acme Model FixedBandEQ.txt"
        self.graphic = self.inputs / "Acme Model GraphicEQ.txt"
        self.parametric = self.inputs / "Acme Model ParametricEQ.txt"
        self.fixed.write_text(self.fixed_text())
        centers = [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
                   800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000]
        self.graphic.write_text("GraphicEQ: " + "; ".join(f"{f} -1" for f in centers))
        self.parametric.write_text("Preamp: -2 dB\nFilter 1: ON PK Fc 1000 Hz Gain 1 dB Q 0.7\n")
        self.entry = dict(brand="Acme", model="Model", source="source", type="over-ear")
        self.entry.update({key: str(path.relative_to(self.autoeq)) for key, path in (
            ("pathFixedBandEQ", self.fixed), ("pathGraphicEQ", self.graphic), ("pathParametric", self.parametric),
        )})
        self.index = self.work / "input.json"
        self.index.write_text(json.dumps([self.entry]))
        self.markdown = self.work / "INDEX.md"
        self.markdown.write_text("# Index\n[Acme Model](./source/over-ear/Acme%20Model)\n")
        self.database = self.work / "output.db"
        with closing(sqlite3.connect(self.database)) as db:
            db.execute("CREATE TABLE original(value TEXT)")
            db.execute("INSERT INTO original VALUES ('keep')")
            db.commit()
        self.index_output = self.work / "output.json"
        self.index_output.write_text('[{"old":true}]')

    @staticmethod
    def fixed_text(count=10):
        return "Preamp: -2 dB\n" + "\n".join(
            f"Filter {i + 1}: ON PK Fc {31.5 * 2 ** i} Hz Gain 1 dB Q 1.41" for i in range(count)
        )

    @staticmethod
    def state(path):
        return hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mtime_ns

    def run_builder(self, binary=None):
        return subprocess.run(
            [str(binary or self.builder), "--index", str(self.index), "--autoeq-root", str(self.autoeq),
             "--output", str(self.database)], cwd=self.work, capture_output=True, text=True, timeout=30,
        )

    def run_indexer(self, *arguments):
        return subprocess.run(
            [str(self.indexer), "--input", str(self.markdown), "--output", str(self.index_output), *arguments],
            cwd=self.work, capture_output=True, text=True, timeout=30,
        )

    def assert_builder_rejected(self, binary=None):
        before = self.state(self.database)
        result = self.run_builder(binary)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.state(self.database), before)
        self.assertFalse(list(self.work.glob(".EQDatabase-*")))

    def assert_indexer_rejected(self, *arguments):
        before = self.state(self.index_output)
        result = self.run_indexer(*arguments)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.state(self.index_output), before)

    def test_healthy_pipeline_validates_sql_fts_and_band_counts(self):
        result = self.run_indexer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        entries = json.loads(self.index_output.read_text())
        self.assertEqual(entries[0]["pathFixedBandEQ"], self.entry["pathFixedBandEQ"])
        self.index.write_text(json.dumps(entries))
        result = self.run_builder()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with closing(sqlite3.connect(f"file:{self.database}?mode=ro", uri=True)) as db:
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone(), ("ok",))
            self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])
            for table, count in [("presets", 1), ("fixed_band_10", 10), ("graphic_eq_31", 31), ("parametric_bands", 1)]:
                self.assertEqual(db.execute(f"SELECT count(*) FROM {table}").fetchone(), (count,))
            self.assertEqual(db.execute("SELECT brand FROM headphones_fts WHERE headphones_fts MATCH 'Acme'").fetchone(), ("Acme",))
            self.assertEqual(db.execute("SELECT value FROM metadata WHERE key='schema_version'").fetchone(), ("1",))
            self.assertEqual(db.execute("SELECT preamp_gain FROM presets").fetchone(), (-2.0,))

    def test_missing_malformed_empty_index_preserves_database(self):
        for value in (b"", b"[]", b"not json", b"\xff", b"{}"):
            with self.subTest(value=value):
                self.index.write_bytes(value)
                self.assert_builder_rejected()
        self.index.unlink()
        self.assert_builder_rejected()

    def test_missing_or_unusable_eq_preserves_database(self):
        self.fixed.unlink()
        self.graphic.unlink()
        self.assert_builder_rejected()

    def test_invalid_band_counts_and_numeric_values_preserve_database(self):
        for text in (self.fixed_text(0), self.fixed_text(9), self.fixed_text(11),
                     self.fixed_text().replace("Gain 1 ", "Gain nan "),
                     self.fixed_text().replace("Gain 1 ", "Gain 1e300 "),
                     self.fixed_text().replace("Preamp: -2", "Preamp: inf"),
                     self.fixed_text().replace("Fc 31.5", "Fc -1")):
            with self.subTest(text=text[:70]):
                self.fixed.write_text(text)
                self.assert_builder_rejected()
        self.fixed.write_bytes(b"\xff")
        self.assert_builder_rejected()

    def test_invalid_graphic_and_parametric_data_preserves_database(self):
        original = self.graphic.read_text()
        for text in ("GraphicEQ: 20 1; 20000 1", original.replace("20 -1", "20 inf"), original + "; broken"):
            with self.subTest(text=text[:50]):
                self.graphic.write_text(text)
                self.assert_builder_rejected()
        self.graphic.write_text(original)
        for value in ("0", "-1", "nan", "inf", "1e300", "invalid"):
            with self.subTest(q=value):
                self.parametric.write_text(f"Filter 1: ON PK Fc 1000 Hz Gain 1 dB Q {value}")
                self.assert_builder_rejected()

    def test_traversal_and_symlinked_input_preserve_database(self):
        for path in ("../outside.txt", "results/../../outside.txt", "/outside.txt"):
            with self.subTest(path=path):
                self.entry["pathFixedBandEQ"] = path
                self.index.write_text(json.dumps([self.entry]))
                self.assert_builder_rejected()
        outside = self.work / "outside.txt"
        outside.write_text(self.fixed_text())
        self.fixed.unlink()
        self.fixed.symlink_to(outside)
        self.entry["pathFixedBandEQ"] = str(self.fixed.relative_to(self.autoeq))
        self.index.write_text(json.dumps([self.entry]))
        self.assert_builder_rejected()

    def test_invalid_markdown_preserves_index(self):
        for value in (b"", b"\xff", b"unrelated", b"[x](./source/over-ear/Acme%ZZModel)\n",
                      b"[x](./source/over-ear/../../outside)\n", b"[x](./source/wrong/Acme%20Model)\n"):
            with self.subTest(value=value):
                self.markdown.write_bytes(value)
                self.assert_indexer_rejected()
        self.markdown.unlink()
        self.assert_indexer_rejected()

    def test_cli_errors_preserve_outputs(self):
        for binary in (self.builder, self.indexer):
            for arguments in (["--unknown"], ["--output"], ["--output", ""], ["--output", "--index"]):
                with self.subTest(binary=binary.name, arguments=arguments):
                    before = self.state(self.database), self.state(self.index_output)
                    result = subprocess.run([str(binary), *arguments], cwd=self.work, capture_output=True, text=True, timeout=10)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual((self.state(self.database), self.state(self.index_output)), before)

    def test_output_directories_and_symlinks_are_preserved(self):
        for output, command in ((self.database, self.run_builder), (self.index_output, self.run_indexer)):
            output.unlink()
            output.mkdir()
            (output / "keep").write_text("keep")
            result = command()
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((output / "keep").read_text(), "keep")
            (output / "keep").unlink()
            output.rmdir()
            target = self.work / (output.name + ".target")
            target.write_text("keep")
            output.symlink_to(target)
            result = command()
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(output.is_symlink())
            self.assertEqual(target.read_text(), "keep")

    @unittest.skipIf(os.geteuid() == 0, "Requires unprivileged write permissions")
    def test_real_write_failure_preserves_outputs(self):
        before = self.state(self.database), self.state(self.index_output)
        self.work.chmod(0o555)
        try:
            self.assertNotEqual(self.run_builder().returncode, 0)
            self.assertNotEqual(self.run_indexer().returncode, 0)
        finally:
            self.work.chmod(0o755)
        self.assertEqual((self.state(self.database), self.state(self.index_output)), before)

    def test_sqlite_prepare_step_close_and_publish_failures_preserve_database(self):
        source = (self.root / "Scripts/build_eq_database.swift").read_text()
        mutations = {
            "prepare": ("CREATE TABLE fixed_band_10 (", "CREATE TABLE missing_fixed_band_10 ("),
            "step": ("frequency REAL NOT NULL,\n            gain REAL NOT NULL,", "frequency REAL NOT NULL,\n            gain REAL NOT NULL CHECK(gain>9999),"),
            "close": ("sqlite3_close(db) == SQLITE_OK", "SQLITE_BUSY == SQLITE_OK"),
            "publish": ("Darwin.rename(dbPath, output.path)", "-1"),
        }
        for name, (old, new) in mutations.items():
            with self.subTest(failure=name):
                self.assertIn(old, source)
                path = self.work / (name + ".swift")
                path.write_text(source.replace(old, new, 1))
                binary = self.compile(path, "failure-" + name)
                self.assert_builder_rejected(binary)

    def test_workflow_rejects_empty_or_invalid_metadata_before_outputs(self):
        workflow = (self.root / ".github/workflows/update-eq-database.yml").read_text()
        match = re.search(r"(?ms)^      - name: Get database stats\n.*?^        run: \|\n(.*?)(?=^      - name:|\Z)", workflow)
        self.assertIsNotNone(match)
        command = textwrap.dedent(match.group(1))
        binary_dir = self.work / "bin"
        binary_dir.mkdir()
        for name, variable in (("stat", "STAT"), ("date", "DATE"), ("git", "GIT")):
            path = binary_dir / name
            path.write_text(f'#!/bin/bash\nset -eu\nprintf "%s\\n" "${{{variable}_OUTPUT}}"\nexit "${{{variable}_EXIT:-0}}"\n')
            path.chmod(0o755)
        healthy = dict(STAT_OUTPUT="123", DATE_OUTPUT="2026-10-20", GIT_OUTPUT="a" * 40)
        cases = [None, ("STAT_OUTPUT", ""), ("STAT_OUTPUT", "0"), ("STAT_OUTPUT", "bad"),
                 ("DATE_OUTPUT", ""), ("DATE_OUTPUT", "bad"), ("GIT_OUTPUT", ""),
                 ("GIT_OUTPUT", "a" * 39), ("GIT_OUTPUT", "a" * 40 + "\nextra"), ("STAT_EXIT", "9")]
        output = self.work / "github-output"
        for invalid in cases:
            with self.subTest(invalid=invalid):
                output.write_text("existing=true\n")
                env = dict(os.environ, PATH=f"{binary_dir}:/usr/bin:/bin", GITHUB_OUTPUT=str(output), **healthy)
                if invalid:
                    env[invalid[0]] = invalid[1]
                result = subprocess.run(["/bin/bash", "-c", command], env=env, cwd=self.work, capture_output=True, text=True, timeout=10)
                if invalid:
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(output.read_text(), "existing=true\n")
                else:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("size=123\ndate=2026-10-20\nrevision=" + "a" * 40, output.read_text())


if __name__ == "__main__":
    unittest.main()
