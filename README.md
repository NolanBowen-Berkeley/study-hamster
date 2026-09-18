# Study Hamster 🐹

A tiny study buddy for your Mac. A hamster peeks over the top-right corner of whatever window you're
working in, keeps a pomodoro timer for you, and jumps out onto the window's edge when it's time for a
break (or when an alarm goes off).

- Follows the window you're using: switch apps and he ducks, then pops up on the new window.
- Click him, type how long you want to study ("2h", "45m", "1h 30m", "90"), and he plans the pomodoros.
- A countdown tag hangs off the window edge, and the menu bar shows the time left.
- No special permissions needed. He only reads where windows are, never what's in them.

## Build & run

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
make app      # builds "build/Study Hamster.app"
make run      # builds it and launches it
```

Or open the app yourself: `open "build/Study Hamster.app"`.

### Install

1. Drag `build/Study Hamster.app` into your **Applications** folder.
2. Optional: to have him show up every time you log in, open **System Settings → General → Login Items &
   Extensions** (just **Login Items** on macOS 14), click **+** under **Open at Login** and choose
   **Study Hamster**.

The app is signed ad-hoc (not notarized). If you built it yourself it opens normally. If you got it from
someone else and macOS blocks it, try to open it once, then go to **System Settings → Privacy & Security**
and click **Open Anyway**.

## How to use

1. **Click the hamster.** A speech bubble asks how long you want to study.
2. **Type a time** and press Return (or click a quick pick: 25 min, 50 min, 1 h, 2 h).
   Examples: `90`, `45m`, `1h`, `1h 30m`, `1:30`, `1.5 hours`, `an hour and a half`.
3. **Study.** He peeks over your window with a countdown tag.
4. **Break time:** he squeaks and jumps out onto the window's edge. Stretch, sip some water.
5. **Back to work:** he bounces and waves until you click **Let's go** (or after a few seconds).
6. **Done:** he celebrates. 🎉

Click him during a session to see the status bubble: time left, progress, and **Pause/Resume**,
**Skip**, **+5 min** and **Stop**. Click him again to close it.

The 🐹 menu-bar item has the same controls, plus **Hide Hamster** (timers keep running and he still pops
out for alarms), **Settings…** and **Quit**. Opening the app again (from Spotlight, Finder or Launchpad)
while it's running brings a hidden hamster back.

### The pomodoro defaults

| | |
|---|---|
| Focus | 25 min |
| Short break | 5 min |
| Long break | 15 min, after every 4 pomodoros |

The time you enter includes breaks. A 2-hour session becomes 25 min focus, 5 min break, 25, 5, 25, 5, 30.
He never ends on a break and never leaves you a tiny focus block at the end. You can change all of this
(plus the sound, whether his eyes follow your cursor, and the timer tag) in **Settings…**. New lengths
apply to your next session.

## Troubleshooting

- **I can't click the window under the hamster.** Only the hamster himself and his speech bubble catch
  clicks; everything else in that corner goes straight through to your window. If a bubble is in the
  way, click the hamster (or press Escape in the time box) to close it.
- **He's not over my full-screen app.** He should join full-screen apps on their own. If he doesn't,
  switch away and back to that Space, or choose **Hide Hamster** then **Show Hamster** from the menu bar.
- **He's sitting inside my window instead of on its edge.** He needs about 100 pt between the window's
  top and the menu bar to peek over the edge. When a window reaches higher than that (a maximized window,
  for example) he peeks from just inside its top instead, with his ears just under the menu bar. During
  breaks he sits out on the ledge and needs about 170 pt, so on those windows he hops a little lower.
- **He's at the top-right of the screen.** That's where he waits when no app has a normal window on
  screen (for example when everything is minimized or hidden).
- **I hid him and can't find the 🐹 in the menu bar.** On a Mac with a notch, menu-bar items can end up
  behind it. Open Study Hamster again from Spotlight or Finder and he comes back.
- **No sound.** Check **Settings… → Play sounds**, use **Preview**, and check your Mac's volume and
  Focus mode.
- **Timer seems off after sleep.** When the Mac wakes he catches up right away. If a phase ended while
  it was asleep, the next one starts fresh instead of burning through several at once.
- **Where are my settings stored?** In the standard macOS preferences for `com.nolanbowen.studyhamster`.

## For developers

```sh
make dev        # run from source without building the .app
make check      # self-checks for the timer/planning/window logic
make snapshots  # render the hamster's poses and bubbles to snapshots/
make clean
```

Layout: `HamsterCore` (pomodoro planning, engine, parsing, window geometry), `HamsterUI` (the SwiftUI
hamster, animator, bubbles and stage), `StudyHamster` (the AppKit app: floating panel, window tracking,
timers, sounds, settings).
