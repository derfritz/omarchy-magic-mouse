import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Magic Mouse settings popup. Every control writes straight to
// ~/.config/magic-mouse/config.toml through `magic-mouse-config`; the daemon
// hot-reloads that file, so sliders take effect while you drag.
Panel {
  id: root
  moduleName: "io.github.maikunari.magic-mouse"
  ipcTarget: "io.github.maikunari.magic-mouse"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property bool openedFromHotkey: false

  // Battery info handed over by the bar widget.
  property string batteryText: ""

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }
  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }
  // Hide first: if anything after this throws, the full-screen overlay must
  // still go away, or it keeps eating every click on every monitor.
  function close() {
    root.controller.hide()
    setCenterHoverRevealSuppressed(false)
  }
  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  // On Omarchy 4.0.3+ third-party widgets get PluginBarApi, where
  // centerHoverRevealSuppressed is read-only and assigning it throws; go
  // through its setter. On older Omarchy `bar` is the raw Bar, which has the
  // writable property but no setter, so fall back to assigning it directly
  // (same shape as Omarchy's own weather/clock panels).
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- config state
  property var cfg: null
  function val(section, key, fallback) {
    if (!cfg || !cfg[section] || cfg[section][key] === undefined) return fallback
    return cfg[section][key]
  }
  function refresh() {
    if (!readProc.running) readProc.running = true
  }

  Process {
    id: readProc
    command: ["magic-mouse-config", "get"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.cfg = JSON.parse(text) } catch (e) { console.warn("magic-mouse: bad config json", e) }
      }
    }
  }

  // Pending writes are coalesced so a slider drag becomes a handful of writes.
  property var pending: ({})
  function set(section, key, value) {
    var next = Object.assign({}, pending)
    next[section + "." + key] = value
    pending = next
    // Optimistic local update so the UI doesn't snap back before the reload.
    if (cfg && cfg[section]) {
      var c = JSON.parse(JSON.stringify(cfg))
      c[section][key] = value
      cfg = c
    }
    writeTimer.restart()
  }
  Timer {
    id: writeTimer
    interval: 120
    onTriggered: root.flush()
  }
  function flush() {
    var keys = Object.keys(pending)
    if (keys.length === 0 || writeProc.running) { if (keys.length) writeTimer.restart(); return }
    var args = ["magic-mouse-config", "set"]
    for (var i = 0; i < keys.length; i++) args.push(keys[i] + "=" + String(pending[keys[i]]))
    pending = ({})
    writeProc.command = args
    writeProc.running = true
  }
  Process {
    id: writeProc
    onExited: function(code) { if (code !== 0) console.warn("magic-mouse-config failed", code) }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/magic-mouse/config.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: if (!writeTimer.running && !writeProc.running) root.refresh()
  }
  Component.onCompleted: root.refresh()

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontFam: bar ? bar.fontFamily : Style.font.family

  function fmt1(v) { return (Math.round(v * 100) / 100).toString() }

  // ---- a labelled slider row
  component SliderRow: Column {
    id: row
    property string label: ""
    property string valueText: ""
    property real minimum: 0
    property real maximum: 1
    property real step: 0.05
    property real value: 0
    signal changed(real v)
    width: parent.width
    spacing: Style.space(4)
    Item {
      width: parent.width
      height: labelText.implicitHeight
      Text { id: labelText; text: row.label; color: root.fg; font.family: root.fontFam; font.pixelSize: Style.font.body; anchors.left: parent.left }
      Text { text: row.valueText; color: root.dim; font.family: root.fontFam; font.pixelSize: Style.font.caption; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
    }
    function snap(v) {
      var s = Math.round((v - row.minimum) / row.step) * row.step + row.minimum
      s = Math.max(row.minimum, Math.min(row.maximum, s))
      return Math.round(s * 10000) / 10000
    }
    PanelSlider {
      bar: root.bar
      width: parent.width
      minimum: row.minimum
      maximum: row.maximum
      step: row.step
      value: row.value
      onMoved: function(v) { row.changed(row.snap(v)) }
      onReleased: function(v) { row.changed(row.snap(v)) }
    }
  }

  // ---- a labelled switch row
  component SwitchRow: Item {
    id: srow
    property string label: ""
    property string description: ""
    property bool checked: false
    signal toggled()
    width: parent.width
    implicitHeight: Math.max(labels.implicitHeight, sw.implicitHeight)
    Column {
      id: labels
      anchors.left: parent.left
      anchors.right: sw.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text { text: srow.label; color: root.fg; font.family: root.fontFam; font.pixelSize: Style.font.body; width: parent.width; elide: Text.ElideRight }
      Text { text: srow.description; visible: text !== ""; color: root.dim; font.family: root.fontFam; font.pixelSize: Style.font.caption; width: parent.width; wrapMode: Text.WordWrap }
    }
    ToggleSwitch {
      id: sw
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: srow.checked
      foreground: root.fg
      onToggled: srow.toggled()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)
          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍽"
            color: root.fg
            font.family: root.fontFam
            font.pixelSize: Style.font.display
          }
          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text { text: "Magic Mouse"; color: root.fg; font.family: root.fontFam; font.pixelSize: Style.font.title; font.bold: true; width: parent.width; elide: Text.ElideRight }
            Text { text: (root.batteryText !== "" ? root.batteryText : "Mac-like on Omarchy").toUpperCase(); color: root.dim; font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.2; width: parent.width; elide: Text.ElideRight }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.fg }

        // ---------- Pointer ----------
        PanelSectionHeader { text: "POINTER"; foreground: root.fg; fontFamily: root.fontFam }
        SliderRow {
          label: "Tracking speed"
          valueText: root.fmt1(root.val("pointer", "tracking_speed", 0.6875)) + (Math.abs(root.val("pointer", "tracking_speed", 0.6875) - 0.6875) < 0.01 ? "  (Apple default)" : "")
          minimum: 0; maximum: 3; step: 0.0625
          value: root.val("pointer", "tracking_speed", 0.6875)
          onChanged: function(v) { root.set("pointer", "tracking_speed", Math.round(v * 10000) / 10000) }
        }

        // ---------- Clicking ----------
        PanelSectionHeader { text: "CLICKING"; foreground: root.fg; fontFamily: root.fontFam }
        SwitchRow {
          label: "Right-side click is a right click"
          description: "Off: the whole mouse left-clicks, like macOS with secondary click off"
          checked: root.val("buttons", "right_click", true) === true
          onToggled: root.set("buttons", "right_click", !(root.val("buttons", "right_click", true) === true))
        }
        SwitchRow {
          label: "Control-click is a right click"
          description: "Hold Control and click to open menus, like on a Mac"
          checked: root.val("buttons", "control_click", false) === true
          onToggled: root.set("buttons", "control_click", !(root.val("buttons", "control_click", false) === true))
        }

        // ---------- Scrolling ----------
        PanelSectionHeader { text: "SCROLLING"; foreground: root.fg; fontFamily: root.fontFam }
        SwitchRow {
          label: "Natural scrolling"
          description: "Content follows the finger"
          checked: root.val("scroll", "natural", true) === true
          onToggled: root.set("scroll", "natural", !(root.val("scroll", "natural", true) === true))
        }
        SliderRow {
          label: "Scroll speed"
          valueText: root.fmt1(root.val("scroll", "speed", 1.0)) + "×"
          minimum: 0.4; maximum: 2.5; step: 0.1
          value: root.val("scroll", "speed", 1.0)
          onChanged: function(v) { root.set("scroll", "speed", Math.round(v * 100) / 100) }
        }
        SliderRow {
          label: "Finger travel before a scroll starts"
          valueText: root.fmt1(root.val("scroll", "start_mm", 0.8)) + " mm"
          minimum: 0.3; maximum: 2.0; step: 0.1
          value: root.val("scroll", "start_mm", 0.8)
          onChanged: function(v) { root.set("scroll", "start_mm", Math.round(v * 100) / 100) }
        }

        // ---------- Momentum ----------
        PanelSectionHeader { text: "MOMENTUM"; foreground: root.fg; fontFamily: root.fontFam }
        SwitchRow {
          label: "Momentum scrolling"
          description: "Flick and lift, the page keeps gliding"
          checked: root.val("momentum", "enabled", true) === true
          onToggled: root.set("momentum", "enabled", !(root.val("momentum", "enabled", true) === true))
        }
        SliderRow {
          label: "Glide length"
          valueText: root.val("momentum", "decay", 0.97) >= 0.983 ? "long (macOS)" : (root.val("momentum", "decay", 0.97) <= 0.955 ? "short" : "medium")
          minimum: 0.94; maximum: 0.99; step: 0.005
          value: root.val("momentum", "decay", 0.97)
          onChanged: function(v) { root.set("momentum", "decay", Math.round(v * 1000) / 1000) }
        }

        // ---------- Gestures ----------
        PanelSectionHeader { text: "GESTURES"; foreground: root.fg; fontFamily: root.fontFam }
        SwitchRow {
          label: "Swipe between pages"
          description: "One-finger sideways flick = back / forward"
          checked: root.val("gestures", "swipe_pages", true) === true
          onToggled: root.set("gestures", "swipe_pages", !(root.val("gestures", "swipe_pages", true) === true))
        }
        SwitchRow {
          label: "Two-finger swipe switches workspace"
          checked: String(root.val("gestures", "two_finger_swipe_left", "")) !== ""
          onToggled: {
            var on = String(root.val("gestures", "two_finger_swipe_left", "")) !== ""
            root.set("gestures", "two_finger_swipe_left", on ? "" : 'dispatch hl.dsp.focus({ workspace = "e+1" })')
            root.set("gestures", "two_finger_swipe_right", on ? "" : 'dispatch hl.dsp.focus({ workspace = "e-1" })')
          }
        }

        // ---------- Bar ----------
        PanelSectionHeader { text: "BAR"; foreground: root.fg; fontFamily: root.fontFam }
        SwitchRow {
          label: "Show battery percentage"
          description: "Off shows just the icon; low battery still highlights"
          checked: root.val("bar", "show_percent", true) === true
          onToggled: root.set("bar", "show_percent", !(root.val("bar", "show_percent", true) === true))
        }

        Text {
          width: parent.width
          text: "More knobs: ~/.config/magic-mouse/config.toml"
          color: root.dim
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
