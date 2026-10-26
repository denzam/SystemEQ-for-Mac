import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import update_download_stats as stats


def release(number=1):
    tag = f"v1.0.{number}"
    return {
        "id": number, "tag_name": tag, "draft": False, "prerelease": False,
        "assets": [
            {"name": f"SystemEQ-{tag}.dmg", "download_count": 10, "size": 20, "state": "uploaded"},
            {"name": f"SystemEQ-{tag}.zip", "download_count": 3, "size": 20, "state": "uploaded"},
            {"name": "appcast.xml", "download_count": 999},
            {"name": "source.zip", "download_count": 999},
            {"name": "unrelated.dmg", "download_count": 999},
            {"name": "SystemEQ-v9.0.0.dmg", "download_count": 999},
        ],
    }


class DownloadStatsTests(unittest.TestCase):
    def test_only_exact_application_packages_count(self):
        result = stats.collect(lambda _: [release()])
        self.assertEqual(result["total"], 13)
        self.assertEqual((result["dmg"], result["zip"], result["package_assets"]), (10, 3, 2))

    def test_all_pages_count_and_duplicates_fail(self):
        first = [release(n) for n in range(1, 101)]
        result = stats.collect(lambda page: first if page == 1 else [release(101)])
        self.assertEqual(result["total"], 101 * 13)
        with self.assertRaises(ValueError):
            stats.collect(lambda _: first)

    def test_missing_empty_and_malformed_responses_fail(self):
        for value in [None, {}, [], [{"id": 1}], ["bad"]]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                stats.collect(lambda _: value)

    def test_bad_package_metadata_and_duplicate_assets_fail(self):
        for key, value in [("download_count", -1), ("download_count", True), ("download_count", 1.5),
                           ("size", 0), ("state", "new")]:
            item = release()
            item["assets"][0][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                stats.collect(lambda _: [item])
        item = release()
        item["assets"].append(copy.deepcopy(item["assets"][0]))
        with self.assertRaises(ValueError):
            stats.collect(lambda _: [item])

    def test_drafts_and_prereleases_are_excluded(self):
        draft, prerelease = release(2), release(3)
        draft["draft"], prerelease["prerelease"] = True, True
        self.assertEqual(stats.collect(lambda _: [release(), draft, prerelease])["total"], 13)

    def test_failed_network_preserves_both_existing_files(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            stats.write_stats(directory, stats.collect(lambda _: [release()]))
            before = {p.name: p.read_bytes() for p in directory.iterdir()}
            with patch.object(stats, "fetch_page", side_effect=TimeoutError("fixture")), self.assertRaises(TimeoutError):
                stats.collect(stats.fetch_page)
            self.assertEqual(before, {p.name: p.read_bytes() for p in directory.iterdir()})

    def test_decreased_count_and_corrupt_previous_state_preserve_files(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            result = stats.collect(lambda _: [release()])
            stats.write_stats(directory, result)
            before = {p.name: p.read_bytes() for p in directory.iterdir()}
            with self.assertRaises(ValueError):
                stats.write_stats(directory, {**result, "total": 0})
            self.assertEqual(before, {p.name: p.read_bytes() for p in directory.iterdir()})
            (directory / "app-downloads.json").write_text("broken")
            with self.assertRaises(json.JSONDecodeError):
                stats.write_stats(directory, result)

    def test_second_replace_failure_rolls_back_both_existing_outputs(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            result = stats.collect(lambda _: [release()])
            stats.write_stats(directory, result)
            before = {p.name: p.read_bytes() for p in directory.iterdir()}
            real_replace = stats.os.replace
            calls = 0

            def replace(source, destination):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("fixture second replace failure")
                return real_replace(source, destination)

            with patch.object(stats.os, "replace", side_effect=replace), self.assertRaises(OSError):
                stats.write_stats(directory, {**result, "total": 14, "dmg": 11})
            self.assertEqual(before, {p.name: p.read_bytes() for p in directory.iterdir()})

    def test_failed_rollback_retains_verified_original_for_recovery(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            result = stats.collect(lambda _: [release()])
            stats.write_stats(directory, result)
            original = (directory / "app-downloads.json").read_bytes()
            real_replace = stats.os.replace
            calls = 0

            def replace(source, destination):
                nonlocal calls
                calls += 1
                if calls >= 2:
                    raise OSError("fixture persistent replace failure")
                return real_replace(source, destination)

            with patch.object(stats.os, "replace", side_effect=replace), self.assertRaisesRegex(RuntimeError, "recovery files retained"):
                stats.write_stats(directory, {**result, "total": 14, "dmg": 11})
            recovery = list(directory.glob(".download-stats-*/app-downloads.json.previous"))
            self.assertEqual(len(recovery), 1)
            self.assertEqual(recovery[0].read_bytes(), original)

    def test_output_describes_downloads_instead_of_people(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            stats.write_stats(directory, stats.collect(lambda _: [release()]))
            data = json.loads((directory / "app-downloads.json").read_text())
            self.assertEqual(data["total"], data["dmg"] + data["zip"])
            self.assertIn("not unique users", data["definition"])
            self.assertIn("13", (directory / "app-downloads.svg").read_text())


if __name__ == "__main__":
    unittest.main()
