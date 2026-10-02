# Cadent

Cadent is a macOS menu-bar app that reminds you to stand up and stretch. At the interval you choose, it covers the frontmost app — including a fullscreen space — and plays a reminder in your own voice.

There is no Dock icon. Cadent lives in the menu bar.

## Features

- Record short reminders with the microphone and play them back yourself before you save them.
- Attach more than one voice to a reminder. Cadent rotates through the voices attached to that reminder, then moves on to the next enabled reminder.
- Set the break interval in hours and minutes, up to 24 hours. Snooze and how long the card stays on screen are saved with the same **Save** button.
- Pause and resume from the menu bar, or start a break immediately with **Stretch Now**.
- Snooze or dismiss the card. Press Escape or **Done** to dismiss it. Clicking the dimmed background leaves the card up.
- Open at login.
- After the Mac wakes, show one overdue break instead of stacking every break missed while asleep.

A break is skipped when no enabled reminder has a voice whose audio file is still on disk.

## Requirements

- macOS 14 or later
- Xcode with Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), used to generate the Xcode project

Cadent asks for microphone access the first time you record. It does not request Accessibility or Screen Recording permission.

## Build and run

Generate the project, then build and open the app:

```bash
xcodegen generate
xcodebuild \
  -project Cadent.xcodeproj \
  -scheme Cadent \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
open build/DerivedData/Build/Products/Debug/Cadent.app
```

`scripts/build-app.sh` compiles the same sources with `swiftc` and ad-hoc signs the app at `build/Cadent.app`. Use that when you want a binary without opening the Xcode project. The generated `Cadent.xcodeproj` is gitignored.

Launch at login uses `SMAppService` and only registers once Cadent is installed, typically in `/Applications`. A debug build run from a DerivedData folder reports that it has to be installed first.

## Using Cadent

Open **Settings** from the menu bar.

1. Under **New Cadent**, name a clip and record it. Recordings are capped at 30 seconds. Preview the take, then save or discard it.
2. Under **Reminders**, add a reminder and choose **Voices** to attach one or more saved clips. A reminder with no attached voice does not play.
3. Under **Schedule**, type how often you want a break, how long snooze lasts, and how long the card stays up. Press **Save** to apply those times. Until you save, Cadent keeps the previous schedule.

The menu bar shows the next break time. **Pause** stops the timer. **Resume** continues from a future deadline, or starts a new interval if the old one has already passed.

Deleting a reminder does not delete its voice files. Deleting a voice removes that clip from every reminder it was attached to.

## Privacy

Recordings and settings stay on this Mac.

- Audio files are AAC (`.m4a`) in `~/Library/Application Support/Cadent/recordings/`.
- Schedule, reminder, and voice metadata are stored in UserDefaults under `com.dukaloco.cadent`. The audio itself is not stored there.
- The microphone is used only while you are recording.

## Project layout

| Path | Role |
| --- | --- |
| `Cadent/CadentApp.swift` | Menu-bar app entry |
| `Cadent/AppModel.swift` | Wiring for settings, playback, schedule, and the overlay |
| `Cadent/Settings/` | Persisted schedule, voices, reminders, and the settings window |
| `Cadent/Audio/` | Recording, playback, and files on disk |
| `Cadent/Scheduler/` | Next-break timer, pause, snooze, and wake |
| `Cadent/Overlay/` | Break card shown above the frontmost app |
| `project.yml` | XcodeGen spec for the macOS 14 target |
