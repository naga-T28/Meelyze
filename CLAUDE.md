# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

The Xcode project (`Meelyze.xcodeproj`) is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding, removing, or moving files under `Meelyze/`, `MeelyzeTests/`, or `MeelyzeUITests/`, regenerate the project before building:

```sh
xcodegen generate --spec project.yml
```

Build and test (Simulator name must match an installed runtime — list with `xcrun simctl list devices available`):

```sh
# Build
xcodebuild -project Meelyze.xcodeproj -scheme Meelyze \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run all tests (Unit + UI)
xcodebuild -project Meelyze.xcodeproj -scheme Meelyze \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run a single Unit Test (Swift Testing)
xcodebuild -project Meelyze.xcodeproj -scheme Meelyze \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MeelyzeTests/ContentViewModelTests/titleIsMeelyze test

# Run a single UI Test (XCTest)
xcodebuild -project Meelyze.xcodeproj -scheme Meelyze \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MeelyzeUITests/MeelyzeUITests/testAppTitleIsDisplayed test
```

Other useful checks:

```sh
xcodebuild -list -project Meelyze.xcodeproj          # confirm schemes/targets resolve
plutil -lint Meelyze.xcodeproj/project.pbxproj        # validate project file syntax
open Meelyze.xcodeproj                                # open in Xcode GUI
```

For building/installing to a physical iPhone (Team selection, and the required git-hygiene step afterward), follow `docs/device-verification.md` — do not hand-edit signing settings without reading it first.

## Architecture

**Layering (MVVM + Repository/Service)**: `Meelyze/` is split into `Views/`, `ViewModels/`, `Services/`, `Repositories/`, `Models/`. Views hold only a `@State` ViewModel (`@Observable` class) and render its published state — they never import Vision/Foundation Models/SwiftData or other Apple frameworks directly. `Services/` and `Repositories/` are currently placeholders (a `README.md` each, no code) because no feature work has landed yet; when adding OCR/LLM/persistence, define a `protocol` in the ViewModel's dependency and put concrete implementations (e.g. `VisionOCRService`, `FoundationModelsMenuParser`) behind it, per `docs/technology-selection.md` §4. Don't add empty protocols or scaffolding speculatively ahead of actual feature work — TASK-003's completion criteria explicitly reject that.

**Core product invariant**: the LLM (Apple Foundation Models primary, llama.cpp fallback) is used *only* for natural-language menu understanding/structuring. Final allergen/dietary-restriction determination must always go through a deterministic DB + Swift Rule Engine — an LLM "not present" inference is never sufficient grounds for a safe/negative result on its own, and anything unresolved must degrade to "判定不可" (undeterminable) rather than a guess. This asymmetric, safety-biased design is the central constraint for all future judgment/analysis logic; see `docs/technology-selection.md` §1, §9–10.

**Requirements vs. tech selection**: `docs/requirements.md` is the original product requirements doc (user stories, FR/NFR, KPIs) and is still authoritative for *product* scope. Its technology constraints (Flutter, SQLite, ML Kit) are superseded by `docs/technology-selection.md` (Accepted, Issue #3), which is authoritative for all MVP implementation technology (Swift/SwiftUI, Apple Vision, SwiftData, Foundation Models). When the two conflict on tech choices, follow `technology-selection.md`.

**Signing**: `project.yml` sets `CODE_SIGN_STYLE: Automatic` and `DEVELOPMENT_TEAM: ""` at the project level intentionally — no developer's personal Team ID is committed. Selecting a Team in Xcode's Signing & Capabilities (needed for on-device builds) writes `DEVELOPMENT_TEAM` into `project.pbxproj`; that change must be discarded (`git checkout -- Meelyze.xcodeproj/project.pbxproj`) before committing anything else. Full procedure in `docs/device-verification.md`.

**Testing split**: Unit tests (`MeelyzeTests/`) use Swift Testing (`import Testing`, `@Test`, `#expect`), mirroring the source tree (e.g. `ViewModels/ContentViewModelTests.swift`). UI tests (`MeelyzeUITests/`) use XCTest/XCUITest.

**Local-only planning docs**: `task/` (per-task implementation logs, `TASK-NNN-*.md`) and `fix/` (follow-up audit/fix notes) are gitignored — they exist in the working tree for coordination between the two developers but are never committed. Don't assume their content reflects the committed history; check `git log`/`docs/` for what's actually shipped.

**Dev workflow** (`docs/development-guide.md`): every change starts from an Issue; branches are `feature|fix|chore/<issue-number>-<slug>`; commits are `<prefix>: #<issue-number> <description>`; PRs must reference the issue and get the other developer's review before merging to `main`. Do not commit directly to `main`.
