# BatteryBar

An iPhone-style battery for the macOS menu bar, with live power use and time left.

The icon fills with the charge, with the percentage cut out of the battery. It turns green on the charger, red at 20%
or less on battery, and yellow in Low Power Mode. The time left sits under it; **Show Time Left in Menu Bar** hides it.

Click it for:

- The charge and the time left in words, with the clock time the battery runs out or finishes charging.
- **Using now**: the whole Mac's power draw in watts, with a chart of the last minute.
- Where the power goes: charger to Mac, battery to Mac, or charger to battery.
- **Apps using the most power**: the three apps drawing the most processor power, their helper processes included.
- **Battery Settings…**, and a shortcut to them when Low Power Mode is on.

## Install

Needs macOS 14 or later and the Command Line Tools (`xcode-select --install`). Xcode isn't needed.

```bash
./build.sh
ditto build/BatteryBar.app /Applications/BatteryBar.app
open /Applications/BatteryBar.app
```

On its first launch the app adds itself to Login Items. If you turn it off in System Settings → General → Login Items,
it stays off. The app is signed ad hoc, so run it from Applications to keep the login item pointing at the same copy.

It places itself next to Control Center. Cmd-drag it somewhere else and it keeps that spot.

## Uninstall

Remove it from Login Items, choose **Quit BatteryBar** from the menu and delete the app.

## How it works

- The charge and charging state come from IOKit's power source API, which reports every change, so nothing polls.
- Live power comes from the System Management Controller: `PSTR` for the whole Mac, `PPBR` for the battery and `PDTR`
  for the charger. The app reads them every 2 seconds, and every second while the menu is open, so the chart already
  holds the last minute when you open it. Apple doesn't document these keys; if a macOS update removes them, the menu
  hides the live figures.
- On battery, the time left is BatteryBar's own estimate: the energy left in the battery divided by the power used,
  averaged over about two minutes. It's ready about 10 seconds after you unplug, where macOS takes several minutes.
  Until then, and while charging, the app shows macOS's estimate.
- App power comes from the kernel's per-process energy counters. Only your own processes can be read without admin
  rights, so system daemons are left out, and only processor power counts, not the screen or graphics. Helper processes
  are grouped under the app macOS holds responsible for them, through a private system function the app looks up at
  run time. If a macOS update removes it, each process is grouped by the app bundle it runs from instead.
