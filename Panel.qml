import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The linter cannot see Quickshell's C++ type registration nor the dynamic
// members of the theme singletons (Style.font.*, Color.* read as missing).
// Same blind spot the first-party panels hit; every other check still runs.
// qmllint disable uncreatable-type missing-property unqualified

// Herd — the attention surface. Which agent under herdr needs you.
//
// One bar icon and one tray. The icon says whether anything is waiting on you;
// the tray says who, and clicking a row takes you there. Counts alone were the
// first attempt and were wrong: a chip reading "2 blocked" is a status line,
// not somewhere you can act, and at bar size it is unreadable besides.
//
// This file is a pure display. The other half of the plugin (herdr/) subscribes
// to herdr's own events and writes ~/.local/state/omarchy/herd/herd.json; this
// panel draws whatever appears there, the same way omarchy.agents draws the
// records omarchy-agent-usage-update writes. Neither half imports the other.
Panel {
  id: root
  moduleName: "brownfamilysports.herd"
  ipcTarget: "brownfamilysports.herd"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir:
    (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omarchy/herd"
  readonly property string configuredSocket: setting("socketPath", "")
  readonly property string socketPath:
    configuredSocket !== "" ? configuredSocket : home + "/.config/herdr/herdr.sock"
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", true)

  // Where this plugin was installed. `omarchy plugin add` clones the whole
  // repository, so the herdr half sits under herdr/ right here — no second
  // path to configure, and no guess at the install directory's name.
  readonly property string pluginDir: {
    var u = Qt.resolvedUrl(".").toString()
    return u.replace(/^file:\/\//, "").replace(/\/$/, "")
  }

  property bool serverUp: false
  property var agents: []
  property string cursorPane: ""

  // ------------------------------------------------------------------ model

  function groupOf(status) {
    if (status === "blocked" || status === "working" || status === "done") return status
    return "rest"
  }

  function rank(status) {
    var g = groupOf(status)
    if (g === "blocked") return 0
    if (g === "working") return 1
    if (g === "done") return 2
    return 3
  }

  // Blocked first, always. The list is ordered by how much each agent wants
  // something from you, not by when it happened to start.
  readonly property var ordered: {
    var list = []
    for (var i = 0; i < agents.length; i++) if (agents[i]) list.push(agents[i])
    list.sort(function (a, b) {
      var d = rank(a.status) - rank(b.status)
      return d !== 0 ? d : String(a.pane).localeCompare(String(b.pane))
    })
    return list
  }

  // Grouped, because one flat list under a "NEEDS YOU" header tells the reader
  // that everything under it needs them, which is false the moment a second
  // state exists. A section that has no agents in it is not drawn at all.
  readonly property var sections: {
    var defs = [
      { key: "blocked", title: "NEEDS YOU", alarm: true },
      { key: "working", title: "RUNNING", alarm: false },
      { key: "done", title: "FINISHED", alarm: false },
      { key: "rest", title: "IDLE", alarm: false }
    ]
    var out = []
    for (var d = 0; d < defs.length; d++) {
      var rows = []
      for (var i = 0; i < ordered.length; i++)
        if (groupOf(ordered[i].status) === defs[d].key) rows.push(ordered[i])
      if (rows.length > 0)
        out.push({ title: defs[d].title, alarm: defs[d].alarm, rows: rows })
    }
    return out
  }

  function tally(status) {
    var n = 0
    for (var i = 0; i < agents.length; i++)
      if (agents[i] && agents[i].status === status) n++
    return n
  }

  readonly property int blocked: tally("blocked")
  readonly property int working: tally("working")
  readonly property int finished: tally("done")

  readonly property string heroMeta: {
    if (agents.length === 0) return "no agents"
    var parts = []
    if (blocked > 0) parts.push(blocked + " waiting on you")
    if (working > 0) parts.push(working + " working")
    if (finished > 0) parts.push(finished + " done")
    var resting = agents.length - blocked - working - finished
    if (resting > 0) parts.push(resting + " idle")
    return parts.join(" · ")
  }

  // herdr has no error state — it folds rate limits and API failures into
  // `unknown` — so nothing here claims one.
  function badgeFor(status) {
    var g = groupOf(status)
    if (g === "blocked") return "‖"
    if (g === "working") return "▶"
    if (g === "done") return "✓"
    return "·"
  }

  function colorFor(status) {
    var g = groupOf(status)
    if (g === "blocked") return urgent
    if (g === "working") return foreground
    return dim
  }

  function labelFor(status) {
    if (status === "blocked") return "waiting on you"
    if (status === "working") return "working"
    if (status === "done") return "done"
    if (status === "idle") return "idle"
    return status
  }

  // ----------------------------------------------------------------- action

  function jumpTo(pane) {
    if (!pane || !root.bar) return
    root.bar.run("sh '" + pluginDir + "/herdr/herd-focus.sh' '" + pane + "'")
    root.close()
  }

  function jumpToCursor() {
    if (ordered.length === 0) return
    var pane = cursorPane !== "" ? cursorPane : ordered[0].pane
    jumpTo(pane)
  }

  // The cursor follows the agent, not the slot it happens to occupy: an agent
  // that finishes while the tray is open re-sorts the list, and an index would
  // silently move the selection onto a different agent under the reader.
  function moveCursor(delta) {
    if (ordered.length === 0) return
    var at = 0
    for (var i = 0; i < ordered.length; i++)
      if (ordered[i].pane === cursorPane) { at = i; break }
    at = Math.max(0, Math.min(at + delta, ordered.length - 1))
    cursorPane = ordered[at].pane
  }

  // ------------------------------------------------------------------- bar

  visible: serverUp && (agents.length > 0 || !hideWhenEmpty)
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) cursorPane = ordered.length > 0 ? ordered[0].pane : ""

  // ------------------------------------------------------------------ state

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
    onExited: function (exitCode) {
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

    function refresh(): void { root.broadcast("refreshNow") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // ------------------------------------------------------------- bar button

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: root.blocked > 0
    tooltipText: root.blocked > 0
      ? (root.blocked === 1 ? "1 agent is waiting on you"
                            : root.blocked + " agents are waiting on you")
      : root.heroMeta
    onPressed: function (buttonCode) {
      // Right-click is the shortcut for the only urgent case: go straight to
      // the agent that is waiting, without reading the tray first.
      if (buttonCode === Qt.RightButton && root.blocked > 0) root.jumpTo(root.ordered[0].pane)
      else root.toggle()
    }
  }

  // ------------------------------------------------------------------- tray

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.jumpToCursor()
      onReturnRequested: root.jumpToCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "Herd"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          Repeater {
            model: root.sections

            Column {
              id: section
              required property var modelData

              width: column.width
              spacing: Style.space(4)

              PanelSectionHeader {
                width: parent.width
                text: section.modelData.title
                foreground: section.modelData.alarm ? root.urgent : root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: section.modelData.rows

                // One agent, one row you can act on. The state is spelled out
                // rather than left to the badge: "waiting on you" is the whole
                // point of the tray, and a glyph makes the reader translate it.
                Rectangle {
                  id: agentRow
                  required property var modelData

                  width: parent.width
                  height: Style.space(46)
                  radius: Style.space(6)
                  color: root.cursorPane === agentRow.modelData.pane
                    ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    : "transparent"

                  Text {
                    id: badge
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.badgeFor(agentRow.modelData.status)
                    color: root.colorFor(agentRow.modelData.status)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Column {
                    anchors.left: badge.right
                    anchors.leftMargin: Style.space(12)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: (agentRow.modelData.agent || "agent") + "  ·  "
                            + root.labelFor(agentRow.modelData.status)
                      color: root.groupOf(agentRow.modelData.status) === "blocked"
                        ? root.urgent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: (agentRow.modelData.workspace || "")
                            + (agentRow.modelData.title ? "  " + agentRow.modelData.title : "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      visible: text !== ""
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.cursorPane = agentRow.modelData.pane
                    onClicked: root.jumpTo(agentRow.modelData.pane)
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.ordered.length === 0
            text: "herdr is running, with no agents in it yet."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
