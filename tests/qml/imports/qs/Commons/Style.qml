pragma Singleton
import QtQuick
QtObject {
  property QtObject spacing: QtObject { property int controlPaddingX: 10; property int inputPaddingY: 7 }
  property QtObject font: QtObject { property string family: "sans"; property int body: 14 }
  property int cornerRadius: 4
  function selectionFillFor(a, b) { return "blue" }
  function controlFill() { return "white" }
  function space(n) { return n }
}
