import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // With per-monitor workspaces enabled, each monitor has its own 1-10, in a
  // block of ten per monitor: 1-10, 11-20, and so on (see
  // default/hypr/monitor-workspaces.lua). Each bar shows its own monitor's block,
  // numbered 1-10, and the one that monitor shows, whichever monitor has focus.
  readonly property int slots: 10

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  property bool perMonitorWorkspaces: true

  FileView {
    id: workspaceScope
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/toggles/no-monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.setPerMonitor(false)
    onLoadFailed: root.setPerMonitor(true)
  }

  // Switching modes renumbers workspaces, and Quickshell can keep the old
  // numbers around, so ask Hyprland for the current lists.
  function setPerMonitor(value) {
    var changed = root.perMonitorWorkspaces !== value
    root.perMonitorWorkspaces = value
    if (changed) {
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
    }
  }

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  // Connector -> block, from the file Hyprland keeps them in. Omarchy 4.5
  // writes omarchy/monitor-workspaces; later releases moved it to
  // omarchy/monitors/workspaces. The newer file wins when both exist.
  property var blocks: ({})
  property string blocksText: ""
  property string legacyBlocksText: ""

  function updateBlocks() {
    root.readBlocks(root.blocksText !== "" ? root.blocksText : root.legacyBlocksText)
  }

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitors/workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.blocksText = text(); root.updateBlocks() }
    onLoadFailed: { root.blocksText = ""; root.updateBlocks() }
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.legacyBlocksText = text(); root.updateBlocks() }
    onLoadFailed: { root.legacyBlocksText = ""; root.updateBlocks() }
  }

  function blockOf(id) {
    return Math.floor((id - 1) / root.slots)
  }

  function slotOf(id) {
    if (!root.perMonitorWorkspaces) return id
    return (id - 1) % root.slots + 1
  }

  function activeWorkspaceId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  // Until Hyprland has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    var active = root.activeWorkspaceId()
    return active > 0 ? root.blockOf(active) : 0
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function inUse(workspace) {
    return workspace.active === true || (workspace.toplevels !== null && workspace.toplevels !== undefined && workspace.toplevels.values.length > 0)
  }

  // Show the first five and any other existing workspaces. In per-monitor mode
  // these are local slots, followed by guests from an unplugged monitor. In
  // global mode every bar shows the same actual ids, including ids above ten.
  function workspaceIds() {
    var base = root.perMonitorWorkspaces ? root.block * root.slots : 0
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      // Classic shows 1-10, as Omarchy 4.0.6 did, and above ten only a
      // workspace with windows or on a screen: compact leaves one there when
      // 1-10 are all taken, and rules or scripts can open one. An empty one is
      // skipped, as Quickshell can keep a stale entry after a workspace
      // changes number.
      if (!root.perMonitorWorkspaces && id > root.slots && !root.inUse(values[i])) continue
      if (!root.perMonitorWorkspaces || root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  function focusWorkspace(id) {
    if (root.perMonitorWorkspaces && root.blockOf(id) === root.block) {
      root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")")
    } else {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
  }

  // A wheel notch moves one entry along the row, and a touchpad adds up its
  // smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function scrollWorkspaces(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return

    // Holds at either end rather than wrapping, so a touchpad swipe that runs
    // long stops on the last workspace.
    var ids = root.workspaceIds()
    var index = ids.indexOf(root.activeWorkspaceId())
    if (index === -1) return
    var target = ids[Util.clamp(index - wheel.steps, 0, ids.length - 1)]
    if (target !== ids[index]) root.focusWorkspace(target)
  }

  // The workspace each monitor shows carries its layout: a square tiles, a
  // circle scrolls, and a triangle floats. Clicking it cycles to the next one,
  // as Super + L does.
  property string activeMode: "dwindle"
  property bool modeStale: false

  function modeGlyph(mode) {
    if (mode === "scrolling") return "󰝥"
    if (mode === "floating") return "󰔶"
    return "󱓻"
  }

  // A layout only changes through the layout commands, which ask for a refresh,
  // or a config reload, so each workspace's mode is read once and cached rather
  // than running the script on every workspace switch.
  property var modeCache: ({})
  property int modeGeneration: 0
  property int modeProcWorkspace: -1
  property int modeProcGeneration: 0

  function showActiveMode() {
    var mode = root.modeCache[root.activeWorkspaceId()]
    if (mode !== undefined) root.activeMode = mode
    else readMode()
  }

  function readMode() {
    if (modeProc.running) {
      root.modeStale = true
      return
    }
    var id = root.activeWorkspaceId()
    if (id === -1) return
    root.modeProcWorkspace = id
    root.modeProcGeneration = root.modeGeneration
    modeProc.command = ["omarchy-hyprland-workspace-layout-current", String(id)]
    modeProc.running = true
  }

  function refresh() {
    root.modeCache = ({})
    root.modeGeneration++
    readMode()
  }

  // The layout commands act on the focused workspace, so a click on another
  // monitor's bar focuses that monitor first.
  // Workspace mode switch (Classic Workspaces plugin): Classic is one global set
  // 1-10, 4.5 Workspaces is Omarchy's per monitor. The bin/mode script reloads
  // Hyprland, which refreshes this widget through configreloaded.
  readonly property string modeScript: decodeURIComponent(Qt.resolvedUrl("bin/mode").toString().replace(/^file:\/\//, ""))

  function setClassic(classic) {
    if (root.bar) root.bar.run(Util.shellQuote(root.modeScript) + (classic ? " classic" : " 4.5"))
  }

  property bool modePopupOpen: false

  function close() { root.modePopupOpen = false }

  function cycleLayout() {
    if (!root.bar) return
    var command = "omarchy-hyprland-workspace-layout-toggle"
    if (root.monitor && !root.monitor.focused) {
      command = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + root.monitorName + "\" })") + " >/dev/null && " + command
    }
    root.bar.run(command)
  }

  Component.onCompleted: refresh()
  onMonitorChanged: root.showActiveMode()

  Connections {
    target: root.monitor
    function onActiveWorkspaceChanged() { root.showActiveMode() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") {
        workspaceScope.reload()
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        root.refresh()
      }
      // Quickshell credits every workspace switch to the focused monitor, as
      // the event doesn't say which one switched, and misses the workspace a
      // monitor falls back to when its own is moved away. Moving workspaces
      // between monitors switches the others, so ask Hyprland for the truth.
      // A workspace that changes number is only learned by asking too. Every
      // bar shares what Hyprland answers, so one asks after a plain switch.
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
      // A renumbered workspace's windows are only moved to the new number in
      // Quickshell's model by asking again.
      if (name === "changeworkspaceid") Hyprland.refreshToplevels()
    }
  }

  Process {
    id: modeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var mode = text.trim()
        // A read that started before a refresh may predate the change.
        if (!mode || root.modeProcGeneration !== root.modeGeneration) return
        root.modeCache[root.modeProcWorkspace] = mode
        if (root.modeProcWorkspace === root.activeWorkspaceId()) root.activeMode = mode
      }
    }
    onExited: {
      if (!root.modeStale) return
      root.modeStale = false
      // Deferred: the process still reports running while it signals exit.
      Qt.callLater(root.showActiveMode)
    }
  }

  // Super + L and the default layout change the mode without a focus change,
  // so they ask every bar to read it again.
  ShellIpc {
    target: "omarchy.workspaces"

    function refresh(): void { root.broadcast("refresh") }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length + 1
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
        readonly property int slot: root.slotOf(modelData)
        readonly property bool firstGuest: root.perMonitorWorkspaces && root.blockOf(modelData) !== root.block && index > 0 && root.blockOf(root.workspaceIds()[index - 1]) === root.block
        required property int index

        // A gap sets visiting workspaces apart from the monitor's own.
        Layout.leftMargin: firstGuest && !root.vertical ? Style.space(6) : 0
        Layout.topMargin: firstGuest && root.vertical ? Style.space(6) : 0

        bar: root.bar
        text: shown ? root.modeGlyph(root.activeMode) : (root.perMonitorWorkspaces && slot === root.slots ? "0" : String(slot))
        opacity: occupied || shown ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() {
          if (shown) root.cycleLayout()
          else root.focusWorkspace(modelData)
        }
        onWheelMoved: function(delta) { root.scrollWorkspaces(delta) }
      }
    }

    WidgetButton {
      id: modeButton
      bar: root.bar
      text: root.perMonitorWorkspaces ? "󰍹" : "󰕰"
      tooltipText: root.modePopupOpen ? "" : strings.t("mode.tooltip")
      opacity: root.modePopupOpen ? 1 : 0.6
      horizontalMargin: 4
      verticalPadding: 6
      fixedHeight: root.barSize
      Layout.leftMargin: root.vertical ? 0 : Style.space(2)
      Layout.topMargin: root.vertical ? Style.space(2) : 0
      onPressed: function() { root.modePopupOpen = !root.modePopupOpen }
    }
  }

  PopupCard {
    id: modePopup
    anchorItem: modeButton
    bar: root.bar
    owner: root
    open: root.modePopupOpen
    contentWidth: modePopup.fittedContentWidth(Style.space(300))
    contentHeight: modePopup.fittedContentHeight(modeColumn.implicitHeight)

    Column {
      id: modeColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: strings.t("card.title")
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Toggle {
        width: parent.width
        label: strings.t("mode.classic")
        description: root.perMonitorWorkspaces
          ? strings.t("mode.offDescription")
          : strings.t("mode.onDescription")
        checked: !root.perMonitorWorkspaces
        onClicked: root.setClassic(root.perMonitorWorkspaces)
      }
    }
  }
}
