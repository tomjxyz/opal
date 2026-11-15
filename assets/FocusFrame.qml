// Purple trackpad-focus frame for system controls (Button, TextField, DropDown, ToggleButton,
// CheckBox) whose own highlight is blue and can't be recoloured. Put the control inside and
// point `target` at it; the control should set navigation.defaultHighlightEnabled: false.
import bb.cascades 1.4

Container {
    property variant target
    horizontalAlignment: HorizontalAlignment.Fill
    leftPadding: 3
    rightPadding: 3
    topPadding: 3
    bottomPadding: 3
    background: (target && target.navigation.wantsHighlight) ? Color.create("#6B52A8") : Color.Transparent
}
