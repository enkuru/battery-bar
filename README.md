# BatteryBar

An iPhone-style battery for the macOS menu bar, with live power use and time left.

The icon fills with the charge, with the percentage cut out of the battery. It turns green on the charger, red at 20%
or less on battery, and yellow in Low Power Mode. The time left sits under it; **Show Time Left in Menu Bar** hides it.

Click it for:

- The charge and the time left in words, with the clock time the battery runs out or finishes charging. On battery,
  how long since you unplugged and how much charge that used.
- **Using now**: the whole Mac's power draw in watts, with a chart of the last minute. On the charger, its name and the
  most power it delivers to this Mac.
- Where the power goes: charger to Mac, battery to Mac, or charger to battery.
- **Apps using the most power**: the three apps drawing the most processor power, their helper processes included.
  Point at one to quit it.
- **Battery health**: maximum capacity, charge cycles and condition, as System Settings shows them.
- **Battery Settings…**, and a shortcut to them when Low Power Mode is on.

## Install

Needs macOS 14 or later and the Command Line Tools (`xcode-select --install`). Xcode isn't needed.

```bash
./install.sh
```

It builds the app, quits the running copy, replaces `/Applications/BatteryBar.app` and opens it. To build without
installing, run `./build.sh`; the app lands in `build/BatteryBar.app`.

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
  hides the live figures. While charging, `PPBR` stays near 1 W, so the power going into the battery comes from the
  battery's own gauge (voltage × current), which updates once a minute.
- The time left is BatteryBar's own estimate, ready the moment the power source changes, where macOS takes minutes.
  On battery it divides the energy left by the power used, averaged over about two minutes and started from what the
  Mac drew in the half minute before you unplugged. While charging it adds up the energy still to go at the charging
  power learned for each percentage, aiming at where charging has been stopping, such as 80% with Optimized Battery
  Charging. What it learns is kept across launches. Until it has a figure, the app shows macOS's estimate.
- The battery's energy, health and cycle figures come from its controller's IORegistry entry, whose keys Apple doesn't
  document either; without them the menu hides Battery health and falls back to macOS's estimate.
- App power comes from the kernel's per-process energy counters. Only your own processes can be read without admin
  rights, so system daemons are left out, and only processor power counts, not the screen or graphics. Helper processes
  are grouped under the app macOS holds responsible for them, through a private system function the app looks up at
  run time. If a macOS update removes it, each process is grouped by the app bundle it runs from instead.
