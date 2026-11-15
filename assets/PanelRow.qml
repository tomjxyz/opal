// One row of the overflow panel: icon, title, shortcut letter.
import bb.cascades 1.4

Container {
    id: row
    property string name
    property string icon
    property string title
    property string letter
    signal activated(string name)
    // Act on Enter/trackpad-click only if the PRESS happened here too: after a screen change the
    // key's release can land on a newly focused item.
    property bool keyArmed: false

    horizontalAlignment: HorizontalAlignment.Fill
    preferredHeight: ui.du(10)
    focusPolicy: FocusPolicy.Key
    navigation.focusPolicy: NavigationFocusPolicy.Focusable
    navigation.defaultHighlightEnabled: false     // the purple row is the highlight
    navigation.leftAllowed: false                 // the page behind is to the left
    background: focused ? Color.create("#6B52A8") : Color.Black
    layout: DockLayout {}

    Container {
        verticalAlignment: VerticalAlignment.Center
        leftPadding: ui.du(4)
        layout: StackLayout {
            orientation: LayoutOrientation.LeftToRight
        }
        ImageView {
            imageSource: row.icon
            preferredWidth: ui.du(4)
            preferredHeight: ui.du(4)
            verticalAlignment: VerticalAlignment.Center
            scalingMethod: ScalingMethod.AspectFit
        }
        Label {
            text: row.title
            leftMargin: ui.du(4)
            verticalAlignment: VerticalAlignment.Center
            textStyle.color: Color.White
            textStyle.base: SystemDefaults.TextStyles.TitleText
            textStyle.fontSize: FontSize.PercentageValue
            textStyle.fontSizeValue: 95
        }
    }
    Container {     // shortcut letter, top-right (DockLayout ignores margins, so pad a wrapper)
        horizontalAlignment: HorizontalAlignment.Right
        verticalAlignment: VerticalAlignment.Top
        rightPadding: ui.du(2.8)
        topPadding: ui.du(1)
        Label {
            text: row.letter
            textStyle.color: Color.create("#b0b0b0")
            textStyle.base: SystemDefaults.TextStyles.SmallText
        }
    }
    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Top
        preferredHeight: 1
        background: Color.create("#333333")
    }

    gestureHandlers: TapHandler {
        onTapped: row.activated(row.name)
    }
    keyListeners: KeyListener {
        onKeyPressed: row.keyArmed = (event.unicode == "\r" || event.unicode == "\n" || event.key == 13)
        onKeyReleased: {
            var enter = event.unicode == "\r" || event.unicode == "\n" || event.key == 13;
            if (enter && row.keyArmed) row.activated(row.name);
            row.keyArmed = false;
        }
    }
    onFocusedChanged: if (!focused) row.keyArmed = false
}
