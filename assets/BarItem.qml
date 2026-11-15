// One item in the bottom bar: icon + optional label, positioned to match the design
// (720 px wide: icons ~36 px with the icon centre 33 px and the label centre 74 px below
// the bar's top edge; label-less icons ~30 px, centred). Tap or trackpad click activates it.
import bb.cascades 1.4

Container {
    id: item
    property string name
    property string icon
    property string label
    signal activated(string name)
    // Act on Enter/trackpad-click only if the PRESS happened here too: after a screen change the
    // key's release can land on a newly focused item.
    property bool keyArmed: false

    preferredWidth: ui.du(15)
    preferredHeight: ui.du(12)
    layout: DockLayout {}
    focusPolicy: FocusPolicy.Key
    navigation.focusPolicy: NavigationFocusPolicy.Focusable
    navigation.defaultHighlightEnabled: false       // purple instead of the system's blue box
    background: (navigation.wantsHighlight || focused) ? Color.create("#6B52A8") : Color.Transparent

    Container {
        horizontalAlignment: HorizontalAlignment.Center
        topPadding: item.label == "" ? ui.du(4.1) : ui.du(1.9)
        ImageView {
            imageSource: item.icon
            preferredWidth: item.label == "" ? ui.du(3.8) : ui.du(4.5)
            preferredHeight: item.label == "" ? ui.du(3.8) : ui.du(4.5)
            scalingMethod: ScalingMethod.AspectFit
        }
    }
    Container {
        visible: item.label != ""
        horizontalAlignment: HorizontalAlignment.Center
        topPadding: ui.du(7.6)
        Label {
            text: item.label
            textStyle.color: Color.create("#d8d8d8")
            textStyle.base: SystemDefaults.TextStyles.SmallText
        }
    }

    gestureHandlers: TapHandler {
        onTapped: if (item.enabled) item.activated(item.name)
    }
    keyListeners: KeyListener {
        onKeyPressed: item.keyArmed = (event.unicode == "\r" || event.unicode == "\n" || event.key == 13)
        onKeyReleased: {
            var enter = event.unicode == "\r" || event.unicode == "\n" || event.key == 13;
            if (enter && item.keyArmed && item.enabled) item.activated(item.name);
            item.keyArmed = false;
        }
    }
    onFocusedChanged: if (!focused) item.keyArmed = false
}
