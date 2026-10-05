#!/usr/bin/env python3

import argparse
import ast
import os
import re
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


EXTENSIONS = {".py", ".sh", ".bash", ".zsh"}
HOOKS = {
    "applypatch-msg", "commit-msg", "post-applypatch", "post-checkout",
    "post-commit", "post-merge", "post-receive", "post-rewrite", "post-update",
    "pre-applypatch", "pre-auto-gc", "pre-commit", "pre-merge-commit", "pre-push",
    "pre-rebase", "pre-receive", "prepare-commit-msg", "push-to-checkout",
    "sendemail-validate", "update",
}


class ScanError(Exception):
    pass


@dataclass(frozen=True)
class Token:
    value: str
    kind: str
    line: int
    substitution: bool = False
    start: int = 0
    end: int = 0


def git_output(root, *arguments):
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *arguments],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ScanError(f"Git command failed: {error}") from error
    if result.returncode:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ScanError(f"Git command failed ({result.returncode}): {detail}")
    return result.stdout


def repository_root(argument):
    try:
        requested = Path(argument).expanduser().resolve(strict=True) if argument else Path(__file__).resolve().parent
        if not requested.is_dir():
            raise ScanError(f"Repository root is not a directory: {requested}")
        output = git_output(requested, "rev-parse", "--show-toplevel")
        if not output.endswith(b"\n") or not output[:-1]:
            raise ScanError("Git returned an empty or malformed repository root")
        reported = Path(os.fsdecode(output[:-1]))
        if not reported.is_absolute() or not reported.is_dir():
            raise ScanError(f"Git returned an invalid repository root: {str(reported)!r}")
        root = reported.resolve(strict=True)
        if argument and requested != root:
            raise ScanError(f"Expected repository root {root}, received {requested}")
        return root
    except (OSError, ValueError) as error:
        raise ScanError(f"Invalid repository root: {error}") from error


def selected_file(relative):
    return relative.suffix.lower() in EXTENSIONS or (relative.parts[0] == ".githooks" and relative.name in HOOKS)


def repository_files(root):
    output = git_output(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
    if output and not output.endswith(b"\0"):
        raise ScanError("Git returned a malformed NUL-delimited file list")
    for raw in sorted(set(output.split(b"\0")) - {b""}):
        relative = Path(os.fsdecode(raw))
        if not relative.parts or relative.is_absolute() or ".." in relative.parts:
            raise ScanError(f"File escapes repository: {relative!s}")
        if not selected_file(relative):
            continue
        candidate = root / relative
        try:
            resolved = candidate.resolve(strict=True)
            if not resolved.is_relative_to(root):
                raise ScanError(f"Symlink escapes repository: {relative!s}")
            metadata = resolved.stat()
            if not stat.S_ISREG(metadata.st_mode):
                raise ScanError(f"Not a regular source file: {relative!s}")
            if not metadata.st_mode & (stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH):
                raise ScanError(f"No read permission bits: {relative!s}")
        except OSError as error:
            raise ScanError(f"Cannot inspect {relative!s}: {error}") from error
        if candidate == Path(__file__).absolute():
            continue
        yield relative, candidate


def python_candidates(content, relative):
    try:
        compile(content, str(relative), "exec")
        tree = ast.parse(content, filename=str(relative))
    except (SyntaxError, ValueError, RecursionError) as error:
        raise ScanError(f"Python parse failed in {relative!s}: {error}") from error
    findings = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.ExceptHandler):
            continue
        empty = all(
            isinstance(statement, ast.Pass)
            or (isinstance(statement, ast.Expr) and isinstance(statement.value, ast.Constant)
                and (statement.value.value is Ellipsis or isinstance(statement.value.value, str)))
            for statement in node.body
        )
        if not empty:
            continue
        types = list(ast.walk(node.type)) if node.type is not None else []
        broad = node.type is None or any(
            (isinstance(value, ast.Name) and value.id in {"Exception", "BaseException"})
            or (isinstance(value, ast.Attribute) and value.attr in {"Exception", "BaseException"})
            for value in types
        )
        rule = "EXCEPT_PASS_BROAD" if broad else "EXCEPT_PASS_TYPED"
        description = "Empty bare/broad exception handler" if broad else "Empty typed exception handler; review expected-error semantics"
        findings.append((node.lineno, rule, description))
    return findings


def shell_tokens(content):
    tokens = []
    index = 0
    line = 1
    pending = []
    heredoc_operator = None
    operators = ("<<<", "<<-", "&&", "||", ">>", "<<", ";;", ";", "|", "&", ">", "<", "(", ")", "{", "}")
    while index < len(content):
        char = content[index]
        if char == "\n":
            tokens.append(Token("\n", "operator", line, start=index, end=index + 1))
            index += 1
            line += 1
            for delimiter, strip_tabs in pending:
                found = False
                while index < len(content):
                    end = content.find("\n", index)
                    end = len(content) if end == -1 else end
                    value = content[index:end]
                    index = end + (end < len(content))
                    line += end < len(content)
                    if (value.lstrip("\t") if strip_tabs else value) == delimiter:
                        found = True
                        break
                if not found:
                    raise ScanError(f"Unterminated shell heredoc {delimiter!r}")
            pending.clear()
            continue
        if char.isspace():
            index += 1
            continue
        if char == "#":
            end = content.find("\n", index)
            index = len(content) if end == -1 else end
            continue
        if content.startswith("\\\n", index):
            index += 2
            line += 1
            continue
        operator = next((value for value in operators if content.startswith(value, index)), None)
        if operator:
            tokens.append(Token(operator, "operator", line, start=index, end=index + len(operator)))
            if operator in {"<<", "<<-"}:
                heredoc_operator = operator
            index += len(operator)
            continue
        start_line = line
        start_index = index
        value = []
        substitution = False
        while index < len(content):
            char = content[index]
            if char.isspace() or any(content.startswith(op, index) for op in operators):
                break
            if char == "\\":
                index += 1
                if index == len(content):
                    raise ScanError("Trailing shell escape")
                if content[index] == "\n":
                    line += 1
                else:
                    value.append(content[index])
                index += 1
                continue
            if char in {"'", '"'}:
                quote = char
                index += 1
                closed = False
                while index < len(content):
                    char = content[index]
                    if char == quote:
                        index += 1
                        closed = True
                        break
                    if quote == '"' and content.startswith("$(", index):
                        substitution = True
                    if quote == '"' and char == "`":
                        substitution = True
                    if quote == '"' and char == "\\" and index + 1 < len(content):
                        index += 1
                        char = content[index]
                    value.append(char)
                    line += char == "\n"
                    index += 1
                if not closed:
                    raise ScanError(f"Unterminated shell quote at line {start_line}")
                continue
            if char == "`":
                substitution = True
            value.append(char)
            index += 1
        token = Token("".join(value), "word", start_line, substitution, start_index, index)
        tokens.append(token)
        if heredoc_operator:
            pending.append((token.value, heredoc_operator == "<<-"))
            heredoc_operator = None
    if pending or heredoc_operator:
        raise ScanError("Unterminated shell heredoc")
    return tokens


def sudo_noninteractive(arguments):
    short_values = {"u", "g", "h", "p", "C", "T", "r", "t", "D", "R"}
    short_flags = set("AbEeHikKlnPSsVv")
    long_values = {"--user", "--group", "--host", "--prompt", "--close-from", "--command-timeout", "--role", "--type", "--chdir", "--chroot"}
    long_flags = {"--askpass", "--background", "--preserve-env", "--edit", "--set-home", "--login", "--remove-timestamp", "--reset-timestamp", "--list", "--preserve-groups", "--stdin", "--shell", "--version", "--validate"}
    index = 0
    while index < len(arguments):
        value = arguments[index]
        if value == "--" or not value.startswith("-"):
            return False
        if value == "--non-interactive":
            return True
        if value.startswith("--"):
            option, separator, attached = value.partition("=")
            if option in long_values:
                if not separator and index + 1 >= len(arguments):
                    return False
                index += 1 if separator else 2
                continue
            if option not in long_flags or (separator and option != "--preserve-env"):
                return False
            index += 1
            continue
        consumed = 1
        for position, option in enumerate(value[1:], start=1):
            if option == "n":
                return True
            if option in short_values:
                if position == len(value) - 1:
                    if index + 1 >= len(arguments):
                        return False
                    consumed = 2
                break
            if option not in short_flags:
                return False
        index += consumed
    return False


def validate_shell(content, relative):
    first_line = content.splitlines()[0] if content else ""
    zsh = relative.suffix.lower() == ".zsh" or re.match(r"^#!.*(?:/|\s)zsh(?:\s|$)", first_line)
    command = ["zsh", "-f", "-n"] if zsh else ["bash", "--noprofile", "--norc", "-n"]
    environment = {name: value for name, value in os.environ.items() if name not in {"BASH_ENV", "ENV", "ZDOTDIR"}}
    try:
        result = subprocess.run(command, input=content, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ScanError(f"Shell validator failed for {relative!s}: {error}") from error
    if result.returncode:
        raise ScanError(f"Shell validation failed in {relative!s} ({result.returncode}): {result.stderr.strip()}")


def shell_candidates(content, relative):
    validate_shell(content, relative)
    try:
        tokens = shell_tokens(content)
    except ScanError as error:
        raise ScanError(f"Shell tokenization failed in {relative!s}: {error}") from error
    findings = []
    command_start = True
    local_command = False
    for index, token in enumerate(tokens):
        value = token.value
        if token.kind == "operator":
            if value == "||":
                following = index + 1
                while following < len(tokens) and tokens[following].value == "\n":
                    following += 1
                if following < len(tokens) and tokens[following].kind == "word" and tokens[following].value in {"true", ":"}:
                    findings.append((token.line, "DEFENSIVE_THEATER_PIPE", "Failure ignored through unconditional success; review intent"))
            if value in {"\n", ";", ";;", "&&", "||", "|", "&", "(", "{"}:
                command_start = True
                local_command = False
            continue
        if value == "2" and content[token.start:token.end] == "2" and index + 2 < len(tokens) and token.end == tokens[index + 1].start and tokens[index + 1].kind == "operator" and tokens[index + 1].value in {">", ">>"} and tokens[index + 2].value == "/dev/null":
            findings.append((token.line, "DEFENSIVE_THEATER_STDERR", "stderr suppressed; review status handling and diagnostics in context"))
        if command_start:
            if value in {"if", "elif", "then", "else", "do", "while", "until", "!", "command", "exec"} or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", value):
                continue
            command_start = False
            local_command = value == "local"
            if value.rsplit("/", 1)[-1] == "sudo":
                arguments = []
                for argument in tokens[index + 1:]:
                    if argument.kind == "operator":
                        break
                    arguments.append(argument.value)
                if not sudo_noninteractive(arguments):
                    findings.append((token.line, "SUDO_HANG", "sudo without a noninteractive option; review surrounding TTY guard"))
        if local_command and "=" in value and (token.substitution or (value.endswith("$") and index + 1 < len(tokens) and tokens[index + 1].value == "(")):
            findings.append((token.line, "LOCAL_MASKING", "local assignment with command substitution may mask command status"))
    return findings


def audit_repository(root):
    findings = []
    scanned = 0
    for relative, candidate in repository_files(root):
        try:
            content = candidate.read_bytes().decode("utf-8")
        except (OSError, UnicodeError) as error:
            raise ScanError(f"Cannot read/decode {relative!s}: {error}") from error
        candidates = python_candidates(content, relative) if relative.suffix.lower() == ".py" else shell_candidates(content, relative)
        scanned += 1
        findings.extend((str(relative), line, rule, description) for line, rule, description in candidates)
    if scanned == 0:
        raise ScanError("INCOMPLETE: scanned 0 applicable source files")
    return scanned, findings


def main(argv=None):
    parser = argparse.ArgumentParser(description="Report heuristic review candidates; this does not prove safety.", epilog="Shell syntax validation does not execute commands. Heuristics do not fully analyze nested/quoted command substitutions or dynamic heredoc expansion.", allow_abbrev=False)
    parser.add_argument("root", nargs="?", help="Exact Git repository root; defaults to this script's repository")
    parser.add_argument("--check", action="store_true", help="Return 1 when review candidates exist, 2 for incomplete/error scans")
    arguments = parser.parse_args(argv)
    try:
        root = repository_root(arguments.root)
        scanned, findings = audit_repository(root)
    except ScanError as error:
        print(f"INCOMPLETE: {error}", file=sys.stderr)
        return 2
    print(f"Scanned {scanned} applicable source files in {str(root)!r}.")
    if findings:
        print(f"Review candidates: {len(findings)}. Contextual review is required; these are not validated defects.")
        for relative, line, rule, description in findings:
            print(f"{relative!r}:{line}: {rule}: {description}")
        return 1 if arguments.check else 0
    print("No review candidates detected by these heuristics; this is not a safety verdict.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
