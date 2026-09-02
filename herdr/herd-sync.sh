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
NOTIFIED="$STATE_DIR/.notified"

# A blocked agent that flaps — blocked, unknown, blocked — would otherwise ring
# once per flap, and herdr's screen detection does flap; three of its open
# issues are exactly that. Suppress a repeat for the same pane in this window.
NOTIFY_REPEAT_SECONDS="${HERD_NOTIFY_REPEAT_SECONDS:-20}"

# Bound the coalesce loop. A pathological event storm should degrade to a
# slightly stale file, never to a process that does not exit.
MAX_PASSES="${HERD_MAX_PASSES:-8}"

mkdir -p "$STATE_DIR"

TMP="$OUT.tmp.$$"
cleanup() { rm -f "$TMP" "$NOTIFIED.tmp.$$"; }
trap cleanup EXIT INT TERM HUP

# --------------------------------------------------------------- publication

# The whole list, every time, never an incremental patch. An incrementally
# maintained map drifts the moment one event is missed or a server restarts,
# and reconciling it is more code than re-reading. `agent list` is one call
# over a local socket.
publish() {
  now=$(date +%s)

  if raw=$("$HERDR" agent list 2>/dev/null); then
    :
  else
    # No server, or it went away mid-call. Publish an empty herd rather than
    # leaving the bar showing agents that no longer exist.
    raw=''
  fi

  if [ -z "$raw" ]; then
    printf '{"stamp":%s,"agents":[]}\n' "$now" >"$TMP"
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
      }' >"$TMP" 2>/dev/null || printf '{"stamp":%s,"agents":[]}\n' "$now" >"$TMP"
  fi

  # Rename within the same directory, so a reader watching the file never
  # observes a half-written one.
  mv -f "$TMP" "$OUT"
}

# -------------------------------------------------------------- notification

# Read the payload by recursive descent rather than a fixed path: the hook
# envelope is herdr's to change, and the field names are the stable part.
event_field() {
  [ -n "${HERDR_PLUGIN_EVENT_JSON:-}" ] || return 0
  printf '%s' "$HERDR_PLUGIN_EVENT_JSON" \
    | jq -r --arg k "$1" '[.. | objects | .[$k]? | select(type == "string")] | first // ""' \
      2>/dev/null || true
}

# True when this pane already rang inside the repeat window.
recently_notified() {
  [ -f "$NOTIFIED" ] || return 1
  last=$(awk -v p="$1" '$1 == p { t = $2 } END { if (t != "") print t }' "$NOTIFIED" 2>/dev/null || true)
  [ -n "$last" ] || return 1
  [ $(( $2 - last )) -lt "$NOTIFY_REPEAT_SECONDS" ]
}

# Record this ring and drop every entry that has aged out, so the file cannot
# grow without bound on a long-lived server.
record_notified() {
  if [ -f "$NOTIFIED" ]; then
    awk -v p="$1" -v n="$2" -v w="$NOTIFY_REPEAT_SECONDS" \
      '$1 != p && (n - $2) < w' "$NOTIFIED" 2>/dev/null >"$NOTIFIED.tmp.$$" || true
  else
    : >"$NOTIFIED.tmp.$$"
  fi
  printf '%s %s\n' "$1" "$2" >>"$NOTIFIED.tmp.$$"
  mv -f "$NOTIFIED.tmp.$$" "$NOTIFIED"
}

# Only on entering `blocked`. It is the one state that requires a human;
# herdr emits the event on transition, so this fires once per block, not once
# per spinner frame. `done` deliberately stays silent — the bar already shows it.
notify_blocked() {
  [ -n "${HERDR_PLUGIN_EVENT_JSON:-}" ] || return 0
  [ "$(event_field agent_status)" = "blocked" ] || return 0

  pane=$(event_field pane_id)
  [ -n "$pane" ] || pane="unknown"

  stamp=$(date +%s)
  if recently_notified "$pane" "$stamp"; then
    return 0
  fi
  record_notified "$pane" "$stamp"

  who=$(event_field display_agent)
  [ -n "$who" ] || who=$(event_field agent)
  [ -n "$who" ] || who="An agent"
  what=$(event_field title)

  notify-send -a herd -u normal "$who needs you" "$what" 2>/dev/null || true
}

# ---------------------------------------------------------------------- main

# Coalesce bursts. working<->idle churns hard with several agents running, and
# every transition fires this script. If a sync already holds the lock, mark
# the work dirty and leave: the holder loops once more and publishes state at
# least as new as ours would have been.
exec 9>"$LOCK"

if flock -n 9; then
  notify_blocked
  passes=0
  while [ "$passes" -lt "$MAX_PASSES" ]; do
    rm -f "$DIRTY"
    publish
    passes=$(( passes + 1 ))
    [ -e "$DIRTY" ] || break
  done
else
  : >"$DIRTY"
  notify_blocked
fi
