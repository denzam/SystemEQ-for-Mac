# Third-Party Notices

SystemEQ for Mac depends on or integrates with the following third-party
software. Each component retains its own license and copyright. This file
satisfies the attribution requirements of those licenses.

## Bundled / linked at runtime

### ProjectM
- Source: https://github.com/projectM-visualizer/projectm
- License: **LGPL-2.1-or-later**
- Used by: `ProjectMHelper` target (visualizer rendering).
- Compliance: ProjectM is dynamically linked. Users have the right to
  relink against a modified ProjectM. Source for the exact ProjectM
  version used in each release is preserved in this repository's release
  notes and is available upstream.

### Accelerate / vDSP
- Apple system framework. No redistribution beyond what macOS provides.

### SQLite
- Source: https://www.sqlite.org
- License: **Public domain**.
- Used by: `Data/EQDatabase.swift`. Linked against the system SQLite that
  ships with macOS.

## Required external software (not bundled)

### BlackHole 2ch
- Source: https://github.com/ExistentialAudio/BlackHole
- License: **GPL-3.0**
- Role: virtual audio driver. Installed separately by the user via the
  Setup Assistant; SystemEQ does not redistribute BlackHole.

## Data

### AutoEQ database
- Source: https://github.com/jaakkopasanen/AutoEq
- License: **MIT** (project), measurements under their respective
  original licenses (oratory1990, Crinacle, Harman, etc.).
- Bundled artifact: `Resources/EQDatabase.db` — a SQLite snapshot derived
  from the AutoEQ project. Attribution preserved in the database and in
  the README.

### oratory1990 measurements
- Source: https://www.reddit.com/r/oratory1990/
- Used as a measurement source within the AutoEQ database. Not
  redistributed independently.

## SystemEQ itself

SystemEQ for Mac is © 2025–2026 Denys Zamorniak and is distributed under
the **GNU General Public License v3.0** — see [`LICENSE`](LICENSE).

If you redistribute SystemEQ, you must comply with GPLv3, including
making the corresponding source code available under the same license.
