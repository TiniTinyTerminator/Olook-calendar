import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The clock and the calendar in one bar widget.
//
// A second plugin rather than part of Olook's own widget, because a plugin
// registers one bar widget and Olook's is the mail envelope. It reads through
// the same engine as the Calendar tab, so the bar and the window cannot
// disagree about what is on.
//
// It replaces Omarchy's clock rather than sitting beside it: the label is the
// date and time, and the popup is the month that clock was already showing,
// with the days you have something on marked and that day's appointments
// underneath.
Panel {
  id: root
  moduleName: "ttt.olook-calendar"
  ipcTarget: "ttt.olook-calendar"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 2.2)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string clockFormat: String(setting("format", "dddd HH:mm"))
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

  property date now: new Date()
  property var events: []
  property bool loading: false
  property string trouble: ""

  // The month on show in the popup, and the day picked out of it.
  property int viewYear: now.getFullYear()
  property int viewMonth: now.getMonth()
  property string selectedDay: ""

  readonly property var weekdayNames: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
  readonly property var monthNames: ["January", "February", "March", "April",
    "May", "June", "July", "August", "September", "October", "November", "December"]

  function pad(value) { return value < 10 ? "0" + value : String(value) }

  function dayKey(date) {
    return date.getFullYear() + "-" + root.pad(date.getMonth() + 1)
           + "-" + root.pad(date.getDate())
  }

  function clockOf(event) {
    var from = new Date(event.start * 1000)
    return root.pad(from.getHours()) + ":" + root.pad(from.getMinutes())
  }

  readonly property string todayKey: root.dayKey(root.now)

  // ------------------------------------------------------------- the label

  readonly property string labelText: {
    var text = Qt.formatDateTime(root.now, root.clockFormat)
    if (!root.showNext || !root.nextEvent) return text
    // A bare time next to the clock reads as a second clock, which is exactly
    // how it was read. The glyph says which of the two is an appointment.
    return text + "   " + String.fromCodePoint(0xF00F0) + " "
           + (root.nextEvent.allDay ? "all day" : root.clockOf(root.nextEvent))
  }

  // ------------------------------------------------------------- the month

  function monthStart() { return new Date(root.viewYear, root.viewMonth, 1) }

  // The Monday on or before the first, which is where the grid starts.
  function gridStart() {
    var first = root.monthStart()
    var weekday = (first.getDay() + 6) % 7
    return new Date(first.getFullYear(), first.getMonth(), 1 - weekday)
  }

  readonly property var monthCells: {
    var out = []
    var from = root.gridStart()
    for (var i = 0; i < 42; i++) {
      var day = new Date(from.getFullYear(), from.getMonth(), from.getDate() + i)
      out.push({
        "key": root.dayKey(day),
        "number": day.getDate(),
        "outside": day.getMonth() !== root.viewMonth
      })
    }
    return out
  }

  readonly property var byDay: {
    var map = ({})
    for (var i = 0; i < root.events.length; i++) {
      var key = String(root.events[i].day || "")
      if (!key) continue
      if (!map[key]) map[key] = []
      map[key].push(root.events[i])
    }
    return map
  }

  function eventsOn(key) { return root.byDay[key] || [] }

  function step(direction) {
    var moved = new Date(root.viewYear, root.viewMonth + direction, 1)
    root.viewYear = moved.getFullYear()
    root.viewMonth = moved.getMonth()
    root.selectedDay = ""
    root.reload()
  }

  function goToday() {
    root.viewYear = root.now.getFullYear()
    root.viewMonth = root.now.getMonth()
    root.selectedDay = ""
    root.reload()
  }

  // ------------------------------------------------------------ the agenda

  // What is still to come, which is what the bar reports and what the panel
  // opens on. An appointment that has finished is not what is next.
  readonly property var upcoming: {
    var cutoff = Math.floor(root.now.getTime() / 1000)
    var limit = new Date(root.now.getFullYear(), root.now.getMonth(),
                         root.now.getDate() + root.daysAhead)
    var until = Math.floor(limit.getTime() / 1000)
    var out = []
    for (var i = 0; i < root.events.length; i++) {
      var event = root.events[i]
      if (Number(event.end) <= cutoff) continue
      if (Number(event.start) >= until) continue
      out.push(event)
    }
    return out
  }

  readonly property var nextEvent: root.upcoming.length > 0 ? root.upcoming[0] : null

  // Rows for the list: a heading per day, then that day's appointments. With
  // a day picked it is that day alone; otherwise it is what is coming.
  readonly property var agendaRows: {
    var source = root.selectedDay !== "" ? root.eventsOn(root.selectedDay)
                                         : root.upcoming
    var rows = []
    var seen = ""
    for (var i = 0; i < source.length; i++) {
      var event = source[i]
      var key = String(event.day || "")
      if (key !== seen) {
        seen = key
        rows.push({ "heading": root.headingFor(key), "event": null })
      }
      rows.push({ "heading": "", "event": event })
    }
    return rows
  }

  function headingFor(key) {
    if (key === root.todayKey) return "Today"
    var parts = key.split("-")
    if (parts.length !== 3) return key
    var when = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    var tomorrow = new Date(root.now.getFullYear(), root.now.getMonth(),
                            root.now.getDate() + 1)
    if (key === root.dayKey(tomorrow)) return "Tomorrow"
    return root.weekdayNames[(when.getDay() + 6) % 7] + " " + when.getDate()
           + " " + root.monthNames[when.getMonth()]
  }

  // ------------------------------------------------------------------ data

  function reload() {
    if (root.loading || root.cliPath.indexOf("bin/olook") === -1) return
    var from = root.gridStart()
    var to = new Date(from.getFullYear(), from.getMonth(), from.getDate() + 42)
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

  // Keeps the label honest across a minute and the highlight across midnight.
  SystemClock {
    id: systemClock
    precision: SystemClock.Minutes
    onDateChanged: root.now = date
  }

  Timer {
    running: true
    repeat: true
    triggeredOnStart: true
    interval: root.refreshSeconds * 1000
    onTriggered: root.reload()
  }

  onOpenedChanged: if (root.opened) {
    root.now = new Date()
    root.reload()
  }

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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.labelText
    labelVisible: true
    hasVisualContent: text !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) root.reload()
      else if (buttonCode === Qt.MiddleButton) root.openCalendar()
      else root.toggle()
    }
  }

  // ----------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(
      headerColumn.implicitHeight + gridColumn.implicitHeight
      + listColumn.implicitHeight + Style.space(38), Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onMoveRequested: function (dx, dy) { if (dx !== 0) root.step(dx) }
      onTextKey: function (text) {
        if (text === "r" || text === "R") root.reload()
        else if (text === "t" || text === "T") root.goToday()
        else if (text === "o" || text === "O") root.openCalendar()
      }

      Column {
        id: headerColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        Item {
          width: parent.width
          height: Style.space(24)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.monthNames[root.viewMonth] + " " + root.viewYear
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            StepChip { glyph: "󰅁"; onTriggered: root.step(-1) }
            StepChip { glyph: "󰃰"; onTriggered: root.goToday() }
            StepChip { glyph: "󰅂"; onTriggered: root.step(1) }
          }
        }

        PanelSeparator { foreground: root.foreground }
      }

      // ------------------------------------------------------- month grid
      Column {
        id: gridColumn
        anchors.top: headerColumn.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(2)

        Row {
          width: parent.width

          Repeater {
            model: root.weekdayNames

            Item {
              required property string modelData
              width: gridColumn.width / 7
              height: Style.space(16)

              Text {
                anchors.centerIn: parent
                text: parent.modelData.charAt(0)
                color: root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Grid {
          width: parent.width
          columns: 7

          Repeater {
            model: root.monthCells

            Item {
              id: cell
              required property var modelData
              width: gridColumn.width / 7
              height: Style.space(26)

              readonly property bool isToday: modelData.key === root.todayKey
              readonly property bool isPicked: modelData.key === root.selectedDay
              readonly property int count: root.eventsOn(modelData.key).length

              Rectangle {
                anchors.centerIn: parent
                width: Style.space(22)
                height: Style.space(20)
                radius: Style.cornerRadius
                color: cell.isToday ? Color.accent
                  : (cell.isPicked ? Util.alpha(root.foreground, 0.16)
                                   : (cellHover.containsMouse
                                      ? Util.alpha(root.foreground, 0.08)
                                      : "transparent"))

                Text {
                  anchors.centerIn: parent
                  text: String(cell.modelData.number)
                  color: cell.isToday ? Color.popups.background
                    : (cell.modelData.outside ? root.faint : root.foreground)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: cell.isToday
                }
              }

              // One dot means something is on; the day itself says what.
              Rectangle {
                visible: cell.count > 0 && !cell.isToday
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(1)
                width: Style.space(4)
                height: width
                radius: width / 2
                color: cell.modelData.outside ? root.faint : Color.accent
              }

              MouseArea {
                id: cellHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedDay =
                  (root.selectedDay === cell.modelData.key) ? "" : cell.modelData.key
              }
            }
          }
        }
      }

      // ---------------------------------------------------------- the list
      Column {
        id: listColumn
        anchors.top: gridColumn.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Style.space(6)

        PanelSeparator { foreground: root.foreground }

        Text {
          width: parent.width
          visible: root.trouble !== ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: root.trouble
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.trouble === "" && root.agendaRows.length === 0
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: root.loading ? "Reading the calendar…"
            : (root.selectedDay !== "" ? "Nothing on that day"
                                       : "Nothing coming up")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
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
            spacing: Style.space(3)

            Repeater {
              model: root.agendaRows

              Item {
                id: agendaRow
                required property var modelData
                width: agendaColumn.width
                implicitHeight: Style.space(19)
                height: implicitHeight

                Rectangle {
                  anchors.fill: parent
                  anchors.margins: -Style.space(1)
                  radius: Style.cornerRadius
                  visible: !!agendaRow.modelData.event && rowHover.containsMouse
                  color: Util.alpha(root.foreground, 0.08)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: agendaRow.modelData.heading !== ""
                  text: agendaRow.modelData.heading
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Row {
                  visible: !!agendaRow.modelData.event
                  anchors.fill: parent
                  spacing: Style.space(7)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(3)
                    height: Style.space(13)
                    radius: Style.space(2)
                    color: (agendaRow.modelData.event
                            && agendaRow.modelData.event.colour)
                      ? agendaRow.modelData.event.colour : root.foreground
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(42)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: agendaRow.modelData.event
                      ? (agendaRow.modelData.event.allDay
                         ? "all day" : root.clockOf(agendaRow.modelData.event))
                      : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(59)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: agendaRow.modelData.event
                      ? (agendaRow.modelData.event.summary || "(no title)") : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
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

  component StepChip: Rectangle {
    id: chip
    property string glyph: ""
    signal triggered()

    width: Style.space(20)
    height: Style.space(20)
    radius: Style.cornerRadius
    color: chipHover.containsMouse ? Util.alpha(root.foreground, 0.10) : "transparent"

    Text {
      anchors.centerIn: parent
      text: chip.glyph
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: chipHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.triggered()
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
