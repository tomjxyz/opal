// Custom bottom bar (the stock action bar can't show an image in the signature button).
// Items sit at fixed horizontal positions (fractions of the width), the opal button
// in the middle sticks up into the content. Set a slot's name to "" to leave it empty.
import bb.cascades 1.4

Container {
    id: bar
    property real barWidth: 720
    property string s1Name
    property string s1Icon
    property string s1Label
    property string s2Name
    property string s2Icon
    property string s2Label
    property string s3Name
    property string s3Icon
    property string s3Label
    property string s4Name
    property string s4Icon
    property string s4Label
    property string centreName: "camera"
    property string centreGlyph: "camera"     // "camera" | "search"
    property string centreLabel: "Camera"
    signal activated(string name)

    // item centres at 1440 px wide: 96, 444, 720, 996, 1344
    function slotX(fraction) { return barWidth * fraction - ui.du(7.5); }

    horizontalAlignment: HorizontalAlignment.Fill
    verticalAlignment: VerticalAlignment.Bottom
    preferredHeight: ui.du(16)
    overlapTouchPolicy: OverlapTouchPolicy.Allow
    layout: DockLayout {}

    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Bottom
        preferredHeight: ui.du(12)
        background: Color.create("#262626")
        layout: AbsoluteLayout {}

        BarItem {
            id: b1
            navigation.right: b2.enabled ? b2 : opalButton
            name: bar.s1Name
            icon: bar.s1Icon
            label: bar.s1Label
            enabled: bar.s1Name != ""
            opacity: bar.s1Name != "" ? 1 : 0
            layoutProperties: AbsoluteLayoutProperties {
                positionX: bar.slotX(0.0667)
            }
            onActivated: bar.activated(name)
        }
        BarItem {
            id: b2
            navigation.left: b1
            navigation.right: opalButton
            name: bar.s2Name
            icon: bar.s2Icon
            label: bar.s2Label
            enabled: bar.s2Name != ""
            opacity: bar.s2Name != "" ? 1 : 0
            layoutProperties: AbsoluteLayoutProperties {
                positionX: bar.slotX(0.3083)
            }
            onActivated: bar.activated(name)
        }
        Container {     // the opal button's label, centred under it
            preferredWidth: ui.du(15)
            topPadding: ui.du(7.6)
            layoutProperties: AbsoluteLayoutProperties {
                positionX: bar.slotX(0.5)
            }
            Label {
                text: bar.centreLabel
                horizontalAlignment: HorizontalAlignment.Center
                textStyle.color: Color.create("#d8d8d8")
                textStyle.base: SystemDefaults.TextStyles.SmallText
            }
        }
        BarItem {
            id: b3
            navigation.left: opalButton
            navigation.right: b4
            name: bar.s3Name
            icon: bar.s3Icon
            label: bar.s3Label
            enabled: bar.s3Name != ""
            opacity: bar.s3Name != "" ? 1 : 0
            layoutProperties: AbsoluteLayoutProperties {
                positionX: bar.slotX(0.6917)
            }
            onActivated: bar.activated(name)
        }
        BarItem {
            id: b4
            navigation.left: b3.enabled ? b3 : opalButton
            name: bar.s4Name
            icon: bar.s4Icon
            label: bar.s4Label
            enabled: bar.s4Name != ""
            opacity: bar.s4Name != "" ? 1 : 0
            layoutProperties: AbsoluteLayoutProperties {
                positionX: bar.slotX(0.9333)
            }
            onActivated: bar.activated(name)
        }
    }

    OpalButton {
        id: opalButton
        horizontalAlignment: HorizontalAlignment.Center
        verticalAlignment: VerticalAlignment.Top
        glyph: bar.centreGlyph
        // Explicit trackpad links: the default navigation can't find neighbours in an AbsoluteLayout.
        navigation.left: b2.enabled ? b2 : b1
        navigation.right: b3.enabled ? b3 : b4
        onClicked: bar.activated(bar.centreName)
    }
}
