import argparse
from datetime import date, datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import urllib.request


REPOSITORY = "denzam/SystemEQ-for-Mac"
TAG = re.compile(r"v\d+\.\d+\.\d+\Z")
CATEGORIES = ("dmg", "zip", "homebrew", "other")
COUNTS = ("total", *CATEGORIES, "total_all_assets")


def fetch_json(path):
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "SystemEQ-download-statistics",
    }
    if token := os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"https://api.github.com/repos/{REPOSITORY}/{path}",
        headers=headers,
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def fetch_page(page):
    return fetch_json(f"releases?per_page=100&page={page}")


def fetch_assets(release_id):
    assets = []
    for page in range(1, 101):
        batch = fetch_json(f"releases/{release_id}/assets?per_page=100&page={page}")
        if not isinstance(batch, list) or len(batch) > 100:
            raise ValueError("Invalid release assets response")
        assets.extend(batch)
        if len(batch) < 100:
            return assets
    raise ValueError("Asset pagination did not finish")


def category_for(name, tag):
    for extension in ("dmg", "zip"):
        if name == f"SystemEQ-{tag}.{extension}":
            return extension
    return "homebrew" if name == f"SystemEQ-{tag}-homebrew.dmg" else "other"


def collect(fetch=fetch_page, asset_fetch=fetch_assets):
    totals = dict.fromkeys(CATEGORIES, 0)
    seen = set()
    seen_assets = set()
    files = []
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
            embedded = release.get("assets")
            if not isinstance(embedded, list):
                raise ValueError("Missing release assets")
            assets = asset_fetch(release_id)
            if not isinstance(assets, list):
                raise ValueError("Invalid release assets response")
            names = set()
            for asset in assets:
                if not isinstance(asset, dict) or not isinstance(asset.get("name"), str) or not asset["name"]:
                    raise ValueError("Invalid asset")
                name = asset["name"]
                asset_id = asset.get("id")
                if type(asset_id) is not int or asset_id <= 0 or asset_id in seen_assets:
                    raise ValueError("Missing or duplicate asset ID")
                seen_assets.add(asset_id)
                count = asset.get("download_count")
                size = asset.get("size")
                if name in names or type(count) is not int or count < 0:
                    raise ValueError("Invalid asset download count or duplicate name")
                if asset.get("state") != "uploaded" or type(size) is not int or size <= 0:
                    raise ValueError("Asset upload is incomplete")
                names.add(name)
                category = category_for(name, tag)
                totals[category] += count
                package_assets += category != "other"
                files.append({"id": asset_id, "release_id": release_id, "version": tag,
                              "name": name, "category": category, "downloads": count, "size": size})
            current_ids = {item["id"] for item in files if item["release_id"] == release_id}
            if any(not isinstance(item, dict) or type(item.get("id")) is not int or item["id"] not in current_ids for item in embedded):
                raise ValueError("Asset listing is incomplete")
            releases += 1
        if len(batch) < 100:
            break
    else:
        raise ValueError("Release pagination did not finish")
    if not package_assets:
        raise ValueError("No application packages found")
    result = {"total": sum(totals[key] for key in CATEGORIES if key != "other"), **totals,
              "total_all_assets": sum(totals.values()), "package_assets": package_assets,
              "releases": releases, "homebrew_available": any(item["category"] == "homebrew" for item in files),
              "assets": sorted(files, key=lambda item: (item["release_id"], item["id"]))}
    validate_stats(result)
    return result


def validate_counts(data):
    if not isinstance(data, dict) or any(type(data.get(key)) is not int or data[key] < 0 for key in COUNTS):
        raise ValueError("Invalid statistics counts")
    if data["total"] != data["dmg"] + data["zip"] + data["homebrew"] or data["total_all_assets"] != data["total"] + data["other"]:
        raise ValueError("Statistics counts do not match")


def validate_stats(data):
    validate_counts(data)
    if type(data.get("releases")) is not int or data["releases"] <= 0 or type(data.get("package_assets")) is not int or data["package_assets"] <= 0:
        raise ValueError("Invalid release or package count")
    if not isinstance(data.get("assets"), list) or type(data.get("homebrew_available")) is not bool:
        raise ValueError("Invalid asset statistics")
    totals = dict.fromkeys(CATEGORIES, 0)
    ids, names, release_ids, versions = set(), set(), {}, {}
    packages = 0
    homebrew = False
    for item in data["assets"]:
        if not isinstance(item, dict):
            raise ValueError("Invalid asset record")
        asset_id, release_id = item.get("id"), item.get("release_id")
        if type(asset_id) is not int or asset_id <= 0 or asset_id in ids or type(release_id) is not int or release_id <= 0:
            raise ValueError("Invalid or duplicate asset identity")
        version, name = item.get("version"), item.get("name")
        if not isinstance(version, str) or not TAG.fullmatch(version) or not isinstance(name, str) or not name or (release_id, name) in names:
            raise ValueError("Invalid asset version or name")
        if release_ids.get(release_id, version) != version or versions.get(version, release_id) != release_id:
            raise ValueError("Inconsistent release identity")
        release_ids[release_id], versions[version] = version, release_id
        category = category_for(name, version)
        if item.get("category") != category or type(item.get("downloads")) is not int or item["downloads"] < 0 or type(item.get("size")) is not int or item["size"] <= 0:
            raise ValueError("Invalid asset category or metadata")
        totals[category] += item["downloads"]
        packages += category != "other"
        homebrew |= category == "homebrew"
        ids.add(asset_id)
        names.add((release_id, name))
    if any(data[key] != totals[key] for key in CATEGORIES) or data["package_assets"] != packages or data["homebrew_available"] != homebrew or len(release_ids) > data["releases"]:
        raise ValueError("Asset records do not match statistics")


def validate_previous(previous, stats):
    if not isinstance(previous, dict) or type(previous.get("schema_version")) is not int or previous["schema_version"] not in (1, 2):
        raise ValueError("Unsupported previous statistics")
    if previous["schema_version"] == 2:
        validate_stats(previous)
        current = {item["id"]: item for item in stats["assets"]}
        for old in previous["assets"]:
            new = current.get(old["id"])
            if new is None or any(new[key] != old[key] for key in ("release_id", "version", "name", "category", "size")) or new["downloads"] < old["downloads"]:
                raise ValueError("Asset disappeared, changed or its count decreased; review release assets")
        keys = COUNTS
    else:
        keys = ("total", "dmg", "zip")
        if any(type(previous.get(key)) is not int or previous[key] < 0 for key in keys) or previous["total"] != previous["dmg"] + previous["zip"]:
            raise ValueError("Invalid previous statistics")
    if any(stats[key] < previous[key] for key in keys):
        raise ValueError("Download count decreased; review deleted or replaced release assets")


def update_history(directory, previous, stats, updated):
    path = directory / "app-downloads-history.json"
    days = []
    if path.exists():
        history = json.loads(path.read_text())
        if not isinstance(history, dict) or type(history.get("schema_version")) is not int or history["schema_version"] != 1 or not isinstance(history.get("days"), list) or not history["days"]:
            raise ValueError("Invalid statistics history")
        days = history["days"]
    elif previous is not None and previous["schema_version"] == 2:
        raise ValueError("Statistics history is missing")
    last_date = None
    last_counts = None
    for day in days:
        validate_counts(day)
        stamp = day.get("date")
        if not isinstance(stamp, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", stamp):
            raise ValueError("Invalid history date")
        day_date = date.fromisoformat(stamp)
        if (last_date is not None and day_date <= last_date) or day_date > updated.date() or (last_counts is not None and any(day[key] < last_counts[key] for key in COUNTS)):
            raise ValueError("History dates or counts are inconsistent")
        last_date, last_counts = day_date, day
    if days:
        if previous is None or previous["schema_version"] != 2:
            raise ValueError("History has no matching statistics")
        previous_time = datetime.fromisoformat(previous["updated_at"])
        if previous_time.tzinfo is None or previous_time.utcoffset() != timedelta(0) or previous_time > updated or previous_time.date() != last_date or any(days[-1][key] != previous[key] for key in COUNTS):
            raise ValueError("History does not match previous statistics")
        if previous.get("history_since") != days[0]["date"]:
            raise ValueError("History start does not match previous statistics")
    today = updated.date().isoformat()
    prior = next((day for day in reversed(days) if day["date"] < today), None)
    delta = None
    if prior is not None and date.fromisoformat(prior["date"]) == updated.date() - timedelta(days=1):
        delta = {key: stats[key] - prior[key] for key in COUNTS}
    snapshot = {"date": today, **{key: stats[key] for key in COUNTS}}
    if days and days[-1]["date"] == today:
        days[-1] = snapshot
    else:
        days.append(snapshot)
    return {"schema_version": 1, "days": days}, delta


def write_stats(directory, stats, now=None):
    if not directory.is_dir():
        raise ValueError("Output directory must already exist")
    validate_stats(stats)
    for name in ("app-downloads.json", "app-downloads.svg", "app-downloads-history.json"):
        if (directory / name).is_symlink():
            raise ValueError("Statistics output must not be a symlink")
    updated = now or datetime.now(timezone.utc)
    if updated.tzinfo is None or updated.utcoffset() != timedelta(0):
        raise ValueError("Statistics time must be UTC")
    target = directory / "app-downloads.json"
    previous = None
    if target.exists():
        previous = json.loads(target.read_text())
        validate_previous(previous, stats)
    history, delta = update_history(directory, previous, stats, updated)
    payload = {
        "schema_version": 2,
        **stats,
        "updated_at": updated.isoformat(timespec="seconds"),
        "history_since": history["days"][0]["date"],
        "daily_change": delta,
        "source": f"https://github.com/{REPOSITORY}/releases",
        "definition": "Official SystemEQ DMG, ZIP and dedicated Homebrew-file downloads, including updates and repeat downloads; not unique users or installations. Historical Homebrew downloads remain in DMG. ZIP includes app updates. Other release attachments are counted separately. GitHub-generated source archives have no exposed download count.",
    }
    count = f"{stats['total']:,}"
    width = 105 + max(40, 12 + len(count) * 7)
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="20" role="img" aria-label="App downloads: {count}">'
        f'<title>SystemEQ app downloads: {count} (DMG, ZIP and Homebrew file, including repeat downloads and updates)</title>'
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
        entries = [("app-downloads.json", json.dumps(payload, indent=2) + "\n"), ("app-downloads.svg", svg),
                   ("app-downloads-history.json", json.dumps(history, indent=2) + "\n")]
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
