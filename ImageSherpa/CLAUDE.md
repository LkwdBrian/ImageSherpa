# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this project is

A native macOS app (working title: **Sherpa** — final name still undecided,
candidates are Sherpa, Wrangler, Formulate, Command Deck) that gives GUI
access to command-line power tools (osxphotos, ImageMagick, more later)
without requiring the user to memorize flags or use Terminal directly.
Target user is technically comfortable but doesn't want to learn CLI syntax
for tools they use occasionally.

Owner: Brian Cosgrove, So Wired Productions. Distributed as a notarized DMG,
not the Mac App Store (see "Distribution constraint" below, this affects
what code is even allowed to do).

## Distribution constraint (read this before touching entitlements)

This app **cannot** ship on the Mac App Store, because it needs to:
- Run `brew install` / `brew uninstall` for arbitrary formulae
- Shell out to binaries outside the app's own container (`/opt/homebrew/bin`,
  `/usr/local/bin`)

Both are blocked by App Sandbox. **App Sandbox must stay off** in
Signing & Capabilities. Don't suggest re-enabling it to "improve security
posture" without flagging that it breaks the core feature set first.

Ship path: Developer ID Application signing → notarize via
`xcrun notarytool` → distribute as a DMG. Auto-updates via Sparkle once
there's a v1.0 to update from.

## Architecture

```
cli-gui-app/
├── Registry/              JSON files, one per supported CLI tool.
│                           Adding a new tool = adding a new JSON file here.
│                           No Swift changes needed for a new tool unless it
│                           needs a field type beyond text/quoted_text/folder/file.
├── Scripts/                Bundled Python helper scripts, invoked via
│                           osxphotos's --query-function (or similar hooks
│                           on other tools later). Ship as a folder reference
│                           in Xcode so they land in the app bundle verbatim.
├── Sources/
│   ├── ToolDefinition.swift   Codable models for the registry JSON + loader.
│   ├── HomebrewManager.swift  Install/uninstall/version-check for brew
│   │                          formulae. Build and stabilize this FIRST,
│   │                          everything else depends on it.
│   └── RecipeRunner.swift     Builds the final shell command from a
│                              Recipe + user field values, then executes it.
└── README.md                 Fuller build-order and setup notes.
```

## Core data model

- **ToolDefinition**: one CLI tool (osxphotos, imagemagick). Has an
  install method (currently only `"brew"` is implemented), a formula name,
  a version-check command, and a list of Recipes.
- **Recipe**: one canned task ("Export Photos by Album," "Best Photos of a
  Place"). Has a `template` string with `{fieldName}` placeholders and a
  list of `RecipeField`s that the UI renders as a form.
- **RecipeField.type** matters a lot, get this right when adding fields:
  - `text` — short values with no spaces (widths, percentages, dates,
    extensions). Left **unquoted** in the built command, needed so glob
    patterns like `*.jpg` still expand.
  - `quoted_text` — free text that may contain spaces (names, keywords,
    city names, watermark text). Always default to this for anything
    name-like; using `text` for a value that turns out to contain a
    space (e.g. "New York") silently breaks the command at runtime.
  - `folder` / `file` — paths, also auto-quoted.

## The `{scriptsDir}` token

Some recipes need real filtering logic a CLI flag can't express (example:
"top 20% of photos by aesthetic score," which osxphotos has no flag for).
These call a bundled Python script via `--query-function`, and pass
user-configurable parameters through an **environment variable** set right
before the command runs, since `--query-function` doesn't accept its own
arguments:

```
env OSXPHOTOS_TOP_PERCENT={percent} osxphotos export {destination} --place {city} --query-function {scriptsDir}/photo_scoring.py::top_percent --update
```

`{scriptsDir}` is a **built-in token resolved by `RecipeRunner`**, not a
`RecipeField`. It always resolves to the bundled `Scripts/` folder's actual
path in the running app. Any new recipe needing a bundled script should
reference `{scriptsDir}` the same way rather than hardcoding a path, dev
builds and notarized app bundles resolve resources differently.

## Build order (do not reorder without reason)

1. **Dependencies tab** — `HomebrewManager` wired to a SwiftUI List: is
   Homebrew installed, per-tool install/uninstall/upgrade buttons, current
   vs latest version shown. Fully testable standalone. Everything else
   assumes this works.
2. **Tool detail view** — lists a tool's recipes.
3. **Recipe form view** — generates form fields from `Recipe.fields`,
   folder/file pickers via `NSOpenPanel`, live command preview via
   `RecipeRunner.buildCommand` (show the user the real command before
   running it, this is partly a teaching tool, not just a black box),
   Run button streaming output via `RecipeRunner.execute`.
4. **Run log** — timestamped history of what ran and its output.

## Known gaps / things not to "helpfully" fix without asking

- `versionRegex` exists in the registry schema but isn't wired into a
  parser yet. `HomebrewManager.installedVersion` currently parses
  `brew list --versions` output directly instead, more reliable for most
  formulae. Keep the regex as a documented fallback path, don't rip it out.
- No support yet for tools not installable via Homebrew (pip-only tools,
  for instance). `installMethod` is a string for exactly this reason,
  add a parallel manager (e.g. `PipManager`) rather than overloading
  `HomebrewManager` when this is needed.
- No `NSOpenPanel` wrapper for folder/file fields yet, intentionally left
  out of the initial scaffold since it's boilerplate likely already
  available from other projects.
- osxphotos CLI flags referenced in recipes (`--place`, `--person`,
  `--year`, `--query-function`) were sourced from documentation and may
  drift across osxphotos versions. Verify against `osxphotos help export`
  on the actual installed version before assuming a recipe template is
  correct, don't just trust the JSON.

## Conventions

- New CLI tool support → new `Registry/*.json` file. Don't hardcode
  tool-specific logic in Swift; if a tool needs something the current
  schema can't express, extend the schema (and this file), don't special-case it.
- New bundled script → add to `Scripts/`, document its env-var parameters
  in a docstring the same way `photo_scoring.py` does, and reference it via
  `{scriptsDir}` from the relevant recipe template.
- Recipes should default to the 80% use case. Resist adding a field for
  every possible flag a CLI tool supports, that defeats the point of the app.
- Show the user the real command before running it. Never silently build
  and execute without a preview step, that's a deliberate product decision
  (trust-building + incidental CLI education), not an oversight to streamline away.

## Style

- Swift: standard Swift API Design Guidelines naming, doc comments on
  anything non-obvious, prefer `async`/`await` over completion handlers
  (see `HomebrewManager` for the established pattern).
- No em dashes or double hyphens in comments or commit messages, use
  commas, colons, or restructure the sentence.
- Prose in this file and in commit messages: concise, no filler phrasing
  ("it's worth noting," "at the end of the day," etc.), state the thing directly.
