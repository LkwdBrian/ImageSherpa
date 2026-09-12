# ImageSherpa — Claude Project Instructions

This is the single source of truth for both Claude Desktop (planning sessions) and Claude Code
(autonomous coding sessions) — no separate docs/CLAUDE.md.

## App Overview
ImageSherpa is a native macOS application that gives GUI access to command-line **image and
photo** tools (osxphotos, ImageMagick, and other candidates like ffmpeg/exiftool) without
requiring the user to memorize flags or use Terminal directly. Each supported tool is defined
by a JSON registry file describing its install method and a curated set of "recipes" (canned
tasks rendered as forms), so adding a new tool is a data change, not a code change.

**Scope (settled 2026-09-10):** image/photo command-line tools specifically, not a
general-purpose CLI wrapper for anything. The name itself encodes this decision — don't
propose adding unrelated tool categories (e.g. network utilities, dev tooling) without
reopening this explicitly with Brian.

**Tagline:** Command-line photo tools, no command line required
**Display name:** ImageSherpa (Image Sherpa with a space is acceptable for display/marketing
copy; bundle identifier and repo name use the no-space form)
**Platform:** macOS, Swift / SwiftUI
**Owner:** Brian Cosgrove — So Wired Productions
**Repo:** [LkwdBrian/ImageSherpa](https://github.com/LkwdBrian/ImageSherpa) (public)
**Status:** Xcode project scaffolded (Xcode 16 file-system-synchronized groups, no manual
pbxproj file lists — see App Components). `ToolDefinition.swift`, `RecipeRunner.swift`,
`HomebrewManager.swift`, a working Dependencies tab (`DependenciesView.swift`), tool detail
(`ToolDetailView.swift`), recipe form + run log (`RecipeFormView.swift`), and a folder/file
picker (`FolderPicker.swift`) all exist. osxphotos and imagemagick are both registered tools.

---

## App Components

- **ImageSherpa.app** — single windowed SwiftUI app. No separate helper process or daemon;
  unlike Conduit, there's no persistent server to coordinate with, so this is a simpler
  single-target architecture. The app shells out directly to `Process` for Homebrew
  operations and recipe execution.
- **All source lives flat under `ImageSherpa/`**, not in separate `Registry/Scripts/Sources`
  top-level folders. The Xcode project uses Xcode 16's file-system-synchronized groups (no
  manual `project.pbxproj` file lists — drop a new `.swift`/`.json`/`.py` file into
  `ImageSherpa/` and it's picked up automatically). This has one real consequence: **nested
  subfolders are flattened when copied into the app bundle's `Contents/Resources`.**
  `ImageSherpa/Registry/` and `ImageSherpa/Scripts/` exist for developer organization only —
  at runtime every `.json`/`.py` file lands directly in `Bundle.main.resourceURL`, not under
  a "Registry" or "Scripts" subdirectory. `ToolRegistryLoader` and `RecipeRunner` read from
  `Bundle.main.resourceURL` directly for this reason; don't reintroduce a
  `Bundle.main.url(forResource: "Registry", ...)`-style lookup, it will silently return zero
  tools.
  - `ImageSherpa/Registry/*.json` — one file per supported CLI tool (`osxphotos.json`,
    `imagemagick.json`, and `ffmpeg.json` exist). Defines the tool's install method, formula
    name, version-check command, and its list of recipes (each recipe: a command template with
    `{field}` placeholders, plus the form fields needed to fill it in).
  - `ImageSherpa/Scripts/*.py` — bundled Python helper scripts for logic a CLI flag can't
    express (currently: `photo_scoring.py`, used by osxphotos recipes that filter by Apple's
    on-device aesthetic score). Invoked via tools' own script hooks (e.g. osxphotos's
    `--query-function`), with user-configurable parameters passed through environment
    variables rather than script arguments.
  - `ToolDefinition.swift` (registry models + loader), `HomebrewManager.swift`
    (install/uninstall/version-check for brew formulae), `RecipeRunner.swift` (builds and
    executes the final shell command from a recipe + field values), `DependenciesView.swift`
    (Dependencies tab UI), `ToolDetailView.swift` (per-tool detail screen), `RecipeFormView.swift`
    (dynamic recipe form generation, command preview, and run log), `FolderPicker.swift`
    (`NSOpenPanel` wrapper for `folder`/`file` recipe fields).

---

## Architecture — Non-Negotiables
Decisions are locked. Do not suggest alternatives unless Brian explicitly reopens them.

- **Scope: image/photo CLI tools only.** See App Overview. This is a product decision, not
  a technical limitation — the underlying Registry/Recipe engine is generic enough to support
  any CLI tool, but ImageSherpa's identity is specifically photo/image workflows. Don't blur
  this by registering an unrelated tool (e.g. a network diagnostic CLI) just because the
  architecture would technically allow it.
- **Language:** Swift only. No Python/Node runtimes bundled for app logic — Python is used
  only as data (the bundled query-function scripts other tools call into), never executed
  directly by the app itself.
- **UI:** SwiftUI only. No AppKit unless an unavoidable framework API requires it (e.g. an
  `NSOpenPanel` wrapper for folder/file picking).
- **App Sandbox: OFF.** This is the single most important technical constraint in the
  project. The app needs to run `brew install`/`brew uninstall` for arbitrary formulae and
  shell out to binaries outside its own container (`/opt/homebrew/bin`, `/usr/local/bin`).
  Both are blocked by App Sandbox. Don't suggest re-enabling it "for security" without
  flagging that it breaks the core feature set first.
- **Distribution:** Direct download only, notarized DMG. **Not the Mac App Store** —
  sandboxing requirements there are incompatible with install/uninstall functionality.
  Sparkle for auto-updates once there's a v1.0 to update from.
- **Data-driven tool support:** New CLI tool = new `Registry/*.json` file. Don't hardcode
  tool-specific logic in Swift; if a tool needs something the current schema can't express,
  extend the schema (and this file), don't special-case it in code.
- **Command execution:** Always show the user the real command before running it. This is a
  deliberate product decision (trust-building + incidental CLI education), not a step to
  streamline away.
- **Field-type quoting is not optional:** `RecipeField.type` must be `quoted_text` for any
  value that may contain spaces (names, keywords, city names), not `text`. Getting this wrong
  silently breaks the built command on any multi-word value. See `RecipeRunner.swift` for the
  quoting logic.

---

## Supported Tools & Recipes

| Tool | Install | Recipes |
|---|---|---|
| osxphotos | brew | Export by album, by keyword, by date range, by person; find duplicates; list albums; Best Photos of a Place/Person/Year (score-based, via `Scripts/photo_scoring.py`) |
| imagemagick | brew | Batch resize, convert format, add watermark, strip metadata, contact sheet |
| ffmpeg | brew | Convert video format, extract frames from video, video to GIF, build video from image sequence (timelapse), compress video |

**Roadmap candidates (image/photo domain only, per the scope decision above):** exiftool
(deeper metadata read/write than osxphotos/ImageMagick expose natively). Not yet scoped into
a Registry file.

Recipes should default to the 80% use case. Resist adding a field for every possible flag a
CLI tool supports, that defeats the point of the app. New tool additions go through this
table, keep it current.

---

## Build & Test Commands
```bash
# Validate registry JSON files are well-formed (do this after any Registry/ edit)
python3 -m json.tool ImageSherpa/Registry/osxphotos.json > /dev/null
python3 -m json.tool ImageSherpa/Registry/imagemagick.json > /dev/null
python3 -m json.tool ImageSherpa/Registry/ffmpeg.json > /dev/null

# Validate a bundled Python script's syntax
python3 -m py_compile ImageSherpa/Scripts/photo_scoring.py

# Full app
xcodebuild -scheme "ImageSherpa" -destination 'platform=macOS' build
xcodebuild -scheme "ImageSherpa" -destination 'platform=macOS' test
```

---

## Tooling & Workflow

**Two-environment approach** (same split as Conduit):
- **Claude Desktop** — session planning, GitHub Issues, architecture decisions, registry
  design, documentation, code review
- **Claude Code** — hands-on coding, multi-file edits, debugging, writing tests, git
  commits/pushes (Claude Code may commit and push directly from the terminal — see Git
  Conventions)

**Recommended session flow:**
1. Start in Claude Desktop — pull current repo state via GitHub MCP, review open Issues,
   plan the session goal
2. Switch to Claude Code (terminal or Xcode) — do the coding work, commit and push
3. Return to Claude Desktop — close Issues, update docs, plan next session

**Before writing any code (Claude Code specifically):** check open GitHub Issues (`gh issue
list` or the GitHub MCP connector) and confirm which issue you're working against. If none
exists for the task, create one first per the format below.

---

## GitHub Issues — Project Task Tracker

GitHub Issues is the single task tracker. No mental todo lists.

**Session start ritual:** Always check open Issues before writing any code or making
recommendations. Use the GitHub MCP connector to fetch current issues.

**When to create an issue:** Any new task, bug, decision, or open question gets an issue.
Reference issues in all commit messages (`closes #12`, `relates to #7`).

**Issue format:**
```
Title: [Area] Brief description
  e.g. "HomebrewManager: implement upgrade-all flow"
  e.g. "Registry: add ffmpeg tool definition"

Body:
## What
One sentence on what this covers.

## Why
What it unblocks or why it matters.

## Acceptance Criteria
- [ ] Specific, testable item
- [ ] ...

## Notes
Relevant context, API references, gotchas.
```

**Labels:**
- `tool:osxphotos`, `tool:imagemagick`, `tool:<new-tool>` — per registered CLI tool
- `arch` — architecture or schema-level decisions
- `docs` — documentation
- `bug` — something broken
- `v1` — must ship in v1

**Milestones:**
- **v0.1 — Foundation:** Homebrew manager working end to end (install/uninstall/version
  check), Xcode project scaffolded, App Sandbox confirmed off, signing configured — **done**,
  merged to `main`.
- **v0.2 — Recipe UI:** Tool detail view, recipe form generation, command preview, run log —
  **done**, merged to `main` via `feature/recipe-form-ui`.
- **v1.0 — Public Release:** Notarized DMG, Sparkle-enabled, at least osxphotos + imagemagick
  fully working. Registry files for both tools exist and their recipes are verified against
  real installed CLIs (see Framework Reality Checks).

---

## Git Conventions

**Branching model:** trunk-based with short-lived feature branches

| Branch | Purpose |
|---|---|
| `main` | Always shippable. Tagged at releases. |
| `feature/short-description` | New feature work |
| `fix/short-description` | Bug fixes |
| `chore/short-description` | Refactors, cleanup, docs |

**Commit message prefixes:** `feat:` · `fix:` · `refactor:` · `chore:` · `wip:` (never on main)

**Reference the relevant issue in every commit** (`closes #12`, `relates to #7`).

**Tagging:** Format `v{major}.{minor}.{patch}`. Tag every notarized build worth handing to a
tester.

### Claude Code Sessions

- Work directly in the current checkout, on the already-checked-out or newly-created feature
  branch. Do not create a git worktree unless Brian explicitly asks for parallel workstreams.
- Do not open a GitHub pull request. Push the branch and merge into `main` directly once the
  work is verified — no PR review step needed for a solo, no-CI repo at this stage.
- Stop after making changes and running available checks (JSON validation, `xcodebuild ...
  test` once tests exist), and report results. Do not merge into `main` without Brian's
  go-ahead — Brian tests the branch himself (running the app) first.
- Once Brian confirms the branch is good, either he merges/pushes via a GUI, or Claude Code
  does it at the terminal on his explicit go-ahead, whichever is more convenient in the
  moment.
- Revisit "no worktree / no PR" once CI is added (require a PR then) or genuinely parallel
  workstreams are needed (worktrees permitted, one per active task).

---

## Framework Reality Checks (don't rebuild these gaps)

- **`--query-function` (osxphotos) accepts no arguments of its own.** Any user-configurable
  parameter for a bundled script (e.g. "top 20%" vs "top 33%") must be passed via environment
  variable set immediately before the command runs, not as a script argument. See
  `Scripts/photo_scoring.py` and the `{scriptsDir}` token in `RecipeRunner.swift`.
- **`versionRegex` in the registry schema is not yet wired into a parser.**
  `HomebrewManager.installedVersion` currently parses `brew list --versions` output directly
  instead, which is more reliable for most formulae. Keep the regex field as a documented
  fallback path, don't remove it.
- **No support yet for non-Homebrew install methods** (pip-only tools, for instance).
  `installMethod` is a string for exactly this reason — add a parallel manager (e.g.
  `PipManager`) rather than overloading `HomebrewManager` when this is needed.
- **osxphotos CLI flags referenced in recipes** (`--place`, `--person`, `--year`,
  `--query-function`) were sourced from documentation and may drift across osxphotos
  versions. Verify against `osxphotos help export` on the actual installed version before
  trusting a recipe template is correct.
- **imagemagick.json recipes are verified against a real installed CLI** (ImageMagick 7.1.2
  aarch64, 2026-09-11). All 5 templates run clean and produce correct output.
- **`magick montage` (contact_sheet recipe) needs an explicit `-font` path.** A stock
  `brew install imagemagick` has no fontconfig registration (`magick -list font` returns
  empty), so montage's default per-thumbnail filename label throws `unable to read font` and
  exits 1 — even though it still writes a usable contact sheet. `-label ''`/`+label` do NOT
  avoid this; montage still tries to measure text metrics for an empty label. The fix is
  pinning `-font /System/Library/Fonts/Helvetica.ttc` (ships on every Mac), which sidesteps
  the font lookup entirely. If you add another recipe that uses `montage`, `-annotate`,
  `-draw`, or anything else that renders text, apply the same explicit `-font` fix.
- **ffmpeg.json recipes are verified against a real installed CLI** (ffmpeg 9.0.1 aarch64,
  2026-09-11). All 5 templates run clean and produce correct output.
- **Every ffmpeg recipe template must include `-y`.** RecipeRunner's `Process` runs
  non-interactively with no stdin. Without `-y`, ffmpeg pauses to ask "overwrite? [y/N]" on
  any re-run where the output file already exists, and the run silently hangs forever (no
  error, no exit code) since nothing can answer the prompt. Any new ffmpeg recipe needs `-y`
  for this reason — it's not optional the way it might look in a docs example.

---

## Working Agreements

- Always start a session by reviewing open GitHub Issues via the GitHub MCP connector
  (Desktop) or `gh issue list` (Code)
- Remind Brian to review and merge feature branches at natural stopping points
- Suggest starting a new chat when the conversation is getting long or switching focus areas
- Brian is experienced with Swift/SwiftUI — skip beginner explanations
- Prefer structured, ready-to-use outputs; skip obvious commentary
- Show the real command before running it, every recipe, no exceptions (see Non-Negotiables)
- Stay within the image/photo scope (see Non-Negotiables) — flag it if a request would add an
  unrelated tool category rather than silently registering it
- Update this file when architecture decisions change — this is not optional

---

## Key Open Questions

Do not make decisions on these without Brian.

- **Pricing/distribution model** — free (lead-gen for So Wired Productions) vs. small paid
  utility (Gumroad or direct sale, since App Store install/uninstall functionality is
  incompatible with sandboxing regardless).
- **Next tool to register after osxphotos/imagemagick** — ffmpeg vs. exiftool as the third
  Registry entry. Both fit the confirmed image/photo scope; neither is scoped into a Registry
  file yet.
