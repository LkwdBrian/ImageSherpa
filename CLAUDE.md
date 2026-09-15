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
picker (`FolderPicker.swift`) all exist. osxphotos, imagemagick, ffmpeg, and exiftool are all
registered tools.

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
    `imagemagick.json`, `ffmpeg.json`, and `exiftool.json` all exist). Defines the tool's
    install method, formula name, version-check command, and its list of recipes (each
    recipe: a command template with
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
| osxphotos | pipx | Export by album (album field is a live `dynamic_choice` picker, #15), by keyword, by date range, by person; find duplicates; list albums; Best Photos of a Place/Person/Year (score-based, via `Scripts/photo_scoring.py`) |
| imagemagick | brew | Batch resize, convert format, add watermark, strip metadata, contact sheet — resize/convert/watermark/strip each also have a single-file variant (#14) |
| ffmpeg | brew | Convert video format, extract frames from video, video to GIF, build video from image sequence (timelapse), compress video (all already single-file, see `inputFile`) |
| exiftool | brew | Remove GPS location only, rename by capture date, add copyright/author, geotag by decimal coordinates, export metadata to CSV — remove-GPS/rename/copyright/geotag each also have a single-file variant (#14) |

All four tools in the confirmed image/photo scope (see App Overview) are now registered.

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
python3 -m json.tool ImageSherpa/Registry/exiftool.json > /dev/null

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
  fully working. Registry files for all four tools (osxphotos, imagemagick, ffmpeg, exiftool)
  exist and their recipes are verified against real installed CLIs (see Framework Reality
  Checks). Remaining v1.0 gap is packaging (notarized DMG, Sparkle), not tool coverage.

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
- **osxphotos has no Homebrew formula — it's pipx-only** (fixed in #18). It's a Python CLI
  installed via `pipx install osxphotos`, not a compiled brew formula. `PipxManager.swift`
  (parallel to `HomebrewManager.swift`) and `PackageManagerRouter.swift` (dispatches by
  `tool.installMethod`) handle this; `osxphotos.json` declares `"installMethod": "pipx"`.
  This is the template for any other pip-only tool added later — new `installMethod` value +
  a parallel manager, not overloading `HomebrewManager`.
- **osxphotos needs Full Disk Access, not Photos-library permission, and this cannot be
  requested programmatically.** osxphotos reads `Photos.sqlite` directly rather than through
  PhotoKit, so every osxphotos command (recipe runs and the `dynamic_choice` album picker
  alike) is gated by the Full Disk Access TCC category, not `NSPhotoLibraryUsageDescription`
  (which the app also declares, for if/when #17's thumbnail preview uses PhotoKit directly —
  but that key does nothing for osxphotos's raw file access). Unlike
  Photos/Camera/Microphone/Contacts, macOS has no `requestAuthorization`-style API for Full
  Disk Access and never shows an automatic prompt — Apple deliberately requires a human to
  add the app via System Settings → Privacy & Security → Full Disk Access → **+**, with a
  password/Touch ID prompt. (Correction to an earlier version of this note: Apple's own WWDC
  2019 guidance confirms macOS *does* auto-prepopulate an app in that list, unchecked, the
  first time it's genuinely denied — this is why random unrelated apps show up there. Full
  Disk Access just has no query API and no prompt dialog, so a user has to know to look.)
  `PermissionHelp.swift` detects the "Operation not permitted" EPERM signature and offers a
  button that opens the Full Disk Access pane directly
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`); `FullDiskAccessCheck.swift`
  proactively probes `~/Library/Safari/CloudTabs.db` (checking raw `errno == EPERM`, since
  higher-level FileManager APIs don't reliably trigger the same TCC check) so `ContentView`/
  `DependenciesView` can gate access and show this before a cryptic failure, not just react
  to one. That's the ceiling of what's automatable here — there is no way to trigger the
  actual grant, or make the app self-register in the list, programmatically.
- **`RecipeRunner` must not rely on a login shell (`-l`) alone to reproduce a user's PATH —
  it silently misses anything added via `.zshrc`.** A `-l` shell sources `~/.zprofile`, not
  `~/.zshrc`; only an *interactive* shell (`-i`) sources `.zshrc`. `pipx`'s PATH setup
  (adding `~/.local/bin`, where pipx-installed tools' shims live) commonly lands in
  `.zshrc`. The practical effect: a recipe or `optionsCommand` that resolves fine when you
  test it by hand in Terminal can fail with a plain "command not found" when run from the
  actual app — which looks nothing like a PATH problem and is easy to misdiagnose as a
  permissions issue instead (this cost an entire debugging session on 2026-09-13 chasing
  Full Disk Access before the real cause — silent "command not found" with zero TCC log
  activity — was found via `log stream --predicate 'subsystem == "com.apple.TCC"'` showing
  *no* access check at all for the failing attempt). Fixed by `RecipeRunner.withGuaranteedPath`,
  which explicitly prepends `~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin` to
  `PATH` before every command, rather than trusting shell dotfile-sourcing behavior. Any new
  recipe or `optionsCommand` that depends on a tool installed via pipx/pip is covered by
  this automatically — no per-recipe workaround needed.
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
- **exiftool.json recipes are verified against a real installed CLI** (exiftool 13.55,
  2026-09-11). All 5 templates run clean and produce correct output.
- **exiftool's `-d` date-format tokens for filename rename must use double-percent for
  exiftool-specific tokens** (`%%e` for the file extension, `%%-c` for a collision counter),
  not single-percent. A single `%e`/`%-c` gets intercepted by the underlying strftime parser
  instead (producing garbage like a locale datetime string or day-of-month), not passed
  through to exiftool's own escapes. The `batch_rename_by_date` recipe's `%%-c` counter also
  isn't cosmetic: without it, two photos sharing the same capture timestamp to the second
  (burst shots, batch imports) collide on the same target filename and the whole run exits 1
  partway through, having renamed some files but not others.
- **Single-file mode (#14) is implemented as a duplicate sibling recipe, not a folder/file
  toggle on one recipe.** Resolves the open question in #14's Notes: a toggle would need
  `RecipeRunner`/`RecipeFormView` to conditionally swap template text at render time, which
  works against "always show the user the real command before running it" (the preview would
  need its own toggle-aware logic instead of just interpolating `recipe.template` directly)
  and against keeping tool-specific behavior out of Swift. A plain sibling recipe (e.g.
  `resize_single_file` next to `batch_resize`) is pure registry data and needs zero code
  changes. Two sub-cases ended up looking different: ImageMagick's batch recipes use a shell
  `for f in {sourceFolder}/*; do ... done` loop, so the single-file template is genuinely
  different (a direct `magick {sourceFile} ... {destinationFile}` call, no loop). ExifTool's
  recipes never glob — `exiftool ... {sourceFolder}` already accepts a bare file path with
  identical behavior — so its single-file variants are the *same* template with only the
  `sourceFolder` (type `folder`) field swapped for `sourceFile` (type `file`), which matters
  only because `RecipeField.type` drives whether `FolderPicker` lets the user pick a file
  vs. a directory. Follow whichever pattern matches a new tool's recipe: check whether its
  template loops over a glob before assuming a field-type swap is sufficient.
- **exiftool's `-GPSLatitudeRef`/`-GPSLongitudeRef` can take the same signed decimal value as
  `-GPSLatitude`/`-GPSLongitude`** rather than needing separate N/S/E/W tag values — exiftool
  derives the hemisphere from the sign. This is what lets the `geotag` recipe use only 2
  fields (latitude, longitude) instead of 4.

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
- ~~**Next tool to register after osxphotos/imagemagick**~~ — **Decided 2026-09-11: both.**
  ffmpeg and exiftool are now both registered (see Supported Tools & Recipes). No fifth tool
  is currently being considered.
