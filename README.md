# Herd

**Which coding agent needs you, on the Omarchy bar.**

[herdr](https://herdr.dev) already knows which of your agents is blocked. Your
desktop does not. Herd puts one chip on the Omarchy bar that says who is stuck,
and one click that takes you there.

```
⏸ 1  ▶ 3
```

One agent waiting on you, three still working. The chip goes urgent-coloured the
moment anything blocks, and disappears entirely when herdr is not running.

## What it is not

Omarchy already ships `omarchy.agents`, which is about **spend** — rate limits,
token meters, pace. Herd is about **attention**. They sit next to each other and
answer different questions.

## How it works

Two halves, one file, no daemon.

```
herdr server
    │  [[events]] pane.agent_status_changed
    ▼
herd-sync.sh  ──writes──▶  ~/.local/state/omarchy/herd/herd.json
                                      │  FileView
                                      ▼
                            BarWidget.qml  (pure display)
```

The herdr half subscribes to herdr's own events and writes a small JSON file.
The Omarchy half draws whatever appears in that file — the same shape
`omarchy.agents` uses to display the records `omarchy-agent-usage-update`
writes. Neither half imports the other, and either one runs fine with the other
missing.

Content updates are event-driven, so the chip changes the instant an agent
does. One thing is polled: whether herdr is alive at all. herdr removes its
socket when the server stops, so a three-second `test -S` on that path is a
truthful liveness check — and no event can report it, because the server that
would have sent one is the thing that went away.

## Install

Both halves, from this one repository.

```bash
omarchy plugin add https://github.com/parker-brown-family/omarchy-herd.git --enable
```
```bash
herdr plugin install parker-brown-family/omarchy-herd/herdr
```
```bash
omarchy bar move brownfamilysports.herd --section right
```

Restart or reattach herdr once so the plugin's startup hook runs and publishes
the first snapshot.

## Settings

In the Omarchy bar widget settings:

| Setting | Default | What it does |
| --- | --- | --- |
| Hide when no agents are running | on | Leave the bar entirely rather than showing an empty chip |
| Count idle agents | off | Idle agents need nothing, so they stay quiet by default |
| herdr socket path | *(session default)* | Point at a named session. `herdr session list` prints the path |

To have the terminal **window** raised when you click through to a pane — not
just the pane focused inside a server nobody is looking at — set your terminal's
Hyprland class:

```bash
herdr plugin config-dir brownfamilysports.herd
```

Put `TERMINAL_CLASS=<your terminal's class>` in `config.env` in that directory.
`hyprctl clients` will tell you the class.

## States

Badges match Terminal Delight's agent wall, so the two read alike.

| Badge | herdr state | Meaning |
| --- | --- | --- |
| ⏸ | `blocked` | Waiting on you — a permission prompt or a question |
| ▶ | `working` | A turn is running |
| ✓ | `done` | Finished, and you have not looked yet |
| · | `idle` | At rest. Hidden unless you turn idle counting on |

herdr has no error state; it folds rate limits and API failures into `unknown`.
Herd does not invent one — unknown agents rest with idle.

## Notifications

One notification when an agent enters `blocked`, and nothing else. herdr emits
that event on transition, so it fires once per block rather than once per
spinner frame. `done` stays silent on purpose: the chip already shows it, and a
notification for every finished turn is noise.

## Requirements

Linux, Hyprland, `omarchy-shell`, herdr 0.7.0 or newer, and `jq`.

## License

MIT.
