import QtQuick
import QtQuick.Layouts
import com.wordloom.app

// The icon for a binder item kind / section root, drawn from bundled SVGs
// (emoji depend on the system's fonts and don't render everywhere).
Image {
    property string kind: ""
    property string role: ""
    property int size: 16
    source: Theme.kindIcon(kind, role)
    sourceSize.width: size
    sourceSize.height: size
    width: size
    height: size
    Layout.preferredWidth: size
    Layout.preferredHeight: size
    fillMode: Image.PreserveAspectFit
    smooth: true
}
