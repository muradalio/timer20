# Timer20 Project Context

This file is for future development work. It summarizes the current project state so a new coding session can continue without chat history.

## Product

Timer20 is a macOS-only menu bar app for eye rest reminders.

Default cycle:

- 20 minutes of work.
- 20 seconds of rest.
- Repeat forever.

The app has no regular Dock window. It runs as an accessory/menu bar utility next to the macOS clock.

## Tech Stack

- Swift 6.
- Swift Package Manager executable package.
- AppKit, not SwiftUI.
- Minimum macOS target: 13.0.
- Menu bar integration via `NSStatusItem`.
- Notifications via `UserNotifications`.
- Launch at login via `ServiceManagement.SMAppService.mainApp`.
- Settings persistence via `UserDefaults`.

There are no third-party dependencies.

## Key Files

- `Package.swift` - SwiftPM package definition.
- `Sources/Timer20/main.swift` - all app logic and UI currently lives here.
- `Resources/Info.plist` - app bundle metadata, `LSUIElement`, bundle id, icon file.
- `Resources/AppIcon.icns` - generated application icon.
- `Scripts/generate-icon.swift` - deterministic icon generator.
- `Scripts/build-app.sh` - builds `build/Timer20.app`, copies plist/icon, ad-hoc signs locally.
- `Scripts/install-app.sh` - installs the built app into `/Applications`.
- `Makefile` - convenience build/run/install targets.
- `README.md` - English user documentation.
- `README_RU.md` - Russian user documentation.
- `PROJECT_CONTEXT.md` - this file.

## Main Architecture

Everything currently lives in `Sources/Timer20/main.swift`.

Important types:

- `NotificationLevel`
  Alert level enum:
  - `.menuBarOnly`
  - `.notifications`
  - `.strictRestOverlay`

- `AppSettings`
  Loads and saves:
  - `workSeconds`
  - `restSeconds`
  - `notificationLevel`

  It still migrates old `workMinutes` settings by reading the legacy key and converting minutes to seconds.

- `L`
  Lightweight in-code localization helper.
  Uses English if `Locale.preferredLanguages.first` starts with `en`; otherwise Russian.

- `TimerPhase`
  Current timer state:
  - `.working`
  - `.resting`
  - `.paused(previous:remaining:)`

- `RunningPhase`
  Non-paused phase:
  - `.working`
  - `.resting`

- `SettingsWindowController`
  AppKit settings window.
  Lets the user configure:
  - work duration;
  - rest duration;
  - alert level;
  - launch at login.

- `TransitionBannerController`
  Small non-blocking floating banner used by the normal notification mode.

- `StrictRestOverlayController`
  Full-screen blur overlay used only during rest in strict mode.
  Shows:
  - rest title;
  - rest countdown;
  - skip button with rocket icon.

- `Timer20App`
  Main app delegate and timer controller.
  Owns:
  - `NSStatusItem`;
  - timer loop;
  - current phase;
  - settings window;
  - floating banner;
  - strict overlay;
  - notification delivery.

## Runtime Behavior

On launch:

1. App becomes `.accessory`.
2. Requests notification permission.
3. Creates menu bar item.
4. Starts working phase using saved/default work duration.

Timer flow:

1. Work phase counts down.
2. At zero, starts rest phase.
3. Rest phase counts down.
4. At zero, starts work phase again.
5. Repeat.

Menu bar display:

- Uses a dynamic state icon:
  - work: `laptopcomputer`
  - rest: `eye.fill`
  - pause: `pause.fill`
- Uses compact text:
  - `19m` when 10+ minutes remain;
  - `9:59`, `3:00`, `0:30` below 10 minutes.
- Full `MM:SS` remains visible in the dropdown menu.

The status item has a fixed width of 58 pt to reduce the chance macOS hides it when screen recording or other system indicators appear.

## Alert Levels

Alert levels are selected in Settings.

### Menu Bar Only

Only pulses the menu bar item when the phase changes.

### Notifications

On phase change:

- sends a system notification;
- shows a small floating banner;
- pulses the menu bar item.

### Strict Rest Overlay

When rest starts:

- no system notification;
- no small floating banner;
- shows a full-screen blur overlay;
- center card shows countdown until rest ends;
- button `Не хочу отдыхать, фигачим дальше!` / English localized text skips rest and starts the next work phase.

When strict rest ends naturally, the app returns to work without showing the normal floating banner.

## Settings Details

Defaults:

- `workSeconds = 20 * 60`
- `restSeconds = 20`
- `notificationLevel = .notifications`

Work duration input accepts:

- whole minutes: `20`, `3`;
- decimal minutes: `0.5`;
- comma/colon short syntax for seconds: `0,3` or `0:30` means 30 seconds.

Rest duration is currently entered as whole seconds.

Bounds:

- work duration: 1 second to 240 minutes;
- rest duration: 1 to 600 seconds.

Saving settings starts a new work cycle with the updated duration.

## Build Commands

Build SwiftPM executable:

```sh
make build
```

Build `.app` bundle:

```sh
make app
```

Run local bundle:

```sh
make run
```

Install into `/Applications`:

```sh
make install
```

Run installed app:

```sh
make run-installed
```

Clean:

```sh
make clean
```

Generate app icon:

```sh
swift Scripts/generate-icon.swift
```

## Bundle And Signing

`Scripts/build-app.sh` creates:

```text
build/Timer20.app
```

It copies:

- executable to `Contents/MacOS/Timer20`;
- `Resources/Info.plist` to `Contents/Info.plist`;
- `Resources/AppIcon.icns` to `Contents/Resources/AppIcon.icns`.

It then ad-hoc signs the app:

```sh
codesign --force --sign - build/Timer20.app
```

This is for local development only.

For public distribution, use Developer ID signing, hardened runtime, notarization, stapling, and Gatekeeper verification. This release pipeline has not been implemented yet.

## Distribution Folder

`dist/` is ignored by git and contains generated distribution artifacts.

Current manual dist archive:

```text
dist/Timer20.zip
```

Expected contents:

```text
Timer20/
├── Timer20.app
├── README.md
└── README_RU.md
```

`dist/Timer20.zip` is not committed.

## Git Notes

The repository is initialized locally and has a linear commit history.

Do not commit:

- `.build/`
- `build/`
- `dist/`
- `.DS_Store`
- `.vscode/`
- `Resources/AppIcon.iconset/`

These are ignored in `.gitignore`.

## Known Practical Notes

- The app is currently a single Swift source file. If it grows further, split it into files by responsibility:
  - `SettingsWindowController.swift`
  - `TimerController.swift`
  - `TransitionBannerController.swift`
  - `StrictRestOverlayController.swift`
  - `Localization.swift`
  - `AppSettings.swift`

- The app icon is deterministic and generated from Swift drawing code, not AI-generated.

- `NSStatusItem` compact mode was added because macOS screen recording adds system menu bar indicators and can hide wider third-party items.

- `README.md` is English. `README_RU.md` is Russian.

## Likely Next Steps

- Add a real release script for Developer ID signing and notarization.
- Add `make dist` to rebuild `dist/Timer20.zip` automatically.
- Consider universal binary support for both Apple Silicon and Intel Macs.
- Split `main.swift` into smaller source files.
- Add a settings option for ultra-compact menu bar mode: icon only, time in dropdown.
- Add tests for settings parsing, especially `0,3`, `0:30`, and decimal inputs.
