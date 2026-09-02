#!/bin/sh
# Herd's test suite. POSIX sh, no framework, one dependency (jq) that the
# plugin itself already needs.
#
#   tests/run.sh
#
# Everything runs against stubs in tests/stubs, so no herdr server, no Omarchy
# shell and no desktop session are required. That is deliberate: the parts that
# need a live herdr are the parts a test cannot honestly cover, and pretending
# otherwise would make the suite lie about what it proves.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
STUBS="$ROOT/tests/stubs"
PATH="$STUBS:$PATH"
export PATH

PASS=0
FAIL=0

pass() { PASS=$(( PASS + 1 )); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$(( FAIL + 1 )); printf '  FAIL %s\n       %s\n' "$1" "$2"; }

check() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

check_contains() {
  case "$3" in
    *"$2"*) pass "$1" ;;
    *) fail "$1" "expected to contain [$2], got [$3]" ;;
  esac
}

section() { printf '\n%s\n' "$1"; }

# A fresh state directory and home per test, so nothing leaks between them.
sandbox() {
  SANDBOX=$(mktemp -d)
  export SANDBOX
  HOME="$SANDBOX/home"
  XDG_STATE_HOME="$SANDBOX/state"
  HERDR_BIN_PATH="$STUBS/herdr"
  HERD_STUB_LOG="$SANDBOX/stub.log"
  HERD_NOTIFY_LOG="$SANDBOX/notify.log"
  HERD_STUB_MODE=ok
  HERD_STUB_HYPR=new
  export HOME XDG_STATE_HOME HERDR_BIN_PATH HERD_STUB_LOG HERD_NOTIFY_LOG \
         HERD_STUB_MODE HERD_STUB_HYPR
  unset HERDR_PLUGIN_EVENT_JSON HERDR_PLUGIN_CONFIG_DIR 2>/dev/null || true
  mkdir -p "$HOME"
  STATE_JSON="$XDG_STATE_HOME/omarchy/herd/herd.json"
}

sync() { sh "$ROOT/herdr/herd-sync.sh"; }
focus() { sh "$ROOT/herdr/herd-focus.sh" "$@"; }

notify_count() { [ -f "$HERD_NOTIFY_LOG" ] && wc -l <"$HERD_NOTIFY_LOG" | tr -d ' ' || echo 0; }
stub_log() { [ -f "$HERD_STUB_LOG" ] && cat "$HERD_STUB_LOG" || printf ''; }

# ---------------------------------------------------------------- herd-sync

section 'herd-sync.sh'

sandbox
sync
check 'maps every agent in the list' '4' "$(jq '.agents | length' "$STATE_JSON")"
check 'keeps herdr pane ids' 'w1:p1' "$(jq -r '.agents[0].pane' "$STATE_JSON")"
check 'carries the state through' 'blocked' "$(jq -r '.agents[0].status' "$STATE_JSON")"
check 'prefers display_agent' 'Claude Code' "$(jq -r '.agents[0].agent' "$STATE_JSON")"
check 'falls back to agent when display_agent is absent' 'gemini' \
  "$(jq -r '.agents[] | select(.pane == "w2:p1") | .agent' "$STATE_JSON")"
check 'defaults a missing title to empty, not null' '' \
  "$(jq -r '.agents[] | select(.pane == "w2:p2") | .title' "$STATE_JSON")"
check 'stamps the snapshot' 'number' "$(jq -r '.stamp | type' "$STATE_JSON")"
check 'leaves no temporary file behind' '0' \
  "$(find "$XDG_STATE_HOME/omarchy/herd" -name 'herd.json.tmp*' | wc -l | tr -d ' ')"

sandbox
HERD_STUB_MODE=down sync
check 'a stopped server publishes an empty herd, not a stale one' '0' \
  "$(jq '.agents | length' "$STATE_JSON")"

sandbox
HERD_STUB_MODE=garbage sync
check 'unparseable output still leaves valid json' '0' \
  "$(jq '.agents | length' "$STATE_JSON")"

sandbox
sync
HERD_STUB_MODE=down sync
check 'a herd that empties is republished, not left behind' '0' \
  "$(jq '.agents | length' "$STATE_JSON")"

section 'herd-sync.sh — notifications'

sandbox
sync
check 'startup publishes without ringing' '0' "$(notify_count)"

sandbox
HERDR_PLUGIN_EVENT_JSON='{"pane_id":"w1:p1","agent_status":"working","display_agent":"Codex"}' \
  sync
check 'a working agent stays silent' '0' "$(notify_count)"

sandbox
HERDR_PLUGIN_EVENT_JSON='{"pane_id":"w1:p1","agent_status":"done","display_agent":"Codex"}' \
  sync
check 'a finished agent stays silent' '0' "$(notify_count)"

sandbox
HERDR_PLUGIN_EVENT_JSON='{"pane_id":"w1:p1","agent_status":"blocked","display_agent":"Claude Code","title":"omarchy-herd"}' \
  sync
check 'a blocked agent rings once' '1' "$(notify_count)"
check_contains 'the notification names the agent' 'Claude Code needs you' "$(cat "$HERD_NOTIFY_LOG")"

sandbox
HERDR_PLUGIN_EVENT_JSON='{"type":"pane.agent_status_changed","event":{"pane_id":"w1:p1","agent_status":"blocked","display_agent":"Codex"}}' \
  sync
check 'a nested event envelope still rings' '1' "$(notify_count)"

sandbox
HERDR_PLUGIN_EVENT_JSON='{"pane_id":"w1:p1","agent_status":"blocked","agent":"claude"}' sync
check_contains 'falls back to agent for the name' 'claude needs you' "$(cat "$HERD_NOTIFY_LOG")"

# herdr's screen detection flaps; three of its open issues are exactly that.
# A pane that re-enters blocked inside the window must not ring again.
sandbox
E='{"pane_id":"w1:p1","agent_status":"blocked","display_agent":"Claude Code"}'
HERDR_PLUGIN_EVENT_JSON="$E" sync
HERDR_PLUGIN_EVENT_JSON="$E" sync
HERDR_PLUGIN_EVENT_JSON="$E" sync
check 'a flapping agent rings once, not once per flap' '1' "$(notify_count)"

sandbox
HERDR_PLUGIN_EVENT_JSON='{"pane_id":"w1:p1","agent_status":"blocked","display_agent":"A"}' sync
HERDR_PLUGIN_EVENT_JSON='{"pane_id":"w2:p2","agent_status":"blocked","display_agent":"B"}' sync
check 'a different pane rings on its own' '2' "$(notify_count)"

sandbox
E='{"pane_id":"w1:p1","agent_status":"blocked","display_agent":"Claude Code"}'
HERD_NOTIFY_REPEAT_SECONDS=0 HERDR_PLUGIN_EVENT_JSON="$E" sync
HERD_NOTIFY_REPEAT_SECONDS=0 HERDR_PLUGIN_EVENT_JSON="$E" sync
check 'the repeat window is what suppresses it, and it is configurable' '2' "$(notify_count)"

section 'herd-sync.sh — concurrency'

sandbox
if command -v flock >/dev/null 2>&1; then
  # Hold the lock, then run a sync: it must mark the work dirty and leave
  # rather than block or fail.
  mkdir -p "$XDG_STATE_HOME/omarchy/herd"
  ( flock 9; sleep 2 ) 9>"$XDG_STATE_HOME/omarchy/herd/.lock" &
  HOLDER=$!
  sleep 1
  sync
  RC=$?
  check 'a second sync exits cleanly while one is running' '0' "$RC"
  check 'and leaves the work marked dirty' '1' \
    "$([ -e "$XDG_STATE_HOME/omarchy/herd/.dirty" ] && echo 1 || echo 0)"
  wait "$HOLDER" 2>/dev/null || true
else
  printf '  skip flock unavailable\n'
fi

sandbox
HERD_MAX_PASSES=2 sync
check 'the coalesce loop is bounded and still publishes' '4' \
  "$(jq '.agents | length' "$STATE_JSON")"

# --------------------------------------------------------------- herd-focus

section 'herd-focus.sh'

sandbox
sync
focus
check 'with no argument it goes to the blocked agent' 'focus w1:p1' "$(stub_log)"

sandbox
sync
focus w2:p2
check 'an explicit pane wins' 'focus w2:p2' "$(stub_log)"

sandbox
HERD_STUB_MODE=empty sync
focus
check 'nothing to jump to means nothing happens' '' "$(stub_log)"

sandbox
sync
jq '{stamp, agents: [.agents[] | select(.status != "blocked")]}' "$STATE_JSON" >"$SANDBOX/x" \
  && mv "$SANDBOX/x" "$STATE_JSON"
focus
check 'with nothing blocked it falls back to the finished one' 'focus w2:p2' "$(stub_log)"

sandbox
sync
focus 'w1:p1; rm -rf /'
check 'a pane id that is not a pane id is refused' '' "$(stub_log)"

sandbox
sync
# shellcheck disable=SC2016  # the literal text is the point: it must not expand
focus '$(whoami)'
check 'and so is a substitution attempt' '' "$(stub_log)"

section 'herd-focus.sh — raising the window'

sandbox
sync
mkdir -p "$SANDBOX/cfg"
HERDR_PLUGIN_CONFIG_DIR="$SANDBOX/cfg"
export HERDR_PLUGIN_CONFIG_DIR
printf 'TERMINAL_CLASS=foot\n' >"$SANDBOX/cfg/config.env"
focus
check_contains 'uses the Hyprland 0.56 Lua dispatcher' 'hl.dsp.focus' "$(stub_log)"

sandbox
sync
mkdir -p "$SANDBOX/cfg"
HERDR_PLUGIN_CONFIG_DIR="$SANDBOX/cfg"
export HERDR_PLUGIN_CONFIG_DIR
printf 'TERMINAL_CLASS=foot\n' >"$SANDBOX/cfg/config.env"
HERD_STUB_HYPR=old focus
check_contains 'and falls back to the legacy dispatcher' 'focuswindow' "$(stub_log)"

sandbox
sync
mkdir -p "$SANDBOX/cfg"
HERDR_PLUGIN_CONFIG_DIR="$SANDBOX/cfg"
export HERDR_PLUGIN_CONFIG_DIR
printf 'TERMINAL_CLASS=foot\ntouch %s/pwned\n' "$SANDBOX" >"$SANDBOX/cfg/config.env"
focus
check 'config.env is parsed, never sourced' '0' \
  "$([ -e "$SANDBOX/pwned" ] && echo 1 || echo 0)"
check_contains 'and the setting still takes effect' 'class:foot' "$(stub_log)"

sandbox
sync
mkdir -p "$SANDBOX/cfg"
HERDR_PLUGIN_CONFIG_DIR="$SANDBOX/cfg"
export HERDR_PLUGIN_CONFIG_DIR
printf 'TERMINAL_CLASS=foot; rm -rf /\n' >"$SANDBOX/cfg/config.env"
focus
check_contains 'a malformed class is dropped, and focus still happens' 'focus w1:p1' "$(stub_log)"
case "$(stub_log)" in
  *hl.dsp*) fail 'a malformed class does not reach hyprctl' "it did: $(stub_log)" ;;
  *) pass 'a malformed class does not reach hyprctl' ;;
esac

unset HERDR_PLUGIN_CONFIG_DIR

# ----------------------------------------------------------------- manifests

section 'manifests'

M="$ROOT/manifest.json"
check 'the Omarchy manifest is valid json' '0' "$(jq -e . "$M" >/dev/null 2>&1; echo $?)"
for key in schemaVersion id name version author license description kinds entryPoints; do
  check "it declares $key" 'true' "$(jq --arg k "$key" 'has($k)' "$M")"
done
ENTRY=$(jq -r '.entryPoints.barWidget' "$M")
check 'its bar widget entry point exists' '1' "$([ -f "$ROOT/$ENTRY" ] && echo 1 || echo 0)"
check 'it declares the bar-widget kind' 'true' "$(jq '.kinds | index("bar-widget") != null' "$M")"

T="$ROOT/herdr/herdr-plugin.toml"

# The package keys live above the first [[table]]; `id` also appears inside
# [[actions]], so reading the whole file would compare the wrong one.
toml_package() { awk '/^\[\[/ { exit } { print }' "$T"; }
toml_key() { toml_package | sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\\(.*\\)\"/\\1/p" | head -n 1; }

for key in id name version min_herdr_version platforms; do
  check "the herdr manifest declares $key" '1' \
    "$(toml_package | grep -cE "^${key}[[:space:]]*=" | head -n 1)"
done
check 'both halves carry the same id' "$(jq -r '.id' "$M")" "$(toml_key id)"
check 'both halves carry the same version' "$(jq -r '.version' "$M")" "$(toml_key version)"

# [[startup]] hooks arrived in herdr 0.7.5. Claiming anything older links the
# plugin on a herdr that will silently never publish the first snapshot.
check 'the herdr floor accounts for [[startup]]' '0.7.5' "$(toml_key min_herdr_version)"

# Every event the manifest subscribes to has to be one herdr will actually
# deliver to a plugin hook — PLUGIN_HOOK_EVENT_KINDS in its api schema. Kept on
# one line on purpose: wrapped, the space-delimited match silently stops
# matching whichever name lands at a line end, and the check quietly inverts.
HOOKABLE=' workspace.created workspace.updated workspace.closed workspace.renamed workspace.moved workspace.reordered workspace.focused worktree.created worktree.opened worktree.removed tab.created tab.closed tab.renamed tab.moved tab.focused pane.created pane.closed pane.focused pane.moved pane.exited pane.agent_detected pane.agent_status_changed '
UNKNOWN=''
SUBSCRIBED=0
# shellcheck disable=SC2013  # event names cannot contain whitespace; splitting is the point
for ev in $(sed -n 's/^on[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "$T"); do
  SUBSCRIBED=$(( SUBSCRIBED + 1 ))
  case "$HOOKABLE" in
    *" $ev "*) ;;
    *) UNKNOWN="$UNKNOWN $ev" ;;
  esac
done
check 'every subscribed event is one herdr delivers to plugins' '' "$UNKNOWN"
# A guard on the guard: if the sed above ever stops matching, the check over
# an empty list would pass while proving nothing.
check 'and the events were actually read from the manifest' '4' "$SUBSCRIBED"

for s in herd-sync.sh herd-focus.sh; do
  check "$s is executable" '1' "$([ -x "$ROOT/herdr/$s" ] && echo 1 || echo 0)"
done
MISSING=''
# shellcheck disable=SC2013  # script names cannot contain whitespace; splitting is the point
for cmd in $(sed -n 's/^command[[:space:]]*=[[:space:]]*\["sh",[[:space:]]*"\(.*\)"\]/\1/p' "$T"); do
  [ -f "$ROOT/herdr/$cmd" ] || MISSING="$MISSING $cmd"
done
check 'every script the manifest names is present' '' "$MISSING"

# ---------------------------------------------------------------------- done

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
