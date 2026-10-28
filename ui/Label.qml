import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Part of the Linear board (mani4.linear-board). Like every file in ui/,
// it is created inside Board.qml and uses its state and functions through
// the id `root` (and the board's other ids, such as keyScope).
// ---- small building blocks -----------------------------------------------------------------
Text {
  textFormat: Text.PlainText
  color: root.fg
  font.family: root.font
  font.pixelSize: Style.font.body
  elide: Text.ElideRight
}
