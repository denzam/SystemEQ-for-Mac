import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import urllib.request


REPOSITORY = "denzam/SystemEQ-for-Mac"
TAG = re.compile(r"v\d+\.\d+\.\d+\Z")


def fetch_page(page):
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "SystemEQ-download-statistics",
    }
    if token := os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"https://api.github.com/repos/{REPOSITORY}/releases?per_page=100&page={page}",
        headers=headers,
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def collect(fetch=fetch_page):
    totals = {"dmg": 0, "zip": 0}
    seen = set()
    package_assets = 0
    releases = 0
    for page in range(1, 101):
        batch = fetch(page)
        if not isinstance(batch, list) or len(batch) > 100:
            raise ValueError("Invalid releases response")
        for release in batch:
            if not isinstance(release, dict):
                raise ValueError("Invalid release")
            release_id = release.get("id")
            if type(release_id) is not int or release_id <= 0 or release_id in seen:
                raise ValueError("Missing or duplicate release ID")
            seen.add(release_id)
            if type(release.get("draft")) is not bool or type(release.get("prerelease")) is not bool:
                raise ValueError("Missing release visibility")
            if release["draft"] or release["prerelease"]:
                continue
            tag = release.get("tag_name")
            if not isinstance(tag, str):
                raise ValueError("Missing release version")
            if not TAG.fullmatch(tag):
                continue
            assets = release.get("assets")
            if not isinstance(assets, list):
                raise ValueError("Missing release assets")
            names = set()
            for asset in assets:
                if not isinstance(asset, dict) or not isinstance(asset.get("name"), str):
                    raise ValueError("Invalid asset")
                name = asset["name"]
                extension = next((ext for ext in totals if name == f"SystemEQ-{tag}.{ext}"), None)
                if extension is None:
                    continue
                count = asset.get("download_count")
                size = asset.get("size")
                if name in names or type(count) is not int or count < 0:
                    raise ValueError("Invalid package download count or duplicate package")
                if asset.get("state") != "uploaded" or type(size) is not int or size <= 0:
                    raise ValueError("Package upload is incomplete")
                names.add(name)
                totals[extension] += count
                package_assets += 1
            releases += 1
        if len(batch) < 100:
            break
    else:
        raise ValueError("Release pagination did not finish")
    if not package_assets:
        raise ValueError("No application packages found")
    return {"total": sum(totals.values()), **totals, "package_assets": package_assets, "releases": releases}


def write_stats(directory, stats):
    if not directory.is_dir():
        raise ValueError("Output directory must already exist")
    target = directory / "app-downloads.json"
    if target.exists():
        previous = json.loads(target.read_text())
        old_total = previous.get("total")
        if type(old_total) is not int or old_total < 0:
            raise ValueError("Invalid previous statistics")
        if stats["total"] < old_total:
            raise ValueError("Package total decreased; review deleted or replaced release assets")
    payload = {
        "schema_version": 1,
        **stats,
        "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": f"https://github.com/{REPOSITORY}/releases",
        "definition": "Official SystemEQ DMG and ZIP downloads, including updates and repeat downloads; not unique users or installations.",
    }
    count = f"{stats['total']:,}"
    width = 105 + max(40, 12 + len(count) * 7)
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="20" role="img" aria-label="App downloads: {count}">'
        f'<title>SystemEQ app downloads: {count} (DMG and ZIP, including repeat downloads and updates)</title>'
        '<rect width="105" height="20" fill="#555"/>'
        f'<rect x="105" width="{width - 105}" height="20" fill="#007ec6"/>'
        '<g fill="#fff" text-anchor="middle" font-family="Verdana,sans-serif" font-size="11">'
        '<text x="52.5" y="14">app downloads</text>'
        f'<text x="{105 + (width - 105) / 2}" y="14">{count}</text></g></svg>\n'
    )
    staging = Path(tempfile.mkdtemp(dir=directory, prefix=".download-stats-"))
    originals = {}
    replaced = []
    preserve_recovery = False
    try:
        entries = [("app-downloads.json", json.dumps(payload, indent=2) + "\n"), ("app-downloads.svg", svg)]
        for name, content in entries:
            destination = directory / name
            if destination.is_symlink():
                raise ValueError("Statistics output must not be a symlink")
            originals[name] = destination.read_bytes() if destination.exists() else None
            if originals[name] is not None:
                backup = staging / (name + ".previous")
                shutil.copy2(destination, backup)
                if backup.read_bytes() != originals[name]:
                    raise ValueError("Statistics backup verification failed")
            (staging / name).write_text(content, encoding="utf-8")
        for name, _ in entries:
            os.replace(staging / name, directory / name)
            replaced.append(name)
    except Exception as error:
        failures = []
        for name in reversed(replaced):
            destination = directory / name
            try:
                if originals[name] is None:
                    destination.unlink()
                else:
                    os.replace(staging / (name + ".previous"), destination)
                    if destination.read_bytes() != originals[name]:
                        raise OSError("Statistics rollback verification failed")
            except OSError as rollback_error:
                failures.append(str(rollback_error))
        if failures:
            preserve_recovery = True
            raise RuntimeError(f"Statistics rollback failed; recovery files retained in {staging}: {failures}") from error
        raise
    finally:
        if not preserve_recovery:
            shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    stats = collect()
    write_stats(args.output_dir, stats)
    print(json.dumps(stats, sort_keys=True))


if __name__ == "__main__":
    main()
