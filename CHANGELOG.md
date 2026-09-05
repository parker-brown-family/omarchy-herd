# Changelog

## 0.2.0 — 2026-09-05

- Renamed from Herd to **Crook**, which is what it always was: the shepherd's
  hook, the tool for singling one animal out of the flock. The name Herd has
  moved to the state bus this family of plugins reads from, where the flock
  itself lives. Nothing about the behaviour changed, but every name did — the
  plugin id is now `brownfamilysports.crook`, the herdr half sits under
  `crook/` as `crook-sync.sh` and `crook-focus.sh`, the state file is
  `~/.local/state/omarchy/crook/crook.json`, and the repository is
  `omarchy-crook`. An installed copy of the old name is not upgraded in place:
  remove `brownfamilysports.herd` from both halves, install this one, and
  delete `~/.local/state/omarchy/herd`.
- The bar icon is a shepherd's crook, drawn as a path rather than borrowed from
  a font. A sheep glyph stood in while the plugin was called Herd, because Nerd
  Fonts ships no crook under any name — but the flock belongs to the bus now,
  and the tool that singles one out of it is what this plugin is. It takes the
  bar's colour, goes urgent with the button, and stays legible down to 18px.

- The tray no longer stays empty after herdr comes back up without republishing.
  Losing the socket clears the agent list, and the cache that makes the
  three-second re-read free was not cleared with it, so a byte-identical
  snapshot afterwards was skipped as unchanged.
- Clicking through to an agent now raises the terminal window hosting it, so
  Hyprland switches to the workspace herdr is on. Previously the jump focused
  the pane inside herdr and stopped there unless `TERMINAL_CLASS` was set in
  `config.env` — which nothing prompts you to do — so on a default install the
  click moved herdr's focus somewhere you could not see and appeared to do
  nothing at all. The window is found by walking up from the herdr client to
  the first ancestor Hyprland owns, which needs no configuration and does not
  care which terminal you use. `TERMINAL_CLASS` still works and still wins,
  for clients the walk cannot reach.
- The bar icon no longer stays hidden when the plugin is installed into a
  running Omarchy shell. The panel loads before the herdr half has created
  `~/.local/state/omarchy/crook`, and a `FileView` created while its parent
  directory is missing never sees the file appear — so `agents` stayed empty,
  and with the default `hideWhenEmpty` the widget drew nothing and logged
  nothing until the shell was restarted. The file is now re-read on the
  three-second tick that already probes herdr's socket, and an unchanged
  snapshot is dropped without touching any bindings.
- Fixed a `TypeError` on every `refresh` IPC call: the handler called
  `root.broadcast(...)`, which the Omarchy shell's `Panel` base class does not
  define, so the call threw instead of refreshing.

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
