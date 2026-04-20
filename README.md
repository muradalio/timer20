# Timer20

Timer20 is a small Mac menu bar timer that helps your eyes rest.

The idea is simple: when you look at a screen for a long time, your eyes get tired. Timer20 reminds you to take short breaks: by default, 20 minutes of work, then 20 seconds of rest, then the cycle starts again.

The app lives in the macOS menu bar next to the clock. It does not have a regular main window.

Russian version: [README_RU.md](README_RU.md)

## How It Works

- The menu bar shows the remaining time.
- When work time ends, the app reminds you to rest.
- During rest, a short countdown runs.
- After rest, the next work cycle starts automatically.
- You can change work and rest durations in settings.

Timer20 has several alert levels:

- blink in the menu bar only;
- show regular notifications;
- show a full-screen blur overlay during rest.

If the full-screen rest mode is enabled, the screen shows this button:

```text
Не хочу отдыхать, фигачим дальше!
```

It skips the rest and starts a new work cycle.

## How To Launch

1. Unzip `Timer20.zip`.
2. Drag `Timer20.app` into the `Applications` folder.
3. Open `Applications`.
4. Right-click `Timer20.app`.
5. Choose `Open`.
6. Confirm the launch.

A normal double-click may not work the first time because the app is not yet Developer ID signed and notarized for public distribution. Right-click -> `Open` usually lets macOS allow the app.

## After Launch

Timer20 appears in the menu bar next to the clock.

Click it to open the menu:

- `Pause` - pause the timer;
- `Start rest now` - start rest immediately;
- `Reset ...` - restart the work cycle;
- `Settings...` - change durations, launch at login, and alert level;
- `Quit` - close the app.

On first launch, macOS may ask for notification permission. Allow it if you want to see reminders.

## Launch At Login

To start Timer20 automatically when you log into macOS:

1. Click Timer20 in the menu bar.
2. Open `Settings...`.
3. Enable `Launch at login`.
4. Click `Save`.

## If The App Does Not Open

Try this:

1. Open `System Settings`.
2. Go to `Privacy & Security`.
3. Find the message about blocked `Timer20`.
4. Click `Open Anyway`.

If that option is not shown, delete the app from `Applications`, unzip the archive again, and repeat right-click -> `Open`.
