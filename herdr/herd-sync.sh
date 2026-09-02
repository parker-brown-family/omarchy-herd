#!/bin/sh
# Publish herdr's agent state where the Omarchy bar can read it.
#
# Runs from herdr's [[events]] hooks, so it is a short-lived process fired on
# change — never a daemon, never a poll. It writes one file:
#
#   ${XDG_STATE_HOME:-~/.local/state}/omarchy/herd/herd.json
#
# and, when an agent has just become blocked, one notification.
set -eu

HERDR="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/herd"
OUT="$STATE_DIR/herd.json"
LOCK="$STATE_DIR/.lock"
DIRTY="$STATE_DIR/.dirty"

mkdir -p "$STATE_DIR"

# --------------------------------------------------------------- publication

# The whole list, every time, never an incremental patch. An incrementally
# maintained map drifts the moment one event is missed or a server restarts,
# and reconciling it is more code than re-reading. `agent list` is one call
# over a local socket.
publish() {
  if raw=$("$HERDR" agent list 2>/dev/null); then
    :
  else
    # No server, or it went away mid-call. Publish an empty herd rather than
    # leaving the bar showing agents that no longer exist.
    raw=''
  fi

  now=$(date +%s)

  if [ -z "$raw" ]; then
    printf '{"stamp":%s,"agents":[]}\n' "$now" >"$OUT.tmp"
  else
    printf '%s' "$raw" | jq -c --argjson stamp "$now" '
      {
        stamp: $stamp,
        agents: [
          (.result.agents // [])[] | {
            pane:      .pane_id,
            workspace: .workspace_id,
            status:    .agent_status,
            agent:     (.display_agent // .agent // "agent"),
            title:     (.title // .terminal_title_stripped // ""),
            focused:   (.focused // false)
          }
        ]
      }' >"$OUT.tmp" 2>/dev/null || printf '{"stamp":%s,"agents":[]}\n' "$now" >"$OUT.tmp"
  fi

  # Rename within the same directory, so a reader watching the file never
  # observes a half-written one.
  mv -f "$OUT.tmp" "$OUT"
}

# -------------------------------------------------------------- notification

# Only on entering `blocked`. It is the one state that requires a human;
# herdr emits the event on transition, so this fires once per block, not once
# per spinner frame. `done` deliberately stays silent — the bar already shows it.
notify_blocked() {
  [ -n "${HERDR_PLUGIN_EVENT_JSON:-}" ] || return 0

  # Read the payload by recursive descent rather than a fixed path: the hook
  # envelope is herdr's to change, and the field names are the stable part.
  field() {
    printf '%s' "$HERDR_PLUGIN_EVENT_JSON" \
      | jq -r --arg k "$1" '[.. | objects | .[$k]? | select(type == "string")] | first // ""' \
        2>/dev/null || printf ''
  }

  [ "$(field agent_status)" = "blocked" ] || return 0

  who=$(field display_agent)
  [ -n "$who" ] || who=$(field agent)
  [ -n "$who" ] || who="An agent"
  what=$(field title)

  notify-send -a herd -u normal "$who needs you" "$what" 2>/dev/null || true
}

# ---------------------------------------------------------------------- main

# Coalesce bursts. working<->idle churns hard with several agents running, and
# every transition fires this script. If a sync already holds the lock, mark
# the work dirty and leave: the holder loops once more and publishes state at
# least as new as ours would have been.
exec 9>"$LOCK"
if ! flock -n 9; then
  : >"$DIRTY"
  notify_blocked
  exit 0
fi

notify_blocked

while :; do
  rm -f "$DIRTY"
  publish
  [ -e "$DIRTY" ] || break
done
