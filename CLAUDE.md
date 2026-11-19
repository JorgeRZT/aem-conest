# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AEM Conest is a macOS 14+ SwiftUI app (SwiftPM executable target `CDNFiltering`, no external dependencies) that estimates **Content Requests** from AEM as a Cloud Service CDN logs. The heavy lifting is done by shell pipelines (`bash`, `grep`, `awk`, `sort`, `perl`) over multi-gigabyte files; Swift only orchestrates processes and renders results.

The product name is "AEM Conest"; the target, executable and source folder keep the legacy name `CDNFiltering`.

## Commands

```bash
swift build                    # debug build
swift run                      # run the app unbundled (no Info.plist, so no version label and no update check)
./build.sh                     # release: universal .app + dist/AEM-Conest-<version>.dmg (ad-hoc signed)
tools/gen_defaults.sh          # regenerate DefaultScripts.swift after editing default-scripts/*.sh
tools/make_icon.sh             # regenerate Resources/AppIcon.icns from AppIcon.svg
```

There is no test target and no linter. To check behaviour manually, drop `test/cdn-2026-09.csv` (synthetic logs; the README screenshots were made from it) or `test/cdn-2026-09-aemcs.log` (a sample of the same data in the AEMaaCS JSON format) onto the app. The default scripts can also be run directly, e.g. `bash default-scripts/clean.sh test/cdn-2026-09.csv /tmp/out.csv`.

Signed/notarized builds: `SIGN_IDENTITY=... NOTARY_PROFILE=... ./build.sh` (see the header of `build.sh`).

## Architecture

### Scripts are embedded, then copied to a user-editable folder

- `default-scripts/*.sh` is the source of truth. `tools/gen_defaults.sh` embeds them as raw string literals in `Sources/CDNFiltering/DefaultScripts.swift`, which is **generated but committed**: never edit it by hand, and rerun the generator (or `./build.sh`, which calls it) after changing a script. The generator has a hard-coded file list, so a new default script must be added there and, if it belongs in the flow, to `FlowStep.defaultFlow` in `Models.swift`.
- At launch `ScriptStore` copies any missing default into `~/Library/Application Support/AEM Conest/scripts/`. Existing files are never overwritten, so a changed default only reaches an existing install through "reset to default" in the Scripts section (or by deleting that folder). Keep this in mind when testing script changes.
- The flow (ordered `FlowStep`s: script name + argument template) persists to `flow.json` in the same folder via `FlowStore`.

### Three independent execution paths

1. **Process / Flow** (`Runner`, `ProcessView`, `FlowView`): runs each enabled step per file, sequentially, showing the exact command and streamed output. Argument templates are split on whitespace and each token has `{input}`, `{cleaned}`, `{dir}`, `{name}`, `{start}`, `{end}` substituted (`FlowVariable.resolve`), so every token becomes one argv entry and paths with spaces need no quoting. Steps using `{start}`/`{end}` are skipped when no date range is enabled; after a failure the remaining steps are skipped.
2. **Dashboard** (`DashboardModel`, `DashboardView`): does not use the flow. It optionally runs `clean.sh` (reusing `<name>_clean.csv` when it is newer than the source), then runs a single inline `awk` program (`DashboardModel.awkProgram`) that emits `day \t domain \t count`. Everything after that (date/domain filters, stacking, heatmap, CSV export) is in-memory in `recompute()`, which is why filtering is instant. Setters use `suspendRecompute` to batch several filter changes into one recompute.

3. **Content Requests** (`ContentAnalysisModel`, `ContentAnalysisView`): does not use the flow or `clean.sh`. It runs `content-requests.sh` on the **raw** log, which classifies every line as counted (consumer class: browser, monitoring, http-library, unclassified-bot, empty-ua) or excluded (reason), following Adobe's Content Requests documentation, and writes tagged TSV aggregates to `<name>_analysis.tsv` (reused while newer than both the log and the script). The table layout is documented in the script header and parsed in `ContentAnalysisModel.load`; keep both in sync. Its rules are deliberately wider than `clean.sh` (JSON and every 1xx/2xx count; `/libs`, `/system/probes/health` and the pod warm-up do not), and it duplicates `clean.sh`'s bot lists on purpose, so a change to a list must be made in both scripts. Filtering, the waterfall, the path trees and the insights are computed in memory in `recompute()`. HTML vs JSON is decided only by the response Content-Type in the script (`type` column), and paths are split into `pages` (HTML) and `json`. JSON calls weigh 1/5 (`apiCallsPerContentRequest`, Adobe's internal rule): `contentRequests = pageViews + jsonCalls / 5` (integer division, so only complete groups of 5 add one), and the class, day and path shares use that weighted total. `counted` stays the unweighted number of counted lines; user agent and IP shares use it because those tables do not carry the type.

The Dashboard and Content Requests share the dropped files (`SourceStore`) and the date/domain `FilterBar`, which is generic over `DateDomainFilterable`.

All paths go through `ShellExec`, which launches the child via `perl -e 'setpgrp(0,0); exec @ARGV'` so the whole pipeline is in its own process group and cancel can `kill(-pgid)`.

### Log format assumptions (shared by scripts and the dashboard awk)

- Legacy CSV: the date is characters 2–11 of each line (`"YYYY-MM-DD…`), the domain is the last comma-separated field, one request per line, no header. This is deliberately not a CSV parser.
- AEM as a Cloud Service JSON (one object per line): any line starting with `{`. `clean.sh` rewrites it to the legacy CSV layout (`normalize()`, regex per key, not a JSON parser) **before** filtering, so the cleaned file is always legacy CSV and the filters behave identically for both formats. Only `clean.sh`, `content-requests.sh` and `DashboardModel.awkProgram` understand JSON; the other default scripts expect `{cleaned}`.
- `clean.sh` drops lines matching the bot/internal-path/static-asset pattern (case-insensitive) and keeps only lines containing both `GET,200` and `html`. A change to these rules changes every reported number, and the "What cleaning does" section of the README describes them.
- Numbers are displayed with `.` as the thousands separator, both in the scripts (the `perl` one-liner) and in Swift (`Fmt.n`).

### Versioning and release

- `VERSION` (CalVer `YYYY.MM.DD`) is the single source of truth; `build.sh` writes it into the generated `Info.plist`. `AppInfo.version` reads it back and is nil under `swift run`, which disables the update prompt.
- `UpdateChecker` asks the GitHub Releases API for `JorgeRZT/aem-conest` on launch and compares tags numerically.
- Publishing: bump `VERSION`, run `./build.sh`, commit the `.dmg` to the `dist` branch, update the download links and version badge in `README.md` (the version appears there several times), tag `v<version>` and create a GitHub release with the `.dmg` attached. `dist/` is git-ignored on `main`.

## Conventions

- All UI text, comments and docs are in English.
- The disclaimer (unofficial tool, approximate figures, not a billing metric) lives in three places that must stay in sync: `Disclaimer.swift`, `DISCLAIMER.md` and the README.
- Current scope is Content Requests only; API Calls are on the roadmap (ratio 5 API Calls : 1 Content Request) and are intentionally excluded by `clean.sh` today.
- `.gitignore` excludes `*.csv`, `*.log`, `*.txt` and `*.tsv` (real customer logs and their `_analysis.tsv` aggregates must never be committed); `test/cdn-2026-09.csv` and its JSON-format sample `test/cdn-2026-09-aemcs.log` are the only exceptions.
