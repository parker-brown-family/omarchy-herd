#!/bin/sh
# Jump to the agent that is waiting on you.
#
# Invoked as the `focus-blocked` action — from the bar icon, from a keybinding,
# or by hand:
#
#   herdr plugin action invoke brownfamilysports.herd.focus-blocked
#
# With no argument it picks the first blocked agent, then the first finished
# one. Pass a pane id to target one directly; the tray does that when you click
# a row.
set -eu

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/herd/herd.json"

# herdr sets HERDR_PLUGIN_CONFIG_DIR when it runs this as an action. The bar
# panel calls the script directly with a pane argument, and gets no such
# environment, so fall back to where herdr keeps that directory.
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-$HOME/.config/herdr/plugins/config/brownfamilysports.herd}"
CONFIG="$CONFIG_DIR/config.env"

# Read one key out of config.env rather than sourcing the file. It lives in a
# directory herdr creates and the user edits, and sourcing would execute
# whatever ends up in it — a needless way to turn a one-line setting into
# arbitrary code that runs on every click.
read_config() {
  [ -f "$CONFIG" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CONFIG" 2>/dev/null \
    | tail -n 1 | tr -d '"'"'"'\r' || true
}

# Pane ids are herdr's opaque handles and look like w1:p1. A window class is a
# Wayland app id. Anything outside that shape did not come from herdr or from
# the config file, and nothing outside that shape reaches a command line.
valid_token() {
  case "${1:-}" in
    "") return 1 ;;
    *[!A-Za-z0-9:._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

first_pane_with_status() {
  [ -f "$STATE" ] || return 0
  jq -r --arg s "$1" '[.agents[]? | select(.status == $s) | .pane] | first // ""' \
    "$STATE" 2>/dev/null || true
}

target="${1:-}"

if [ -z "$target" ]; then
  target=$(first_pane_with_status "blocked")
fi

# Nothing blocked. Fall back to whatever finished and has not been looked at,
# so the icon always lands somewhere it said something about.
if [ -z "$target" ]; then
  target=$(first_pane_with_status "done")
fi

valid_token "$target" || exit 0

# `agent focus` takes a live agent name or the pane id hosting it. `pane focus`
# is directional and only moves between neighbours — not this.
"$HERDR" agent focus "$target" >/dev/null 2>&1 || exit 0

TERMINAL_CLASS=$(read_config TERMINAL_CLASS)
valid_token "${TERMINAL_CLASS:-}" || exit 0
command -v hyprctl >/dev/null 2>&1 || exit 0

# Hyprland 0.56 replaced string dispatchers with a Lua API. The form every guide
# still documents — `hyprctl dispatch focuswindow class:X` — does not fail
# loudly there; it returns 7 with a Lua parse error, so a script that ignores
# the exit code raises nothing and reports success. Try the new form first and
# fall back, rather than picking one and being wrong for half the installs.
hyprctl dispatch "hl.dsp.focus({window=\"class:$TERMINAL_CLASS\"})" >/dev/null 2>&1 \
  || hyprctl dispatch focuswindow "class:$TERMINAL_CLASS" >/dev/null 2>&1 \
  || true
