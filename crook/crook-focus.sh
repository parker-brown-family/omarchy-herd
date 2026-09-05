#!/bin/sh
# Jump to the agent that is waiting on you.
#
# Invoked as the `focus-blocked` action — from the bar icon, from a keybinding,
# or by hand:
#
#   herdr plugin action invoke brownfamilysports.crook.focus-blocked
#
# With no argument it picks the first blocked agent, then the first finished
# one. Pass a pane id to target one directly; the tray does that when you click
# a row.
set -eu

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/crook/crook.json"

# herdr sets HERDR_PLUGIN_CONFIG_DIR when it runs this as an action. The bar
# panel calls the script directly with a pane argument, and gets no such
# environment, so fall back to where herdr keeps that directory.
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-$HOME/.config/herdr/plugins/config/brownfamilysports.crook}"
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

# ------------------------------------------------------------------- raising
#
# `herdr agent focus` moves herdr's own focus, inside the terminal running it.
# When that terminal is on another Hyprland workspace nothing visible happens:
# the notification said an agent needs you, the click appears to do nothing,
# and the agent is still a workspace away. Raising the window brings its
# workspace forward with it, which is the point of the jump.
#
# This used to require TERMINAL_CLASS in config.env, and did nothing at all
# without it — so the default install did half the job silently. The window is
# now found instead of configured.

# Hyprland 0.56 replaced string dispatchers with a Lua API. The form every guide
# still documents — `hyprctl dispatch focuswindow class:X` — does not fail
# loudly there; it returns 7 with a Lua parse error, so a script that ignores
# the exit code raises nothing and reports success. Try the new form first and
# fall back, rather than picking one and being wrong for half the installs.
raise() {
  hyprctl dispatch "hl.dsp.focus({window=\"$1\"})" >/dev/null 2>&1 \
    || hyprctl dispatch focuswindow "$1" >/dev/null 2>&1 \
    || true
}

# Addresses come out of hyprctl rather than off a config line, but they still
# reach a command line, so they are checked like everything else here.
valid_address() {
  case "${1:-}" in
    0x*) ;;
    *) return 1 ;;
  esac
  case "${1#0x}" in
    "" | *[!0-9a-fA-F]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Field 4 of /proc/<pid>/stat is the parent pid. The comm field ahead of it is
# parenthesised and can itself contain spaces and brackets, so the tail is read
# after the last ')' rather than counted in columns.
ppid_of() {
  [ -r "/proc/$1/stat" ] || return 1
  sed 's/^.*)//' "/proc/$1/stat" 2>/dev/null | awk '{ print $2 }'
}

# A herdr client is a descendant of the terminal emulator hosting it, so the
# window for a session is its first ancestor that Hyprland owns. herdr's own
# server matches the same process name and costs nothing to try: it is
# parented to the service manager, so the walk reaches the top without a match
# and the server drops out by itself.
window_of() {
  _pid=$1
  _hops=0
  while [ "$_hops" -lt 32 ]; do
    case "$_pid" in
      "" | *[!0-9]*) return 1 ;;
    esac
    [ "$_pid" -gt 1 ] || return 1
    _addr=$(printf '%s\n' "$WINDOWS" | awk -v p="$_pid" '$1 == p { print $2; exit }')
    if [ -n "$_addr" ]; then
      printf '%s\n' "$_addr"
      return 0
    fi
    _pid=$(ppid_of "$_pid") || return 1
    _hops=$(( _hops + 1 ))
  done
  return 1
}

command -v hyprctl >/dev/null 2>&1 || exit 0

# An explicit class still wins, for what the search cannot reach: a client
# attached over ssh, a terminal Hyprland does not own, or a session someone
# wants pinned to one window. A class that is set but malformed stops here
# rather than falling through to a guess.
TERMINAL_CLASS=$(read_config TERMINAL_CLASS)
if [ -n "${TERMINAL_CLASS:-}" ]; then
  valid_token "$TERMINAL_CLASS" || exit 0
  raise "class:$TERMINAL_CLASS"
  exit 0
fi

command -v pgrep >/dev/null 2>&1 || exit 0

WINDOWS=$(hyprctl clients -j 2>/dev/null \
  | jq -r '.[]? | select(.pid != null and .address != null) | "\(.pid) \(.address)"' \
  2>/dev/null) || WINDOWS=''
[ -n "$WINDOWS" ] || exit 0

# Match on the binary's own name, so a client running from a renamed or
# preview build is still found.
HERDR_NAME=${HERDR##*/}
valid_token "$HERDR_NAME" || exit 0

for candidate in $(pgrep -x "$HERDR_NAME" 2>/dev/null || true); do
  addr=$(window_of "$candidate") || continue
  valid_address "$addr" || continue
  raise "address:$addr"
  exit 0
done
