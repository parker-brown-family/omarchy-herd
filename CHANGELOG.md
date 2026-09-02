# Changelog

## 0.1.0

First release.

- A bar icon that goes urgent when a coding agent under [herdr](https://herdr.dev)
  is waiting on you, and a tray listing every agent it is running — grouped as
  NEEDS YOU, RUNNING, FINISHED and IDLE, with the empty groups left out.
- Click a row to focus that pane, and raise the terminal window with it when
  `TERMINAL_CLASS` is set. Right-click the bar icon to go straight to whatever
  is blocked. Arrow keys move through the rows, Enter jumps, Escape closes.
- One desktop notification when an agent enters `blocked`, and nothing else.
  Repeats for the same pane are suppressed for 20 seconds, because herdr's
  screen detection can flap between states and a notification per flap is noise.
- The two halves talk through a single JSON file and nothing else, so either
  runs with the other missing. Content is event-driven; only herdr's liveness
  is polled, and only because no event can report a server that has gone away.

Requires herdr 0.7.5 or newer — `[[startup]]` hooks arrived there, and without
one the bar stays empty until an agent happens to change state.
