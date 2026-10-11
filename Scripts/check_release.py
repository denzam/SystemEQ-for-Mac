import argparse
import ast
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from urllib.parse import urlencode


JOBS = {"Tooling Check", "SwiftLint", "SwiftFormat Check", "Sanitizer (address)", "Sanitizer (thread)", "Test Check"}
WORKFLOW = ".github/workflows/code-quality.yml"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(root, *args):
    result = subprocess.run(args, cwd=root, env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"), capture_output=True, text=True, timeout=60)
    require(result.returncode == 0, f"{args[0]} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def api(root, endpoint, paginated=False):
    args = ["gh", "api", "--method", "GET", "-H", "Accept: application/vnd.github+json"]
    if paginated:
        args.extend(["--paginate", "--slurp"])
    return json.loads(command(root, *args, endpoint))


def collection(payload, key):
    require(isinstance(payload, list) and bool(payload), "Missing API pages")
    items = []
    totals = []
    for page in payload:
        require(isinstance(page, dict) and isinstance(page.get(key), list), "Invalid API collection")
        count = page.get("total_count")
        require(type(count) is int and 0 <= count < 1000, "Invalid or truncated API count")
        totals.append(count)
        items.extend(page[key])
    require(len(set(totals)) == 1 and len(items) == totals[0], "Incomplete API pagination")
    require(all(isinstance(item, dict) and type(item.get("id")) is int and item["id"] > 0 for item in items), "Invalid API item")
    require(len({item["id"] for item in items}) == len(items), "Duplicate API items")
    return items


def project_data(text):
    pattern = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', re.S)
    tokens = [m.group() for m in pattern.finditer(text) if not m.group().isspace() and not m.group().startswith(("/*", "//"))]
    position = 0

    def take(expected=None):
        nonlocal position
        require(position < len(tokens), "Truncated project")
        token = tokens[position]
        position += 1
        require(expected is None or token == expected, "Invalid project syntax")
        return ast.literal_eval(token) if token.startswith('"') else token

    def value():
        require(position < len(tokens), "Truncated project value")
        if tokens[position] == "{":
            take("{")
            result = {}
            while tokens[position] != "}":
                key = take()
                require(key not in result, "Duplicate project key")
                take("=")
                result[key] = value()
                take(";")
            take("}")
            return result
        if tokens[position] == "(":
            take("(")
            result = []
            while tokens[position] != ")":
                result.append(value())
                if tokens[position] == ",":
                    take(",")
                else:
                    require(tokens[position] == ")", "Invalid project array")
            take(")")
            return result
        return take()

    result = value()
    require(position == len(tokens), "Trailing project content")
    return result


def metadata(root, sha, version):
    def source(path):
        return command(root, "git", "show", f"{sha}:{path}")

    objects = project_data(source("SystemEQ for Mac.xcodeproj/project.pbxproj"))["objects"]
    targets = [item for item in objects.values() if item.get("isa") == "PBXNativeTarget" and item.get("productType") == "com.apple.product-type.application"]
    require({item["name"] for item in targets} == {"SystemEQ for Mac", "ProjectMHelper"} and len(targets) == 2, "Missing application target")
    for target in targets:
        configs = objects[target["buildConfigurationList"]]["buildConfigurations"]
        require(len(configs) == 2 and {objects[key]["name"] for key in configs} == {"Debug", "Release"}, "Missing target configuration")
        for key in configs:
            settings = objects[key]["buildSettings"]
            require(settings["MARKETING_VERSION"] == version, f"Version mismatch in {target['name']}")
            expected_path = "Config/Info.plist" if target["name"] == "SystemEQ for Mac" else "Config/ProjectMHelper/Info.plist"
            require(settings["INFOPLIST_FILE"] in (expected_path, "$(SRCROOT)/" + expected_path), "Unexpected target plist")
            info = plistlib.loads(source(expected_path).encode())
            require(info["CFBundleShortVersionString"] in (version, "$(MARKETING_VERSION)"), "Plist version mismatch")
    changelog = source("CHANGELOG.md")
    headings = list(re.finditer(r"^## \[([^\]\n]+)\].*$", changelog, re.M))
    matches = [i for i, heading in enumerate(headings) if heading[1] == version]
    require(len(matches) == 1, "Missing or duplicate CHANGELOG version")
    index = matches[0]
    require(all(heading[1] == "Unreleased" for heading in headings[:index]), "Release is not the newest CHANGELOG version")
    heading = headings[index]
    require(re.fullmatch(r"## \[" + re.escape(version) + r"\] [—-] \d{4}-\d{2}-\d{2}", heading[0]), "Invalid CHANGELOG heading")
    end = headings[index + 1].start() if index + 1 < len(headings) else len(changelog)
    notes = changelog[heading.end():end].strip()
    require(bool(re.search(r"^- \S", notes, re.M)), "Empty release notes")
    return notes


def successful_run(run, sha, workflow_id, repository):
    require(isinstance(run, dict) and type(run.get("id")) is int and run["id"] > 0, "Invalid CI run")
    require(run.get("head_sha") == sha and run.get("event") == "push" and run.get("head_branch") == "main", "Wrong CI SHA/event/branch")
    require(run.get("workflow_id") == workflow_id and run.get("name") == "Code Quality" and run.get("path", "").split("@")[0] == WORKFLOW, "Wrong CI workflow")
    require(run.get("repository", {}).get("full_name", "").lower() == repository.lower(), "Wrong CI repository")
    require(run.get("status") == "completed" and run.get("conclusion") == "success", "Latest CI run is not successful")
    require(type(run.get("run_attempt")) is int and run["run_attempt"] > 0, "Missing CI attempt")


def ci(root, repository, sha):
    prefix = f"repos/{repository}/actions"
    workflow = api(root, f"{prefix}/workflows/code-quality.yml")
    require(isinstance(workflow, dict) and type(workflow.get("id")) is int and workflow["id"] > 0, "Missing workflow identity")
    require(workflow.get("path") == WORKFLOW and workflow.get("name") == "Code Quality" and workflow.get("state") == "active", "Wrong or disabled workflow")
    query = urlencode({"head_sha": sha, "event": "push", "branch": "main", "per_page": 100})
    runs = collection(api(root, f"{prefix}/workflows/code-quality.yml/runs?{query}", True), "workflow_runs")
    require(bool(runs), "No Code Quality run for exact SHA")
    run = max(runs, key=lambda item: item["id"])
    successful_run(run, sha, workflow["id"], repository)
    jobs = collection(api(root, f"{prefix}/runs/{run['id']}/attempts/{run['run_attempt']}/jobs?per_page=100", True), "jobs")
    require({item.get("name") for item in jobs}.issuperset(JOBS), "Missing required CI jobs")
    for name in JOBS:
        require(sum(item.get("name") == name for item in jobs) == 1, "Ambiguous CI job")
    for job in jobs:
        require(job.get("run_id") == run["id"] and job.get("head_sha") == sha and job.get("run_attempt") == run["run_attempt"], "Wrong CI job identity")
        require(job.get("status") == "completed" and job.get("conclusion") == "success", "Incomplete, skipped or failed CI job")
    after = api(root, f"{prefix}/runs/{run['id']}")
    successful_run(after, sha, workflow["id"], repository)
    require(after["id"] == run["id"] and after["run_attempt"] == run["run_attempt"], "CI changed during validation")
    refreshed = collection(api(root, f"{prefix}/workflows/code-quality.yml/runs?{query}", True), "workflow_runs")
    require(bool(refreshed), "CI disappeared during validation")
    latest = max(refreshed, key=lambda item: item["id"])
    successful_run(latest, sha, workflow["id"], repository)
    require(latest["id"] == run["id"] and latest["run_attempt"] == run["run_attempt"], "New CI run appeared during validation")
    return {"id": run["id"], "attempt": run["run_attempt"], "jobs": sorted(JOBS)}


def check(root, version, revision, repository, require_tag):
    require(re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", version), "Expected canonical X.Y.Z")
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository), "Invalid GitHub repository")
    sha = command(root, "git", "rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}").strip()
    require(re.fullmatch(r"[0-9a-f]{40}", sha), "Invalid commit SHA")
    require(command(root, "git", "rev-parse", "HEAD").strip() == sha, "Checkout differs from requested SHA")
    require(not command(root, "git", "status", "--porcelain", "--untracked-files=normal").strip(), "Working tree is not clean")
    origin = command(root, "git", "remote", "get-url", "origin").strip()
    allowed = {f"https://github.com/{repository}", f"https://github.com/{repository}.git", f"git@github.com:{repository}.git"}
    require(origin in allowed, "Origin differs from requested GitHub repository")
    notes = metadata(root, sha, version)
    tag = f"v{version}"
    message = f"SystemEQ for Mac {tag}"
    if require_tag:
        reference = f"refs/tags/{tag}"
        obj = command(root, "git", "rev-parse", "--verify", reference).strip()
        require(command(root, "git", "cat-file", "-t", obj).strip() == "tag", "Annotated tag required")
        require(command(root, "git", "rev-parse", f"{reference}^{{commit}}").strip() == sha, "Tag points to another commit")
        require(command(root, "git", "for-each-ref", reference, "--format=%(contents)").strip() == message, "Unexpected public tag message")
        remote = api(root, f"repos/{repository}/git/ref/tags/{tag}")
        require(remote.get("ref") == reference and remote.get("object", {}).get("type") == "tag" and remote["object"].get("sha") == obj, "Remote tag differs from validated local tag")
    else:
        require(not command(root, "git", "for-each-ref", f"refs/tags/{tag}", "--format=%(refname)").strip(), "Release tag already exists locally")
        matches = api(root, f"repos/{repository}/git/matching-refs/tags/{tag}")
        require(isinstance(matches, list) and all(isinstance(item, dict) and isinstance(item.get("ref"), str) for item in matches), "Invalid remote tag discovery")
        require(not any(item["ref"] == f"refs/tags/{tag}" for item in matches), "Release tag already exists remotely")
    return {"version": version, "sha": sha, "tag": tag, "tag_message": message, "release_notes": notes, "ci": ci(root, repository, sha)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--require-tag", action="store_true")
    args = parser.parse_args()
    try:
        result = check(Path.cwd(), args.version, args.sha, args.repo, args.require_tag)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError, IndexError, AttributeError, SyntaxError) as error:
        print(f"Release check failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
