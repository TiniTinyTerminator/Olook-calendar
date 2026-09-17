import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The calendar in the bar: what is next, and the agenda behind it.
//
// A second plugin rather than part of Olook's own widget, because a plugin
// registers one bar widget and Olook's is the mail envelope. It reads the
// same cache through the same engine, so what is in the bar and what is in
// the Calendar tab cannot disagree.
Panel {
  id: root
  moduleName: "ttt.olook-calendar"
  ipcTarget: "ttt.olook-calendar"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool showNext: setting("showNextInBar", true) !== false
  readonly property int daysAhead: {
    var value = parseInt(String(setting("daysAhead", 2)), 10)
    return isFinite(value) ? Math.max(1, Math.min(7, value)) : 2
  }
  readonly property int refreshSeconds: {
    var value = parseInt(String(setting("refreshIntervalSec", 300)), 10)
    return isFinite(value) ? Math.max(60, Math.min(3600, value)) : 300
  }

  // Olook installs beside this, so its engine is one directory over. Asking
  // PATH would depend on what the shell inherited, which is not something a
  // bar widget should rely on.
  readonly property string cliPath:
    Qt.resolvedUrl("../ttt.olook/bin/olook").toString().replace(/^file:\/\//, "")

  property var events: []
  property bool loading: false
  property string trouble: ""

  function pad(value) { return value < 10 ? "0" + value : String(value) }

  function dayKey(date) {
    return date.getFullYear() + "-" + root.pad(date.getMonth() + 1)
           + "-" + root.pad(date.getDate())
  }

  function clockOf(event) {
    var from = new Date(event.start * 1000)
    return root.pad(from.getHours()) + ":" + root.pad(from.getMinutes())
  }

  // Today's remaining appointments and the days after it, in order. An
  // appointment that has already finished is not what is next.
  readonly property var upcoming: {
    var now = Math.floor(Date.now() / 1000)
    var out = []
    for (var i = 0; i < root.events.length; i++) {
      var event = root.events[i]
      if (Number(event.end) <= now) continue
      out.push(event)
    }
    return out
  }

  readonly property var nextEvent: root.upcoming.length > 0 ? root.upcoming[0] : null

  // Rows for the panel: a heading per day, then that day's appointments.
  readonly property var agendaRows: {
    var rows = []
    var today = root.dayKey(new Date())
    var seen = ""
    for (var i = 0; i < root.upcoming.length; i++) {
      var event = root.upcoming[i]
      var key = String(event.day || "")
      if (key !== seen) {
        seen = key
        rows.push({ "heading": root.headingFor(key, today), "event": null,
                    "key": "h:" + key })
      }
      rows.push({ "heading": "", "event": event, "key": key + ":" + i })
    }
    return rows
  }

  function headingFor(key, today) {
    if (key === today) return "Today"
    var parts = key.split("-")
    if (parts.length !== 3) return key
    var when = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    var tomorrow = new Date()
    tomorrow.setDate(tomorrow.getDate() + 1)
    if (key === root.dayKey(tomorrow)) return "Tomorrow"
    var names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var months = ["January", "February", "March", "April", "May", "June", "July",
                  "August", "September", "October", "November", "December"]
    return names[(when.getDay() + 6) % 7] + " " + when.getDate()
           + " " + months[when.getMonth()]
  }

  // ------------------------------------------------------------------ data

  function reload() {
    if (root.loading || root.cliPath.indexOf("bin/olook") === -1) return
    var from = new Date()
    var to = new Date()
    to.setDate(to.getDate() + root.daysAhead)
    root.loading = true
    reader.command = [root.cliPath, "--json", "calendar",
                      "--start", root.dayKey(from), "--end", root.dayKey(to)]
    reader.running = true
  }

  Process {
    id: reader
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.loading = false
        var payload = null
        try {
          payload = JSON.parse(text)
        } catch (error) {
          root.trouble = "The calendar could not be read."
          return
        }
        if (!payload || payload.ok === false) {
          root.trouble = String((payload && payload.error) || "")
          root.events = (payload && payload.events) || []
          return
        }
        root.trouble = ""
        root.events = payload.events || []
      }
    }
  }

  Timer {
    running: true
    repeat: true
    triggeredOnStart: true
    interval: root.refreshSeconds * 1000
    onTriggered: root.reload()
  }

  // A minute is the resolution the bar shows, so "what is next" has to be
  // recomputed that often or a finished appointment stays there.
  Timer {
    running: true
    repeat: true
    interval: 30000
    onTriggered: root.eventsChanged()
  }

  onOpenedChanged: if (root.opened) root.reload()

  function openCalendar() {
    root.close()
    var payload = JSON.stringify({ "view": "calendar" })
    if (bar && bar.shell && typeof bar.shell.summon === "function") {
      bar.shell.summon("ttt.olook", payload)
      return
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "summon",
                             "ttt.olook", payload])
  }

  // ------------------------------------------------------------------- bar

  // The bar asks the widget how much room it wants. Without this the plugin
  // loads, takes a slot and paints nothing, which is exactly what it did.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The glyph goes straight on the button. An iconComponent is loaded into
    // a 16-pixel canvas and has to size and colour itself; the text path is
    // what the bar's own widgets use and what its optical centring is for.
    text: "󰃭"
    // BarIconButton reports the button that was pressed, not a plain click.
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) root.reload()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(
      headerColumn.implicitHeight + listColumn.implicitHeight + Style.space(30),
      Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (text) {
        if (text === "r" || text === "R") root.reload()
        else if (text === "o" || text === "O") root.openCalendar()
      }

      Column {
        id: headerColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Calendar"
          meta: {
            if (root.trouble !== "") return "Could not read the calendar"
            if (root.loading && root.events.length === 0) return "Reading…"
            if (!root.nextEvent) return "Nothing coming up"
            var count = root.upcoming.length
            return count === 1 ? "One appointment ahead"
                               : count + " appointments ahead"
          }
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "󰃭"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { foreground: root.foreground }
      }

      Column {
        id: listColumn
        anchors.top: headerColumn.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Style.space(8)

        Text {
          width: parent.width
          visible: root.trouble !== ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: root.trouble
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: parent.width
          visible: root.trouble === "" && root.agendaRows.length === 0
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: root.loading ? "Reading the calendar…"
                             : "Nothing on for the next "
                               + (root.daysAhead === 1 ? "day" : root.daysAhead + " days")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Flickable {
          id: agendaFlick
          width: parent.width
          height: parent.height - y
          contentWidth: width
          contentHeight: agendaColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          MomentumScroll { view: agendaFlick }

          Column {
            id: agendaColumn
            width: agendaFlick.width
            spacing: Style.space(4)

            Repeater {
              model: root.agendaRows

              Item {
                id: agendaRow
                required property var modelData
                width: agendaColumn.width
                implicitHeight: rowBody.implicitHeight + Style.space(6)
                height: implicitHeight

                Rectangle {
                  anchors.fill: parent
                  anchors.margins: -Style.space(2)
                  radius: Style.cornerRadius
                  visible: !!agendaRow.modelData.event && rowHover.containsMouse
                  color: Util.alpha(root.foreground, 0.08)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: agendaRow.modelData.heading !== ""
                  text: agendaRow.modelData.heading
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Row {
                  id: rowBody
                  visible: !!agendaRow.modelData.event
                  width: parent.width
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(3)
                    height: Style.space(16)
                    radius: Style.space(2)
                    color: (agendaRow.modelData.event
                            && agendaRow.modelData.event.colour)
                      ? agendaRow.modelData.event.colour : root.foreground
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(48)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: agendaRow.modelData.event
                      ? (agendaRow.modelData.event.allDay
                         ? "all day" : root.clockOf(agendaRow.modelData.event))
                      : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(70)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: agendaRow.modelData.event
                      ? (agendaRow.modelData.event.summary || "(no title)") : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  id: rowHover
                  anchors.fill: parent
                  hoverEnabled: !!agendaRow.modelData.event
                  cursorShape: agendaRow.modelData.event
                    ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: if (agendaRow.modelData.event) root.openCalendar()
                }
              }
            }
          }
        }
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.reload(); return "ok" }
    function next(): string {
      return root.nextEvent ? String(root.nextEvent.summary || "") : ""
    }
  }
}
