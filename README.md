# GarminRace2

A GPS lap timer for motorsport and track days, built as a Connect IQ watch app for the **Garmin Venu 2**.

![Main screen states](docs/screens.png)

## Features

- **Accurate line detection.** Each timing line is a point plus a 25 m capture radius. The app checks the straight path between consecutive GPS fixes and interpolates the exact crossing time, so laps are timed to the hundredth and fast cars can't skip the line between 1 Hz fixes.
- **Direction aware.** If you set a line while moving, the app records which way the track runs there and ignores passes in the opposite direction.
- **Two modes.** *Circuit* times laps across one start/finish line. *Sprint* times A-to-B runs between separate start and finish lines and re-arms after each run.
- **Live feedback.** A bezel ring fills as your lap approaches your best. A coloured pill shows the gap: green when you set a new best, red when you're slower. You also get vibration and tone alerts on each lap.
- **Heart rate** from the wrist or a paired strap, coloured by your Garmin HR zones, with max HR per session.
- **Saved to Garmin Connect.** Each session is recorded as a FIT activity (GPS track, heart rate, laps).
- **Lap history page** (swipe up) with the gap to best for every lap.
- Lines and mode are remembered between launches.

![Lap history](docs/lap-history.png)

## Controls

| Input | Action |
|---|---|
| **START** (top button) | Start session / stop and save (asks to confirm) |
| **Hold BACK** (menu) | Set lines, switch Circuit/Sprint, lap history, clear lines |
| **Swipe up** | Lap history |
| **BACK** while recording | Asks to save and exit |

Screen taps are ignored on the main screen, so a bumped wrist can't stop a session.

## Using it

1. At the track, open the menu and choose **Set Start/Finish** while standing on (or driving across) the line. In Sprint mode, set both the start and the finish.
2. Press **START**. The app arms and waits for you to cross the line.
3. Lap timing begins at the first crossing. Every crossing after that records a lap.
4. Press **START** again to stop and save to Garmin Connect.

## Building

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and a developer key.

```bat
build.bat
```

Or directly:

```bat
monkeyc -d venu2 -f monkey.jungle -o bin\GarminRace2.prg -y path\to\developer_key -w
```

`build.bat` looks for the key in `%DEV_KEY%`, then `developer_key` next to the script, then `..\..\GarminRace\developer_key`. Keys are gitignored. Never commit yours.

## Installing on the watch

The Venu 2 connects as a media (MTP) device. In File Explorer, copy `bin\GarminRace2.prg` into **Venu 2 › Internal Storage › GARMIN › APPS**, then unplug the watch.

## Project layout

```
source/
  GarminRace2App.mc         app entry, GPS + heart-rate sensors
  RaceSessionModel.mc       track setup, timing, FIT recording, persistence
  TimingGate.mc             line-crossing detection and interpolation
  GarminRace2View.mc        main race screen
  LapHistoryView.mc         lap history page
  GarminRace2Delegate.mc    buttons, confirmations
  GarminRace2MenuDelegate.mc menu
  RaceAlerts.mc             vibration, tones, toasts
  TimeFormat.mc             time formatting
resources/                  strings, launcher icon
```
