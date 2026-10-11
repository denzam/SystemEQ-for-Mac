import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid


def check_directory(path):
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError(f"Directory contains a symlink: {part}")
        if part.exists() and not part.is_dir():
            raise ValueError(f"Not a directory: {part}")


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def snapshot(path):
    entries = {}
    pending = [(path, ".")]
    while pending:
        item, relative = pending.pop()
        mode = item.lstat().st_mode
        if stat.S_ISDIR(mode):
            entries[relative] = {"type": "directory", "mode": stat.S_IMODE(mode)}
            for child in item.iterdir():
                pending.append((child, str(Path(relative) / child.name)))
        elif stat.S_ISREG(mode):
            entries[relative] = {"type": "file", "mode": stat.S_IMODE(mode), "sha256": digest(item)}
        else:
            raise ValueError(f"Evidence contains a symlink or special file: {item}")
    return entries


def export_evidence(work, destination, selections):
    exported = {}
    for relative in selections:
        source = work / relative
        for ancestor in source.parents:
            if ancestor == work:
                break
            if ancestor.is_symlink():
                raise ValueError(f"Evidence ancestor is a symlink: {ancestor}")
        before = snapshot(source)
        target = destination / "artifacts" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target, symlinks=True)
        else:
            shutil.copy2(source, target, follow_symlinks=False)
        if snapshot(source) != before or snapshot(target) != before:
            raise RuntimeError(f"Evidence verification failed: {relative}")
        exported[str(relative)] = before
    return exported


def group_exists(pid):
    try:
        os.killpg(pid, 0)
        return True
    except ProcessLookupError:
        return False


def stop_group(process):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return process.wait(timeout=10)
    process.wait(timeout=10)


def wait_command(process, timeout, interrupted):
    deadline = time.monotonic() + timeout
    while True:
        if interrupted["signal"] is not None:
            stop_group(process)
            return 128 + interrupted["signal"], "Fixture interrupted"
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            stop_group(process)
            return 124, "Fixture timed out"
        try:
            code = process.wait(timeout=min(remaining, 0.1))
            return (code if code >= 0 else 128 - code), None
        except subprocess.TimeoutExpired:
            continue


def save_manifest(destination, manifest):
    temporary = destination / "run.json.pending"
    temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(destination / "run.json")


def check_owned_work(work, identity, token):
    info = work.lstat()
    marker = work / ".owner.json"
    if not stat.S_ISDIR(info.st_mode) or (info.st_dev, info.st_ino) != identity:
        raise RuntimeError("Fixture identity changed; cleanup refused")
    marker_info = marker.lstat()
    if not stat.S_ISREG(marker_info.st_mode) or marker_info.st_size > 1024:
        raise RuntimeError("Fixture owner marker is not a small regular file; cleanup refused")
    owner = json.loads(marker.read_text())
    if not isinstance(owner, dict) or owner.get("token") != token:
        raise RuntimeError("Fixture owner marker changed; cleanup refused")


def remove_owned_work(work, identity, token):
    check_owned_work(work, identity, token)
    shutil.rmtree(work)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Run an isolated fixture and preserve evidence before cleanup.")
    parser.add_argument("--results", type=Path, default=Path(__file__).resolve().parent.parent / "LocalArtifacts/FixtureResults")
    parser.add_argument("--keep", type=Path, action="append", default=[])
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("A command after -- is required")
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be finite and positive")
    for relative in args.keep:
        if relative.is_absolute() or ".." in relative.parts or relative == Path("."):
            parser.error("--keep must be a nonempty relative fixture path without ..")
    for index, relative in enumerate(args.keep):
        if any(relative == other or relative in other.parents or other in relative.parents for other in args.keep[:index]):
            parser.error("--keep selections must not overlap")
    results = Path(os.path.abspath(args.results))
    try:
        check_directory(results)
    except ValueError as error:
        parser.error(str(error))
    if args.check:
        print(json.dumps({"results": str(results), "keep": list(map(str, args.keep)), "command": command}))
        return 0
    work = None
    destination = None
    process = None
    manifest = {"command": command, "cleanup": "preserved", "exit_code": 125, "completed": False}
    interrupted = {"signal": None}
    def on_interrupt(number, frame):
        interrupted["signal"] = number
    handlers = {number: signal.signal(number, on_interrupt) for number in (signal.SIGTERM, signal.SIGINT)}
    try:
        results.mkdir(parents=True, exist_ok=True)
        destination = Path(tempfile.mkdtemp(prefix="fixture-", dir=results))
        work = Path(tempfile.mkdtemp(prefix="systemeq-fixture-")).resolve()
        info = work.lstat()
        identity = (info.st_dev, info.st_ino)
        token = uuid.uuid4().hex
        (work / ".owner.json").write_text(json.dumps({"token": token}))
        (work / "tmp").mkdir()
        manifest["work"] = str(work)
        manifest["results"] = str(destination)
        print(f"Fixture: {work}\nResults: {destination}", flush=True)
        env = dict(os.environ, SYSTEMEQ_FIXTURE_DIR=str(work), TMPDIR=str(work / "tmp"), PYTHONDONTWRITEBYTECODE="1")
        if interrupted["signal"] is not None:
            raise InterruptedError("Fixture interrupted before command launch")
        with (destination / "stdout.log").open("wb") as stdout, (destination / "stderr.log").open("wb") as stderr:
            process = subprocess.Popen(command, cwd=work, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
            code, error = wait_command(process, args.timeout, interrupted)
            manifest["exit_code"] = code
            if error is not None:
                manifest["error"] = error
            if group_exists(process.pid):
                stop_group(process)
                manifest.update(exit_code=125, error="Command left background processes; fixture retained")
        manifest["logs"] = {name: digest(destination / name) for name in ("stdout.log", "stderr.log")}
        if interrupted["signal"] is not None:
            manifest.update(exit_code=128 + interrupted["signal"], error="Fixture interrupted")
        if manifest["exit_code"] == 0:
            check_owned_work(work, identity, token)
            manifest["artifacts"] = export_evidence(work, destination, args.keep)
            manifest["cleanup"] = "pending"
            save_manifest(destination, manifest)
            if interrupted["signal"] is not None:
                raise InterruptedError("Fixture interrupted before cleanup")
            remove_owned_work(work, identity, token)
            manifest["cleanup"] = "removed"
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        try:
            if process is not None and (process.poll() is None or group_exists(process.pid)):
                stop_group(process)
        except (OSError, subprocess.SubprocessError) as stop_error:
            error = RuntimeError(f"{error}; could not stop fixture process group: {stop_error}")
        manifest.update(exit_code=128 + interrupted["signal"] if interrupted["signal"] is not None else 125, error=str(error))
    finally:
        for number, handler in handlers.items():
            signal.signal(number, handler)
    if interrupted["signal"] is not None and manifest["exit_code"] == 0:
        manifest.update(exit_code=128 + interrupted["signal"], error="Fixture interrupted")
    manifest["completed"] = True
    if destination is not None:
        try:
            save_manifest(destination, manifest)
        except OSError as error:
            manifest.update(exit_code=125, error=str(error))
            print(f"Could not save manifest: {error}", file=sys.stderr)
            try:
                save_manifest(destination, manifest)
            except OSError as save_error:
                manifest["completed"] = False
                print(f"Could not save failure manifest: {save_error}", file=sys.stderr)
    if manifest["exit_code"]:
        location = f"fixture path remains at {work}" if work is not None and os.path.lexists(work) else f"fixture path is absent; evidence directory: {destination}"
        print(f"Fixture failed: {manifest.get('error', manifest['exit_code'])}; {location}", file=sys.stderr)
    return manifest["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
