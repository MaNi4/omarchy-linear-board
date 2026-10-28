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
Label {
  color: Util.alpha(root.fg, 0.6)
  font.pixelSize: Style.font.caption
  font.capitalization: Font.AllUppercase
  font.letterSpacing: 1
}
