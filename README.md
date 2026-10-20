# AEM Conest

<img src="Resources/AppIcon.svg" width="128" align="right" alt="AEM Conest icon">

A macOS app for reviewing **AEM as a Cloud Service** CDN logs: it filters out noise
(bots, static assets, internal paths) and counts content requests by day, domain or date
range. Drop one or more files (`.csv`, `.log`, `.txt`…) and get results without touching
the terminal. Built for files of several gigabytes.

## Disclaimer

**AEM Conest is an independent, unofficial tool. It is not an Adobe product and is not
endorsed, supported or guaranteed by Adobe, even though its developer is an Adobe employee.**

- It is **not a 100% guarantee of anything**. It can help you approximate a real figure, but
  its results must not be considered accurate or authoritative.
- Results are request counts computed with text filters over the log files you provide. They
  are not unique visitors or sessions, and the filters may include or exclude traffic
  incorrectly (they do not remove all bots or automated traffic).
- Do not use these figures as a billing, contractual or usage-entitlement metric. For official
  numbers, use Adobe's own reporting and support channels.
- The software is provided "as is", without warranty of any kind (see the [MIT License](LICENSE)).

The same notice is available inside the app (sidebar and *About AEM Conest*).
See also [DISCLAIMER.md](DISCLAIMER.md).

## Scope and roadmap

**Current scope:** AEM Conest only calculates classic **Content Requests**, i.e. content delivery
requests (HTML pages). It does not calculate API Calls yet.

**Roadmap:**

- [ ] Calculate **API Calls** as well (e.g. `.json` and other API requests, which the current
  cleaning flow deliberately excludes because it requires `html`). The ratio between API Calls
  and Content Requests is **5 to 1** (5 API Calls correspond to 1 Content Request), so both
  metrics should be reported together and be comparable.

As with every figure produced by this tool, API Call estimates will be approximations
(see the [Disclaimer](#disclaimer)).

## Sections

- **Dashboard**: analyzes one or more files in a single pass, then lets you filter by date
  and domain instantly. Includes a per-day chart (stackable by domain), top domains, a
  day × domain heatmap, sortable tables and CSV export.
- **Process**: runs the script flow on the dropped files and shows the exact command and
  output of every step.
- **Flow**: ordered list of steps (script + arguments). Steps can be reordered, disabled,
  deleted and added. Variables: `{input}`, `{cleaned}`, `{dir}`, `{name}`, `{start}`, `{end}`.
- **Scripts**: editor for the `.sh` files. Create new scripts and add them to the flow.

Scripts and the flow are stored in `~/Library/Application Support/AEM Conest/`.

## What cleaning does (`clean.sh`)

Lines matching any of the following (case-insensitive, anywhere in the line) are dropped:

- **Bots, crawlers, monitoring, proxies and AI agents**: Googlebot, Bingbot, AhrefsBot,
  SemrushBot, Applebot, ClaudeBot, ChatGPT, Perplexity, StatusCake, SiteImprove, etc.
- **Internal AEM paths**: `/etc.clientlibs/`, `/api/graphql`, `/content/experience-fragments/`.
- **Resources**: images, video, `.css`, `.js`, `.mjs`.

Only lines containing both `GET,200` and `html` (case-sensitive) are kept. The full list is in
[`default-scripts/clean.sh`](default-scripts/clean.sh). These filters do not guarantee the
removal of all automated traffic.

## Expected input format

- The date occupies characters 2 through 11 of each line in `YYYY-MM-DD` format
  (e.g. a line starting with `"2026-09-21`).
- The domain is the last comma-separated field.
- Each line is one request, with no header row. This is not a full CSV parser (no general
  quoting or multiline records).

## Requirements

- macOS 14 or later. Uses only system tools (`bash`, `grep`, `awk`, `sort`, `perl`).
- To build: Xcode / Swift 5.9+.

## Build

```bash
./build.sh   # produces dist/AEM Conest.app (universal) and dist/AEM-Conest-1.0.dmg
```

The resulting app is ad-hoc signed. On another Mac, macOS asks for confirmation the first
time: right-click → **Open**, or *System Settings → Privacy & Security → Open Anyway*.

To sign with a Developer ID and notarize, see the header of `build.sh`
(`SIGN_IDENTITY` and `NOTARY_PROFILE`).

## Layout

```
Sources/CDNFiltering/   SwiftUI code (Dashboard, Process, Flow, Scripts)
default-scripts/        original scripts; tools/gen_defaults.sh embeds them in the app
Resources/AppIcon.svg   icon; tools/make_icon.sh generates the .icns
build.sh                builds, packages, signs and creates the .dmg
```

## License

[MIT](LICENSE)
