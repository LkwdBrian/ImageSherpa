# CLI Companion (working title — pick from: Sherpa, Wrangler, Formulate, Command Deck)

A native macOS app that gives GUI access to command-line power tools (osxphotos,
ImageMagick, and anything else you register) without requiring users to memorize
flags or touch Terminal.

## Why not the Mac App Store

Sandboxing on the App Store blocks arbitrary process execution and Homebrew
install/uninstall calls. This app needs both, so it ships as a **notarized DMG**
distributed directly (Gumroad, direct download, or your own site). Use Sparkle
for auto-updates.

## Project structure

```
cli-gui-app/
├── Registry/              → JSON files, one per supported CLI tool
│   ├── osxphotos.json
│   └── imagemagick.json
├── Scripts/               → bundled Python helper scripts, invoked via --query-function etc.
│   └── photo_scoring.py   → score-based filtering (used by the "Best Photos of..." recipes)
├── Sources/
│   ├── ToolDefinition.swift    → Codable models + registry loader
│   ├── HomebrewManager.swift   → install/uninstall/version-check for brew formulae
│   └── RecipeRunner.swift      → builds & executes commands from recipe templates
└── README.md
```

## Field types

`RecipeField.type` in a registry JSON file must be one of:

- `text` — short values with no spaces expected (widths, percentages, dates,
  file extensions). Left unquoted in the built command so glob patterns like
  `*.jpg` still expand correctly.
- `quoted_text` — free text that may contain spaces (city names, person names,
  keywords, watermark text). Automatically wrapped in quotes.
- `folder` / `file` — paths, also automatically quoted.

Getting this wrong for a value that can contain spaces (e.g. defining a city
field as `text` instead of `quoted_text`) will silently break on any
multi-word value like "New York" or "Los Angeles," so default to
`quoted_text` for anything name-like.

## Bundled scripts and the `{scriptsDir}` token

Some recipes need real filtering logic that a flat command-line flag can't
express, most notably anything based on Apple's on-device aesthetic score
(`photo.score.overall`), since `osxphotos` has no `--min-score` flag. These
use `--query-function`, which only accepts the already-filtered photo list
and returns a filtered list, no extra arguments of its own.

To still let the user configure something like "top 20% vs top 33%," the
recipe template sets an environment variable immediately before invoking
osxphotos, and the bundled script reads it:

```
env OSXPHOTOS_TOP_PERCENT={percent} osxphotos export {destination} --place {city} --query-function {scriptsDir}/photo_scoring.py::top_percent --update
```

`{scriptsDir}` is a **built-in token**, not a `RecipeField` the user fills
in. `RecipeRunner.buildCommand` resolves it automatically to the path of the
bundled `Scripts/` folder inside the app. Any future recipe that needs a
bundled script should reference it the same way rather than hardcoding a
path, since the folder's location differs between a dev build and a
notarized app bundle.

Add `Scripts/` to Xcode the same way as `Registry/`: as a folder reference
(blue folder icon), not a group, so it copies into the app bundle as-is.

## Xcode setup

1. New macOS App project, SwiftUI interface, no sandboxing (**Signing & Capabilities
   → uncheck App Sandbox**, since Process execution outside the container requires it off).
2. Drag `Registry/` into the project as a **folder reference** (blue folder icon, not
   a group) so it's copied as-is into the app bundle and `Bundle.main.url(forResource:
   "Registry", withExtension: nil)` resolves correctly.
3. Add the three Swift files under `Sources/` to the target.
4. Codesign with a Developer ID Application certificate, then notarize via
   `xcrun notarytool` before distributing the DMG. Unsigned/unnotarized builds will
   get Gatekeeper-blocked on any machine but your own.

## Build order (recommended)

1. **Dependencies tab first.** Wire up `HomebrewManager` to a simple SwiftUI List
   showing: Homebrew installed? (yes/no + install button), then one row per tool
   in the registry showing installed version, latest version, and
   install/uninstall/upgrade buttons. This is the piece every recipe depends on,
   and it's fully testable on its own before any recipe UI exists.
2. **Tool detail view.** Tapping a tool card shows its list of recipes
   (`ToolDefinition.recipes`).
3. **Recipe form view.** Tapping a recipe generates a form from `Recipe.fields`
   (text field, folder picker via `NSOpenPanel`, etc.), shows a live command
   preview built via `RecipeRunner.buildCommand`, and a Run button that streams
   output via `RecipeRunner.execute`.
4. **Run log.** A simple scrollable text view showing timestamped command history
   and output, useful for debugging and for building user trust in what's running.

## Adding a new tool later

Drop a new JSON file into `Registry/` following the same shape as
`osxphotos.json`. No Swift changes needed unless the tool needs a field type
beyond `text` / `folder` / `file`.

## Known gaps to solve before v1.0

- `versionRegex` in each JSON file is defined but not yet wired into a parser —
  currently `HomebrewManager.installedVersion` parses `brew list --versions`
  output directly, which is more reliable than parsing each tool's own
  `--version` output. Keep `versionCommand`/`versionRegex` as a fallback for
  formulae where `brew list --versions` is ambiguous.
- No handling yet for tools not installable via Homebrew (e.g. anything requiring
  a pip venv). `installMethod` is scaffolded as a string for this reason —
  add a `pip` case to `HomebrewManager` (or a parallel `PipManager`) when needed.
- Folder/file field types need an `NSOpenPanel` wrapper in SwiftUI — not included
  here since it's boilerplate you likely already have from other projects.
