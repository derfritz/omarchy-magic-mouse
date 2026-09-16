# omarchy-magic-mouse

Make an Apple Magic Mouse feel like it does on a Mac, on [Omarchy](https://omarchy.org)
(Hyprland / Wayland). Pointer acceleration that slows down for small targets,
scrolling that only happens when you mean it, natural direction, and momentum.

## Why the stock experience is bad

The kernel `hid_magicmouse` driver exposes the mouse as a plain pointer plus
an "emulated scroll wheel" derived from the touch surface. Three things follow:

- **The page scrolls while you aim.** Any finger drift on the glass becomes
  wheel events. There is no start threshold, so as you slow down to click, the
  page moves under you.
- **The cursor jumps past small targets.** Bluetooth delivers some reports in
  bursts. libinput turns a burst into a huge instantaneous velocity, and every
  acceleration profile then multiplies that frame.
- **Scroll direction and momentum are wrong or missing.**

## What this does

A small daemon grabs the real mouse and re-emits a virtual one called
`magic-mouse-omarchy`:

- **Pointer:** Apple's own acceleration curve, taken from the open-source
  IOHIDFamily driver, driven by the same "tracking speed" number as the macOS
  slider. Velocity is smoothed so Bluetooth bursts can't spike it. Click
  tolerance freezes the cursor for a moment after a press so the click itself
  can't nudge it.
- **Scroll:** synthesized from the touch surface, ignoring the kernel wheel.
  A finger must travel about a millimetre, and be clearly moving, before a
  scroll starts. Fingers that only hold the mouse don't count: a touch that
  lands on the side edge is a grip, and among several fingers the one that
  slides scrolls (two sliding together scroll too). While the mouse itself
  moves, a scroll only starts if the finger slides several times farther than
  the mouse travels, so a resting finger drifting as you aim never scrolls,
  and a scroll stops once you start mousing. No scroll starts right around a
  click. One axis at a time, natural direction, and the scroll rate ramps with
  finger speed.
- **Momentum:** flick and lift, the page glides and eases out.
- **Clicks:** the kernel driver's centre "middle-click" zone (which pastes on
  Linux) is a left click, like on a Mac. Configurable. Control-click as a
  right click is a switch in the settings popup (`buttons.control_click`):
  the daemon never reads the keyboard, so it adds a Hyprland binding for
  Control + click on its virtual mouse only and answers it with a right click.
  While it is on, apps no longer see Control + click from the Magic Mouse.
- **Gestures:** one-finger sideways flick = back / forward (browser buttons).
  Two-finger sideways swipe = previous / next workspace. One- and two-finger
  double taps are hooks you can point at any Hyprland dispatcher or command.

- **Battery and settings in the bar:** a small Omarchy shell widget shows the
  mouse's charge and highlights when low. Click it for a settings popup with
  tracking speed, natural scrolling, scroll speed, momentum and gesture
  switches; every control applies live. Right-click opens the Bluetooth panel.
  The daemon asks the mouse for its charge directly (the mouse only volunteers
  it to the kernel on its own schedule, so UPower alone shows 0% for a long
  time after connecting).
- **Clicks decided by the mouse:** the kernel driver's three fixed touch zones
  (left / middle / right) are turned off, so the mouse's own firmware decides
  left vs right, exactly as on macOS.

Hyprland only needs a flat profile for the virtual device; the installer adds it.

## macOS feature checklist

| macOS | Here |
|---|---|
| Pointer acceleration | Apple's curve, same numbers |
| Natural scrolling | yes |
| Scroll starts only when you mean it | start threshold, resting and gripping fingers ignored, finger-vs-mouse motion |
| Momentum scrolling | yes (`momentum.decay` 0.984 matches Apple's rate) |
| Secondary click on the right side | done by the mouse itself |
| Secondary click off | `buttons.right_click = false` (switch in the popup) |
| Control-click = secondary click | `buttons.control_click = true` (switch in the popup) |
| No middle click | `buttons.middle = "left"` |
| Swipe between pages (one finger) | back / forward buttons |
| Swipe between full-screen apps (two fingers) | workspace switch (`hl.dsp.focus({ workspace = "e+1" })`) |
| Mission Control (two-finger double tap) | hook, off by default |
| Smart zoom (one-finger double tap) | hook, off by default |
| Battery level | bar widget (`io.github.maikunari.magic-mouse`) |
| Force click, Handoff | not applicable |

## Install

This repo is an Omarchy plugin (the bar widget and settings popup) that ships
its own helper daemon. Two steps:

```sh
# 1. the plugin: clones into ~/.config/omarchy/plugins/ and enables the bar widget
omarchy plugin add https://github.com/maikunari/omarchy-magic-mouse --enable

# 2. the daemon, udev rule, driver option and Hyprland snippet (asks for your password once)
~/.config/omarchy/plugins/io.github.maikunari.magic-mouse/install.sh
```

Later updates: `omarchy plugin update io.github.maikunari.magic-mouse`, then
re-run `install.sh` to refresh the daemon.

Prefer a plain checkout? `git clone` anywhere and run `./install.sh`; it copies
the widget into the plugins directory for you.

Pair the mouse with Bluetooth as usual. The daemon waits for it and grabs it
whenever it connects.

Check it is running:

```sh
systemctl --user status magic-mouse
journalctl --user -u magic-mouse -f
hyprctl devices | grep magic-mouse-omarchy
```

## Tune it

Click the mouse icon in the bar for the common settings. Everything else is in
`~/.config/magic-mouse/config.toml`; changes apply live, no restart. From a
shell, `magic-mouse-config set pointer.tracking_speed=1.0` edits the file
without disturbing your comments, and `magic-mouse-config get` prints the
effective config as JSON.

| Feels like… | Change |
|---|---|
| pointer too slow / too fast | `pointer.tracking_speed`, same scale as the macOS slider (0 to 3, Apple default 0.6875) |
| the curve is right but everything is a touch off | `pointer.speed` 0.9 / 1.1 |
| scroll starts when I only meant to click | raise `scroll.start_mm` (1.2) or `scroll.settle_ms` (250) |
| have to move the finger too far before it scrolls | lower `scroll.start_mm` (0.5) |
| scrolling backwards | flip `scroll.natural` |
| forward/back inverted only on my model | flip `scroll.invert_y` |
| glide too long / too short | `momentum.decay` 0.95 / 0.985 |
| no glide | `momentum.enabled = false` |

## Remove

```sh
~/.config/omarchy/plugins/io.github.maikunari.magic-mouse/uninstall.sh   # daemon, unit, udev rule, driver option
omarchy plugin remove io.github.maikunari.magic-mouse                     # the widget
```

`uninstall.sh` leaves `~/.config/magic-mouse/config.toml` and the small
`magic-mouse-omarchy` device block in your Hyprland input config; delete those
by hand if you want a clean slate.

## What the installer touches

Everything is listed so you can decide before running it:

| Path | What |
|---|---|
| `~/.local/bin/magic-mouse-daemon`, `magic-mouse-config`, `magic-mouse-battery-query` | the daemon and its two helpers |
| `~/.config/systemd/user/magic-mouse.service` | user service, enabled and started |
| `~/.config/magic-mouse/config.toml` | your settings (only created if missing) |
| `~/.config/hypr/input.lua` (or `input.conf`) | a 7-line device block, **appended only after asking**, with a backup |
| `/etc/udev/rules.d/70-magic-mouse.rules` | via the root helper: a `uaccess` rule for the mouse's input and raw HID nodes and for `/dev/uinput`, matched by device ID |
| `/etc/modprobe.d/hid_magicmouse.conf` | via the root helper: `emulate_3button=0` |
| `/etc/modules-load.d/magic-mouse.conf` | via the root helper: loads `uinput` at boot so the rule above can apply |

No file from the checkout runs as root. The only privileged step is a short
Python helper embedded in `install.sh` and handed to the distro's `python3` on
the command line, so it is already in memory when `sudo` runs and nothing on
disk can be swapped in afterwards. It carries the exact bytes of all three `/etc`
files, walks to each directory one component at a time without following
symlinks, requires root-owned directories that only root can write to, writes
to an exclusive temporary file there, verifies it through the same descriptor,
renames it into place atomically and verifies again; it refuses if anything
in the way is a symlink or not a regular file. It then reloads udev and
prints the files' SHA-256 digests, which `install.sh` re-checks as your user.
Access to the mouse comes from that device-specific `uaccess` rule alone: the
installer never changes your group membership, and stops if your user still
cannot open the device nodes afterwards.

No sudoers changes, no NOPASSWD, nothing downloaded at install time. The
daemon runs as your user, talks only to the local mouse and the Hyprland
socket, and writes its status under `$XDG_RUNTIME_DIR/magic-mouse/`.

## Dependencies

- `python-evdev` (Arch package; the installer adds it with `omarchy pkg add`)
- the in-kernel `hid_magicmouse` driver (ships with Arch) and `upower` (ships with Omarchy)
- Omarchy shell for the bar widget; the daemon works on any Hyprland

## Notes

- Works with Magic Mouse 1 (`05ac:030d`), Magic Mouse 2 (`004c:0269`) and Magic Mouse USB‑C (`004c:0323`),
  matched by ID, so it does not matter what you named the mouse on macOS.
- Requires `python-evdev` (installed by `install.sh`) and the in-kernel
  `hid_magicmouse` driver, which Arch ships.
- The installer writes `/etc/modprobe.d/hid_magicmouse.conf` with
  `emulate_3button=0`. The old `scroll_acceleration` / `scroll_speed` options
  only affect the kernel's emulated wheel, which this daemon ignores.
- `config.toml` and the battery status file are only ever read and written
  descriptor-first: no symlink following, no blocking on a planted FIFO,
  owner/type/size checks before reading, and writes go to a random
  same-directory `O_EXCL` temp file (mode 0600) that is fsynced and renamed
  into place.
- Bar widget settings (on its entry in `~/.config/omarchy/shell.json`):
  `"match": "MMM"` to pin it to one device by model name, `"lowAt": 20` for the
  low-battery highlight threshold.

---

Magic Mouse, Mac and macOS are trademarks of Apple Inc. This project is
independent and is not affiliated with or endorsed by Apple.
