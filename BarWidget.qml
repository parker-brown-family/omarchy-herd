import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The linter cannot see Quickshell's C++ type registration nor the dynamic
// members of the theme singletons (Style.font.*, Color.* read as missing).
// Same blind spot first-party widgets hit; every other check still runs.
// qmllint disable uncreatable-type missing-property unqualified

// Herd — the attention surface. Which agent under herdr needs you, on the bar.
//
// This file is a pure display. The other half of the plugin (herdr/) subscribes
// to herdr's own events and writes ~/.local/state/omarchy/herd/herd.json; this
// widget draws whatever appears there, the same way omarchy.agents draws the
// records omarchy-agent-usage-update writes. Neither half imports the other,
// and either one runs fine with the other missing.
BarWidget {
  id: root
  moduleName: "brownfamilysports.herd"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir:
    (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omarchy/herd"
  readonly property string configuredSocket: setting("socketPath", "")
  readonly property string socketPath:
    configuredSocket !== "" ? configuredSocket : home + "/.config/herdr/herdr.sock"
  readonly property bool showIdle: setting("showIdle", false)
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", true)

  property bool serverUp: false
  property var agents: []

  // ------------------------------------------------------------------ counts

  function tally(status) {
    var n = 0
    for (var i = 0; i < agents.length; i++)
      if (agents[i] && agents[i].status === status) n++
    return n
  }

  readonly property int blocked: tally("blocked")
  readonly property int working: tally("working")
  readonly property int finished: tally("done")
  readonly property int resting: Math.max(0, agents.length - blocked - working - finished)

  // Badges read like Terminal Delight's agent wall. Not the same codepoints:
  // U+23F8 ⏸, which TD uses for blocked, carries Emoji_Presentation, so the
  // bar's font stack substitutes a colour emoji and it lands as a solid blob
  // at bar size. U+2016 ‖ is a plain text glyph, says the same thing, and
  // renders. ▶ ✓ · were checked on the real bar and are fine as they are.
  //
  // herdr has no error state — it folds rate limits and API failures into
  // `unknown` — so nothing here claims one. Unknown rests with idle.
  readonly property string label: {
    var parts = []
    if (blocked > 0) parts.push("‖ " + blocked)
    if (working > 0) parts.push("▶ " + working)
    if (finished > 0) parts.push("✓ " + finished)
    if (showIdle && resting > 0) parts.push("· " + resting)
    return parts.join("  ")
  }

  readonly property string tooltip: {
    if (!serverUp) return "herdr is not running"
    if (agents.length === 0) return "herdr: no agents"
    var lines = []
    for (var i = 0; i < agents.length; i++) {
      var a = agents[i]
      if (!a) continue
      var line = a.status + "  " + (a.agent || "agent")
      if (a.title) line += "  — " + a.title
      lines.push(line)
    }
    if (blocked > 0) lines.push("", "click to jump to the blocked agent")
    return lines.join("\n")
  }

  visible: serverUp && (label !== "" || !hideWhenEmpty)
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  // ------------------------------------------------------------------- state

  FileView {
    path: root.stateDir + "/herd.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.agents = []
  }

  function parse(content) {
    try {
      var doc = JSON.parse(String(content || ""))
      root.agents = (doc && Array.isArray(doc.agents)) ? doc.agents : []
    } catch (e) {
      console.warn("herd", "ignoring unreadable state file", e)
      root.agents = []
    }
  }

  // ---------------------------------------------------------------- liveness
  //
  // herdr removes its socket when the server stops, so a stat tells the truth.
  // Events drive every content update; this only answers "is herdr still
  // there", which no event can ever tell us — the server that would have sent
  // one is the thing that went away.

  Process {
    id: liveness
    command: ["test", "-S", root.socketPath]
    onExited: function(exitCode) {
      root.serverUp = exitCode === 0
      if (!root.serverUp) root.agents = []
    }
  }

  function refreshNow() {
    if (!liveness.running) liveness.running = true
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNow()
  }

  IpcHandler {
    target: "brownfamilysports.herd"

    function refresh(): void {
      root.broadcast("refreshNow")
    }
  }

  // -------------------------------------------------------------------- chip

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    active: root.blocked > 0
    fontSize: Style.font.caption
    tooltipText: root.tooltip
    onPressed: function(mouseButton) {
      if (root.blocked === 0 || !root.bar) return
      root.bar.run("herdr plugin action invoke brownfamilysports.herd.focus-blocked")
    }
  }
}
