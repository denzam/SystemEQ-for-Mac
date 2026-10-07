#!/usr/bin/env python3
import argparse
import hashlib
from pathlib import Path
import plistlib
import re
import sys


def read_source(manifest):
    with manifest.open("rb") as file:
        info = plistlib.load(file)
    if not isinstance(info, dict):
        raise ValueError("Invalid preset manifest")
    commit = info.get("ProjectMPresetCommit")
    digest = info.get("ProjectMPresetSHA256")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Invalid pinned preset commit")
    if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Invalid pinned preset SHA256")
    return f"https://codeload.github.com/projectM-visualizer/presets-cream-of-the-crop/zip/{commit}", digest


def verify(archive, expected):
    if archive.is_symlink() or not archive.is_file():
        raise ValueError("Preset archive must be a regular file")
    digest = hashlib.sha256()
    with archive.open("rb") as file:
        for block in iter(lambda: file.read(65536), b""):
            digest.update(block)
    if digest.hexdigest() != expected:
        raise ValueError("Preset archive SHA256 does not match the pinned version")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", nargs="?", type=Path)
    parser.add_argument("--url", action="store_true")
    parser.add_argument("--manifest", type=Path, default=Path(__file__).resolve().parent.parent / "Config/ProjectMHelper/Info.plist")
    args = parser.parse_args()
    if args.url == (args.archive is not None):
        parser.error("Choose either --url or an archive to verify")
    try:
        url, digest = read_source(args.manifest)
        if args.url:
            print(url)
        else:
            verify(args.archive, digest)
            print("ProjectM preset archive verified")
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Preset archive verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
