# Security Policy

## Supported versions

Security fixes ship in the latest release. Older versions are not patched —
please update to the newest [release](https://github.com/denzam/SystemEQ-for-Mac/releases)
before reporting an issue.

## Reporting a vulnerability

Please report security issues privately via
[GitHub Security Advisories](https://github.com/denzam/SystemEQ-for-Mac/security/advisories/new),
not as a public issue. Include the affected version, what you observed, and
reproduction steps if you have them.

This is a single-maintainer hobby project — expect an initial response within a
week or two rather than within hours.

## Security model

SystemEQ processes system audio locally. It has **no telemetry, no analytics,
and no account system**, and never uploads user data. Network access is limited
to three fixed HTTPS endpoints:

- the AutoEQ preset repository (preset index and preset files),
- the ProjectM visualizer preset archive,
- GitHub Releases (update check).

The app is **not sandboxed** — CoreAudio/AUHAL virtual audio routing is
incompatible with the App Sandbox. It is distributed ad-hoc signed and without
Apple notarization, which is why Gatekeeper requires a right-click → Open on
first launch. Install only from the official GitHub Releases page or the
Homebrew tap.

## Audit history

### 2026-07 — automated security audit

An automated security scan of the full codebase reported 14 findings: 1 medium
and 13 low severity. No finding involved user data exposure, remote code
execution, or network-reachable attack surface — the app exposes no listening
network service, and its ProjectM IPC socket is restricted to the current user.

Fixed in 1.1.2:

| Severity | Issue | Fix |
|---|---|---|
| Medium | GitHub Actions were referenced by mutable version tags (`@v6`), so a compromised action publisher could have altered the workflow that builds and publishes release artifacts | All workflow dependencies pinned to reviewed full commit SHAs |
| Low | Audio render callbacks sized their writes from the frame count supplied by CoreAudio without validating it against the preallocated buffer capacity; a device violating the AudioUnit contract could have written past the allocation | Both callbacks now verify the frame count and bail out real-time-safely |
| Low | Imported `.txt` presets were parsed without bounds — an arbitrarily large file blocked the UI while being read, and non-finite or extreme gain/preamp values could reach the DSP through paths that skipped the existing clamp | Import caps file size and filter count and drops invalid bands; the engine sanitizes every gain and preamp value before configuring filters |

Accepted as known risk (documented, not fixed):

The remaining findings are supply-chain and resource-exhaustion scenarios whose
exploitation requires compromise of an upstream project (AutoEQ, ProjectM,
Homebrew) or another local account on the same Mac. For a single-user local
audio utility, the mitigations cost more complexity than the risk warrants:

- Homebrew build tools in CI are installed unpinned (`swiftlint`, `swiftformat`,
  `create-dmg`) — Homebrew does not support reproducible version pinning without
  vendoring binaries.
- Remote AutoEQ index refresh and the ProjectM preset archive download lack hard
  byte and entry budgets; both use fixed HTTPS endpoints.
- The ProjectM preset archive is fetched from a mutable branch rather than a
  pinned commit with a verified checksum.
- `Scripts/setup_projectm.sh` (developer-only, requires explicit execution and a
  sudo confirmation) builds from a mutable upstream tag. The predictable `/tmp`
  paths reported in the same finding were fixed after the audit: the script now
  does all of its work in a private `mktemp -d` directory removed on exit.

These are re-evaluated at each audit. If you believe one is more exploitable in
practice than assessed here, please report it.
