#!/bin/bash
set -euo pipefail
exec python3 - "$0" "$@" <<'PY'
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid


ROOT = Path(sys.argv.pop(1)).resolve().parent.parent
NAME = "SystemEQ for Mac"
HELPER = Path("Contents/Helpers/ProjectMHelper.app")
LIBRARIES = ("libprojectM-4.4.dylib", "libprojectM-4-playlist.4.dylib")
MACHOS = (
    Path("Contents/MacOS") / NAME,
    HELPER / "Contents/MacOS/ProjectMHelper",
    *(base / "Contents/Frameworks" / name for base in (Path("."), HELPER) for name in LIBRARIES),
)
MAGIC = {bytes.fromhex(value) for value in (
    "feedface", "feedfacf", "cefaedfe", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
)}
ENTITLEMENTS = {
    "com.apple.security.device.audio-input": True,
    "com.apple.security.automation.apple-events": True,
}
RUN = None


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def save_log(path, output):
    if path is not None:
        with path.open("ab") as stream:
            stream.write(b"\n--- command attempt ---\n" + output)


def run(command, log=None, timeout=180):
    try:
        result = subprocess.run([str(item) for item in command], capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        save_log(log, (error.stdout or b"") + (error.stderr or b""))
        raise RuntimeError(f"Command timed out: {command[0]}; log: {log}") from error
    save_log(log, result.stdout + result.stderr)
    require(result.returncode == 0, f"Command failed ({result.returncode}): {command[0]}; log: {log}\n{result.stderr.decode(errors='replace')[-2000:]}")
    return result


def prerequisites(identity, team):
    for tool in ("security", "codesign", "xcodebuild", "xcrun", "lipo", "otool", "ditto", "bash", "spctl"):
        require(shutil.which(tool), f"Missing tool: {tool}")
    output = run(["security", "find-identity", "-v", "-p", "codesigning"]).stdout.decode()
    matches = re.findall(r'\b([A-Fa-f0-9]{40}) "(Developer ID Application: [^"\n]+)"', output)
    names = [name for fingerprint, name in matches if fingerprint.upper() == identity and name.endswith(f"({team})")]
    require(len(names) == 1, "Expected one valid Developer ID Application identity for the specified fingerprint and team")
    with (ROOT / "Config/SystemEQ.entitlements").open("rb") as stream:
        require(plistlib.load(stream) == ENTITLEMENTS, "Unexpected application entitlements")


def inventory(app):
    require(app.is_dir() and not app.is_symlink(), "Missing app or symlinked app")
    app = app.resolve()
    found = set()
    hashes = {}
    for path in sorted(app.rglob("*")):
        relative = path.relative_to(app).as_posix()
        if path.is_symlink():
            require(path.resolve().is_relative_to(app) and path.resolve().exists(), f"Escaping or broken symlink: {relative}")
            hashes[relative] = {"link": os.readlink(path)}
        elif path.is_file():
            with path.open("rb") as stream:
                if stream.read(4) in MAGIC:
                    found.add(Path(relative))
            hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        else:
            require(path.is_dir(), f"Unsupported file: {relative}")
    require(found == set(MACHOS), f"Unexpected Mach-O inventory: {sorted(str(path) for path in found.symmetric_difference(MACHOS))}")
    return hashes


def diagnostic(name):
    return RUN / name if RUN is not None else None


def verify(app, state, label):
    inventory(app)
    requirement = f'anchor apple generic and certificate leaf[subject.OU] = "{state["team"]}" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
    components = [app / path for path in MACHOS[2:]] + [app / HELPER, app]
    for index, component in enumerate(components):
        run(["codesign", "--verify", "--strict", "--all-architectures", "-R", f"={requirement}", component], diagnostic(f"{label}-{index}-verify.log"))
        executable = component
        if component.is_dir():
            with (component / "Contents/Info.plist").open("rb") as stream:
                info = plistlib.load(stream)
            require(info["CFBundleShortVersionString"] == state["version"], "App/helper version mismatch")
            executable = component / "Contents/MacOS" / info["CFBundleExecutable"]
        arches = run(["lipo", "-archs", executable], diagnostic(f"{label}-{index}-architectures.log")).stdout.decode().split()
        require(set(arches) == {"arm64", "x86_64"}, f"Not a universal binary: {component}")
        for arch in ("arm64", "x86_64"):
            result = run(["codesign", "--display", "--arch", arch, "--verbose=4", "--entitlements", "-", "--xml", component], diagnostic(f"{label}-{index}-{arch}.log"))
            details = result.stderr.decode()
            require(f"TeamIdentifier={state['team']}\n" in details, f"Wrong team: {component}")
            require("Authority=Developer ID Application:" in details and "Signature=adhoc" not in details, f"Wrong signature: {component}")
            require(re.search(r"flags=0x[0-9a-f]+\([^\n]*\bruntime\b", details), f"Hardened Runtime missing: {component}")
            require(re.search(r"^Timestamp=(?!none\s*$).+", details, re.MULTILINE), f"Secure timestamp missing: {component}")
            entitlements = plistlib.loads(result.stdout) if result.stdout.strip() else {}
            require(entitlements == (ENTITLEMENTS if component == app else {}), f"Unexpected entitlements: {component}")
    run(["bash", ROOT / "Scripts/verify_release_artifacts.sh", "--bundle", app, state["version"]], diagnostic(f"{label}-bundle.log"))


def write_json(path, value):
    with path.open("x") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def submission_id(value):
    require(isinstance(value, str), "Missing notary submission ID")
    require(str(uuid.UUID(value)) == value.lower(), "Malformed notary submission ID")
    return value.lower()


def require_accepted(submission, log, state):
    require(isinstance(submission, dict) and isinstance(log, dict), "Malformed notary response")
    identifier = submission_id(submission.get("id"))
    require(submission.get("status") == "Accepted" and log.get("status") == "Accepted" and submission_id(log.get("jobId")) == identifier, "Notarization was not accepted; inspect preserved notary logs")
    require(log.get("sha256") == state["zip_sha256"], "Notary log does not match the submitted ZIP")


def record_json(path, value):
    require(not path.is_symlink(), f"Symlinked record: {path}")
    if path.exists():
        require(json.loads(path.read_text()) == value, f"Existing record differs: {path}")
    else:
        write_json(path, value)


def accepted(state):
    submission = RUN / "accepted.json"
    log = RUN / "notary-log.json"
    require(not submission.is_symlink() and not log.is_symlink(), "Symlinked notarization record")
    require_accepted(json.loads(submission.read_text()), json.loads(log.read_text()), state)


def notarize(args, state, package_name="SystemEQ-signed.zip", upload=None):
    package = RUN / package_name
    require(not package.is_symlink() and hashlib.sha256(package.read_bytes()).hexdigest() == state["zip_sha256"], "Submission ZIP changed since preparation")
    attempt = Path(tempfile.mkdtemp(prefix="notary-", dir=RUN))
    submission_path = RUN / "submission.json"
    authentication = ["--keychain-profile", args.profile]
    if args.keychain:
        authentication += ["--keychain", args.keychain]
    require(not submission_path.is_symlink(), "Symlinked submission record")
    should_upload = bool(args.notarize) if upload is None else upload
    if should_upload:
        require(not (RUN / "submission-attempt.json").exists() and not submission_path.exists(), "Submission already attempted; use --resume instead of uploading again")
        write_json(RUN / "submission-attempt.json", {"zip_sha256": state["zip_sha256"]})
        result = run(["xcrun", "notarytool", "submit", package, *authentication, "--no-wait", "--output-format", "json"], RUN / "submission-output.log", timeout=1500)
        submission = json.loads(result.stdout)
        require(isinstance(submission, dict), "Malformed submission response")
        submission_id(submission.get("id"))
        write_json(submission_path, submission)
    elif args.submission_id:
        require((RUN / "submission-attempt.json").is_file(), "No recorded upload attempt to recover")
        identifier = submission_id(args.submission_id)
        if submission_path.exists():
            require(submission_id(json.loads(submission_path.read_text()).get("id")) == identifier, "Submission ID differs from the saved upload")
        else:
            write_json(submission_path, {"id": identifier})
    require(submission_path.is_file(), "No saved submission ID; recover it from submission-output.log or notarytool history, then use --resume --submission-id UUID")
    identifier = submission_id(json.loads(submission_path.read_text()).get("id"))
    if (RUN / "accepted.json").exists():
        accepted(state)
        return
    result = run(["xcrun", "notarytool", "info", identifier, *authentication, "--output-format", "json"], attempt / "info-output.log")
    info = json.loads(result.stdout)
    require(isinstance(info, dict) and submission_id(info.get("id")) == identifier, "Notary info belongs to another submission")
    write_json(attempt / "info.json", info)
    if info.get("status") == "In Progress":
        result = run(["xcrun", "notarytool", "wait", identifier, *authentication, "--timeout", "20m", "--output-format", "json"], attempt / "wait-output.log", timeout=1250)
        info = json.loads(result.stdout)
        require(isinstance(info, dict) and submission_id(info.get("id")) == identifier, "Notary wait belongs to another submission")
        write_json(attempt / "wait.json", info)
    result = run(["xcrun", "notarytool", "log", identifier, *authentication], attempt / "log-output.log")
    log = json.loads(result.stdout)
    write_json(attempt / "log.json", log)
    require_accepted(info, log, state)
    record_json(RUN / "notary-log.json", log)
    record_json(RUN / "accepted.json", {"id": identifier, "status": "Accepted"})
    print(f"Apple accepted notarization; inspect preserved warnings: {RUN / 'notary-log.json'}")


def load_run(path, allow_completed=False):
    global RUN
    base = ROOT / "LocalArtifacts/SignedReleases"
    RUN = Path(path).resolve(strict=True)
    require(not (ROOT / "LocalArtifacts").is_symlink() and not base.is_symlink() and RUN.parent == base.resolve() and RUN.name.startswith("release-"), "Not an owned signed-release directory")
    manifest = RUN / "manifest.json"
    require(not manifest.is_symlink(), "Symlinked manifest")
    state = json.loads(manifest.read_text())
    require(re.fullmatch(r"[A-Z0-9]{10}", state["team"]), "Invalid recorded team")
    require(re.fullmatch(r"[A-F0-9]{40}", state["identity"]), "Invalid recorded signing identity")
    app = RUN / f"{NAME}.app"
    require(allow_completed or not (RUN / "completed.json").exists(), "This release is already finalized")
    require(inventory(app) == state["files"], "Signed app changed since preparation")
    verify(app, state, "preflight")
    return app, state


def finalize(app, state):
    accepted(state)
    attempt = Path(tempfile.mkdtemp(prefix="finalize-", dir=RUN))
    staged = attempt / app.name
    run(["ditto", app, staged], attempt / "copy.log")
    require(inventory(staged) == state["files"], "Staged app differs from the signed app")
    app = staged
    run(["xcrun", "stapler", "staple", app], attempt / "staple.log")
    run(["xcrun", "stapler", "validate", app], attempt / "staple-validate.log")
    verify(app, state, "final")
    run(["spctl", "--assess", "--type", "execute", "--verbose=4", app], attempt / "gatekeeper.log")
    package = attempt / "SystemEQ-notarized.zip"
    run(["ditto", "-c", "-k", "--keepParent", app, package], attempt / "distribution-zip.log")
    extracted = attempt / "DistributionCheck"
    run(["ditto", "-x", "-k", package, extracted], attempt / "distribution-extract.log")
    distributed_app = extracted / f"{NAME}.app"
    require(inventory(distributed_app) == inventory(app), "Distribution ZIP does not match the stapled app")
    run(["xcrun", "stapler", "validate", distributed_app], attempt / "distribution-ticket.log")
    run(["codesign", "--verify", "--deep", "--strict", distributed_app], attempt / "distribution-signature.log")
    run(["spctl", "--assess", "--type", "execute", "--verbose=4", distributed_app], attempt / "distribution-gatekeeper.log")
    write_json(RUN / "completed.json", {"team": state["team"], "version": state["version"], "app": str(app.relative_to(RUN)), "zip": str(package.relative_to(RUN)), "zip_sha256": hashlib.sha256(package.read_bytes()).hexdigest()})
    print(f"Notarized app, stapled ticket and Gatekeeper assessment verified: {package}")


def owned_file(base, relative):
    require(isinstance(relative, str) and relative and not Path(relative).is_absolute(), "Invalid artifact path")
    path = base / relative
    require(not path.is_symlink() and path.resolve(strict=True).is_relative_to(base), "Artifact escapes its release directory")
    return path


def finalized_artifacts(base, state):
    record = base / "completed.json"
    require(record.is_file() and not record.is_symlink(), "Missing app completion record")
    complete = json.loads(record.read_text())
    require(complete["team"] == state["team"] and complete["version"] == state["version"], "App completion identity mismatch")
    app = owned_file(base, complete["app"])
    package = owned_file(base, complete["zip"])
    require(package.is_file() and hashlib.sha256(package.read_bytes()).hexdigest() == complete["zip_sha256"], "Completed ZIP changed")
    verify(app, state, "dmg-source")
    run(["xcrun", "stapler", "validate", app], diagnostic("dmg-source-ticket.log"))
    run(["spctl", "--assess", "--type", "execute", "--verbose=4", app], diagnostic("dmg-source-gatekeeper.log"))
    return app, package


def dmg_release(args):
    global RUN
    _, app_state = load_run(args.notarize_dmg or args.resume_dmg or args.staple_dmg, allow_completed=True)
    base = RUN
    _, package = finalized_artifacts(base, app_state)
    directory = base / "dmg"
    if args.notarize_dmg:
        source = Path(args.dmg).absolute()
        require(source.is_file() and not source.is_symlink(), "DMG must be a regular file")
        require(not directory.exists() and not directory.is_symlink(), "DMG preparation already attempted; use --resume-dmg")
        directory.mkdir()
        RUN = directory
        signed = RUN / "SystemEQ-signed.dmg"
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        shutil.copyfile(source, signed)
        require(hashlib.sha256(signed.read_bytes()).hexdigest() == before == hashlib.sha256(source.read_bytes()).hexdigest(), "DMG copy changed")
        run(["bash", ROOT / "Scripts/verify_release_artifacts.sh", package, signed, app_state["version"]], RUN / "packages-preflight.log")
        run(["codesign", "--force", "--sign", app_state["identity"], "--timestamp", signed], RUN / "sign.log")
        requirement = f'anchor apple generic and certificate leaf[subject.OU] = "{app_state["team"]}" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
        run(["codesign", "--verify", "--strict", "-R", f"={requirement}", signed], RUN / "signature.log")
        state = dict(app_state, zip_sha256=hashlib.sha256(signed.read_bytes()).hexdigest(), app_record_sha256=hashlib.sha256((base / "completed.json").read_bytes()).hexdigest())
        write_json(RUN / "manifest.json", state)
    else:
        require(directory.is_dir() and not directory.is_symlink(), "Missing owned DMG directory")
        RUN = directory
        require(not (RUN / "manifest.json").is_symlink(), "Symlinked DMG manifest")
        state = json.loads((RUN / "manifest.json").read_text())
    require(state["team"] == app_state["team"] and state["identity"] == app_state["identity"] and state["version"] == app_state["version"], "DMG identity mismatch")
    require(state["app_record_sha256"] == hashlib.sha256((base / "completed.json").read_bytes()).hexdigest(), "App completion changed")
    require(not (RUN / "completed.json").exists(), "DMG is already finalized")
    signed = RUN / "SystemEQ-signed.dmg"
    require(signed.is_file() and not signed.is_symlink() and hashlib.sha256(signed.read_bytes()).hexdigest() == state["zip_sha256"], "Signed DMG changed")
    if not args.staple_dmg:
        notarize(args, state, "SystemEQ-signed.dmg", upload=bool(args.notarize_dmg))
    accepted(state)
    attempt = Path(tempfile.mkdtemp(prefix="finalize-", dir=RUN))
    final = attempt / "SystemEQ-notarized.dmg"
    shutil.copyfile(signed, final)
    run(["xcrun", "stapler", "staple", final], attempt / "staple.log")
    run(["bash", ROOT / "Scripts/verify_release_artifacts.sh", "--distribution", state["team"], package, final, state["version"]], attempt / "distribution.log")
    write_json(RUN / "completed.json", {"team": state["team"], "version": state["version"], "dmg": str(final.relative_to(base)), "dmg_sha256": hashlib.sha256(final.read_bytes()).hexdigest()})
    RUN = base


def machine_record(path, phase):
    if path is None:
        return
    value = {"run": str(RUN), "phase": phase, "manifest": str(RUN / "manifest.json")}
    if phase != "signed":
        record = RUN / ("dmg/completed.json" if phase == "dmg" else "completed.json")
        value["completed"] = str(record)
    write_json(path, value)


def main():
    global RUN
    parser = argparse.ArgumentParser(description="Prepare an isolated Developer ID release; never installs or publishes.")
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true")
    action.add_argument("--build", action="store_true")
    action.add_argument("--notarize", metavar="RUN_DIR")
    action.add_argument("--resume", metavar="RUN_DIR")
    action.add_argument("--staple", metavar="RUN_DIR")
    action.add_argument("--notarize-dmg", metavar="RUN_DIR")
    action.add_argument("--resume-dmg", metavar="RUN_DIR")
    action.add_argument("--staple-dmg", metavar="RUN_DIR")
    action.add_argument("--verify-bundle", metavar="APP")
    parser.add_argument("--identity", help="40-character signing certificate fingerprint")
    parser.add_argument("--team", help="10-character Developer Team ID")
    parser.add_argument("--profile", help="Existing notarytool Keychain profile; no passwords accepted")
    parser.add_argument("--keychain", help="Keychain containing the notarytool profile")
    parser.add_argument("--submission-id", help="Recover an interrupted upload with a known submission UUID; --resume only")
    parser.add_argument("--dmg", help="Existing DMG to copy, sign and notarize")
    parser.add_argument("--record", type=Path, help="New machine-readable success record")
    parser.add_argument("--version", help="Expected version for --verify-bundle")
    if any(value in ("--help", "-h") for value in sys.argv[1:]) and len(sys.argv) != 2:
        parser.error("Use --help alone")
    args = parser.parse_args()
    if args.record:
        if args.check or args.verify_bundle:
            parser.error("Read-only modes do not write records")
        require(not args.record.exists() and not args.record.is_symlink() and args.record.parent.is_dir(), "Record target must be a new file in an existing directory")
    if args.verify_bundle:
        if not args.team or not re.fullmatch(r"[A-Z0-9]{10}", args.team) or not args.version or args.identity or args.profile or args.keychain or args.dmg or args.submission_id:
            parser.error("--verify-bundle requires only --team and --version")
        verify(Path(args.verify_bundle), {"team": args.team, "version": args.version}, "distribution")
        return
    if args.version:
        parser.error("--version is only for --verify-bundle")
    is_dmg = bool(args.notarize_dmg or args.resume_dmg or args.staple_dmg)
    if is_dmg:
        if args.identity or args.team or (bool(args.dmg) != bool(args.notarize_dmg)) or (args.submission_id and not args.resume_dmg):
            parser.error("DMG modes use the recorded identity; --dmg is required only for --notarize-dmg")
        if args.staple_dmg:
            if args.profile or args.keychain: parser.error("--staple-dmg uses saved acceptance records")
        elif not args.profile or not re.fullmatch(r"[A-Za-z0-9._-]{1,80}", args.profile):
            parser.error("DMG notarization requires --profile")
        if args.submission_id: submission_id(args.submission_id)
        dmg_release(args)
        machine_record(args.record, "dmg")
        return
    if args.dmg:
        parser.error("--dmg requires --notarize-dmg")
    if args.check or args.build:
        if not args.identity or not re.fullmatch(r"[A-Fa-f0-9]{40}", args.identity) or not args.team or not re.fullmatch(r"[A-Z0-9]{10}", args.team) or args.profile or args.keychain or args.submission_id:
            parser.error("--check/--build require --identity SHA1 and --team TEAM; --profile is for --notarize only")
        args.identity = args.identity.upper()
        prerequisites(args.identity, args.team)
        if args.check:
            print("Developer ID identity, entitlements and tools available; no files changed")
            return
        base = ROOT / "LocalArtifacts/SignedReleases"
        require(not (ROOT / "LocalArtifacts").is_symlink() and not base.is_symlink(), "Refusing a symlinked artifacts directory")
        base.mkdir(parents=True, exist_ok=True)
        RUN = Path(tempfile.mkdtemp(prefix="release-", dir=base))
        print(f"Artifacts and diagnostics: {RUN}", flush=True)
        archive = RUN / "SystemEQ.xcarchive"
        run(["xcodebuild", "archive", "-project", ROOT / f"{NAME}.xcodeproj", "-scheme", NAME, "-configuration", "Release", "-destination", "generic/platform=macOS", "-derivedDataPath", RUN / "DerivedData", "-archivePath", archive, "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "CODE_SIGNING_ALLOWED=NO", "-quiet"], RUN / "archive.log", timeout=1800)
        source = archive / "Products/Applications" / f"{NAME}.app"
        inventory(source)
        app = RUN / f"{NAME}.app"
        shutil.copytree(source, app, symlinks=True)
        shutil.copyfile(ROOT / "Config/SystemEQ.entitlements", RUN / "SystemEQ.entitlements")
        with (app / "Contents/Info.plist").open("rb") as stream:
            version = plistlib.load(stream)["CFBundleShortVersionString"]
        state = {"identity": args.identity, "team": args.team, "version": version}
        components = [app / path for path in MACHOS[2:]] + [app / HELPER, app]
        for index, component in enumerate(components):
            command = ["codesign", "--force", "--sign", args.identity, "--timestamp", "--options", "runtime"]
            if component == app:
                command += ["--entitlements", RUN / "SystemEQ.entitlements"]
            run([*command, component], RUN / f"sign-{index}.log")
        verify(app, state, "signed")
        package = RUN / "SystemEQ-signed.zip"
        run(["ditto", "-c", "-k", "--keepParent", app, package], RUN / "signed-zip.log")
        state["files"] = inventory(app)
        state["zip_sha256"] = hashlib.sha256(package.read_bytes()).hexdigest()
        write_json(RUN / "manifest.json", state)
        machine_record(args.record, "signed")
        print(f"Signed universal app verified; NOT notarized: {app}")
        return
    if args.identity or args.team or (args.staple and (args.profile or args.keychain)):
        parser.error("Recorded identity/team are used for notarization and stapling")
    if args.submission_id and not args.resume:
        parser.error("--submission-id is for --resume only")
    if (args.notarize or args.resume) and (not args.profile or not re.fullmatch(r"[A-Za-z0-9._-]{1,80}", args.profile)):
        parser.error("--notarize/--resume require --profile with an existing Keychain profile name")
    if args.submission_id:
        submission_id(args.submission_id)
    app, state = load_run(args.notarize or args.resume or args.staple)
    if args.notarize or args.resume:
        notarize(args, state)
    finalize(app, state)
    machine_record(args.record, "notarized")


try:
    main()
except (OSError, ValueError, KeyError, RuntimeError, plistlib.InvalidFileException) as error:
    print(f"ERROR: {error}", file=sys.stderr)
    if RUN is not None:
        print(f"Artifacts preserved: {RUN}", file=sys.stderr)
    sys.exit(1)
PY
