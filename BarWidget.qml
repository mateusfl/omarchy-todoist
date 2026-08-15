import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Strings.js" as Strings

// Bar pill for the Todoist plugin: the Todoist mark (assets/todoist-mark.svg,
// tinted to the bar's theme color via MultiEffect) plus the count of tasks
// due today or overdue, following the same host/panel split as the built-in
// clock/weather widgets. Left click opens the task list popup, middle click
// forces a refresh.
BarWidget {
  id: root
  moduleName: "todoist"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property bool hasToken: panelLoader.item ? panelLoader.item.hasToken === true : true
  readonly property int overdueCount: panelLoader.item ? (panelLoader.item.overdueCount || 0) : 0
  readonly property int dueCount: panelLoader.item ? (panelLoader.item.dueCount || 0) : 0
  readonly property string countLabel: dueCount > 99 ? "99+" : String(dueCount)
  readonly property string statusLabel: !hasToken ? "!" : (dueCount > 0 ? countLabel : "")
  readonly property string language: setting("language", Strings.DEFAULT_LANGUAGE)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.max(12, contentRow.implicitWidth + scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    active: root.hasToken && root.overdueCount > 0
    tooltipText: !root.hasToken
      ? Strings.t(root.language, "tooltipConfigureToken")
      : (root.dueCount > 0 ? root.dueCount + " " + Strings.t(root.language, "tooltipTasksDue") : Strings.t(root.language, "tooltipNoTasksToday"))
    horizontalMargin: 8.75

    readonly property color tintColor: active && useActiveColor ? activeColor : foreground

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Row {
      id: contentRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(4)

      Image {
        id: markImage
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.body
        height: Style.font.body
        source: Qt.resolvedUrl("assets/todoist-mark.svg")
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        visible: false
      }
      MultiEffect {
        anchors.verticalCenter: parent.verticalCenter
        width: markImage.width
        height: markImage.height
        source: markImage
        colorization: 1.0
        colorizationColor: button.tintColor
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.statusLabel !== ""
        text: root.statusLabel
        color: button.tintColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Item {
        width: button.width
        height: Style.bar.iconSlot

        Image {
          id: vMarkImage
          anchors.centerIn: parent
          width: Style.bar.iconSlot * 0.6
          height: width
          source: Qt.resolvedUrl("assets/todoist-mark.svg")
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          visible: false
        }
        MultiEffect {
          anchors.centerIn: parent
          width: vMarkImage.width
          height: vMarkImage.height
          source: vMarkImage
          colorization: 1.0
          colorizationColor: button.tintColor
        }
      }
    }
  }
}
