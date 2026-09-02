#!/bin/sh
# Jump to the agent that is waiting on you.
#
# Invoked as the `focus-blocked` action — from the bar chip, from a keybinding,
# or by hand:
#
#   herdr plugin action invoke brownfamilysports.herd.focus-blocked
#
# With no argument it picks the first blocked agent. Pass a pane id to target
# one directly.
set -eu

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/herd/herd.json"
# herdr sets HERDR_PLUGIN_CONFIG_DIR when it runs this as an action. The bar
# panel calls the script directly with a pane argument, and gets no such
# environment, so fall back to where herdr keeps that directory.
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-$HOME/.config/herdr/plugins/config/brownfamilysports.herd}"
CONFIG="$CONFIG_DIR/config.env"

# TERMINAL_CLASS is the Hyprland class of the terminal that has herdr attached.
# Set it in config.env to have the window raised as well as the pane focused —
# focusing a pane inside a server nobody is looking at is only half the jump.
# `herdr plugin config-dir brownfamilysports.herd` prints where that file goes.
TERMINAL_CLASS=""
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

target="${1:-}"

if [ -z "$target" ]; then
  target=$(jq -r '
    [.agents[]? | select(.status == "blocked") | .pane] | first // ""
  ' "$STATE" 2>/dev/null || printf '')
fi

# Nothing blocked. Fall back to whatever is done and unseen before giving up —
# clicking the chip should always land somewhere it said something.
if [ -z "$target" ]; then
  target=$(jq -r '
    [.agents[]? | select(.status == "done") | .pane] | first // ""
  ' "$STATE" 2>/dev/null || printf '')
fi

[ -n "$target" ] || exit 0

# `agent focus` takes a live agent name or the pane id hosting it. `pane focus`
# is directional and moves between neighbours — not this.
"$HERDR" agent focus "$target" >/dev/null 2>&1 || exit 0

[ -n "$TERMINAL_CLASS" ] || exit 0
command -v hyprctl >/dev/null 2>&1 || exit 0

# Hyprland 0.56 replaced string dispatchers with a Lua API. The form every guide
# still documents — `hyprctl dispatch focuswindow class:X` — does not fail
# loudly there; it returns 7 with a Lua parse error, so a script that ignores
# the exit code raises nothing and reports success. Try the new form first and
# fall back, rather than picking one and being wrong for half the installs.
hyprctl dispatch "hl.dsp.focus({window=\"class:$TERMINAL_CLASS\"})" >/dev/null 2>&1 \
  || hyprctl dispatch focuswindow "class:$TERMINAL_CLASS" >/dev/null 2>&1 \
  || true
