// Right-hand overflow panel, rows from the top. Rows depend on the screen.
// Opened by ⋮ and the Menu key; closed by Back, a tap outside, or choosing a row.
import bb.cascades 1.4

Container {
    id: panel
    property bool open: false
    property string screen: "home"
    property real screenWidth: 720
    signal activated(string name)
    signal closeRequested()
    property bool shown: false     // stays true until the closing slide has finished

    // Explicit slide animations: an implicit one doesn't run when the panel becomes visible
    // in the same frame as the translation change (it only animated on close).
    // Move trackpad focus into the panel so it navigates the rows, not the page behind.
    function focusFirst() { rowNew.requestFocus(); }

    onOpenChanged: {
        if (open) {
            slideOut.stop();
            sheet.translationX = screenWidth;
            shown = true;
            slideIn.play();
            focusFirst();
            opal.callLater(120, "focusPanel");
        } else if (shown) {
            slideIn.stop();
            slideOut.play();
        }
    }

    horizontalAlignment: HorizontalAlignment.Fill
    verticalAlignment: VerticalAlignment.Fill
    layout: DockLayout {}
    visible: shown

    Container {     // dim the page; tap to close
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Fill
        background: Color.create("#99000000")
        opacity: panel.open ? 1 : 0
        gestureHandlers: TapHandler {
            onTapped: panel.closeRequested()
        }
    }
    Container {
        id: sheet
        horizontalAlignment: HorizontalAlignment.Right
        verticalAlignment: VerticalAlignment.Fill
        preferredWidth: panel.screenWidth * 0.62
        background: Color.Black
        translationX: 720
        layout: DockLayout {}
        animations: [
            TranslateTransition {
                id: slideIn
                toX: 0
                duration: 180
                easingCurve: StockCurve.QuadraticOut
            },
            TranslateTransition {
                id: slideOut
                toX: panel.screenWidth
                duration: 150
                onEnded: panel.shown = false
            }
        ]

        Container {
            horizontalAlignment: HorizontalAlignment.Fill
            verticalAlignment: VerticalAlignment.Top
            PanelRow {
                id: rowNew
                navigation.upAllowed: false     // don't let focus escape to the page behind
                name: "new"
                icon: "asset:///ic-plus.png"
                title: "New chat"
                letter: "N"
                onActivated: panel.activated(name)
            }
            PanelRow {
                name: "camera"
                visible: panel.screen != "camera"
                icon: "asset:///ic-camera.png"
                title: "Search with camera"
                letter: "K"
                onActivated: panel.activated(name)
            }
            PanelRow {
                name: "copy"
                visible: panel.screen == "answer"
                icon: "asset:///ic-copy.png"
                title: "Copy answer"
                letter: "Y"
                onActivated: panel.activated(name)
            }
            PanelRow {
                name: "sources"
                visible: panel.screen == "answer"
                icon: "asset:///ic-translate.png"
                title: "Open sources"
                letter: "O"
                onActivated: panel.activated(name)
            }
            PanelRow {
                name: "export"
                visible: panel.screen == "answer"
                icon: "asset:///ic-export.png"
                title: "Export chat"
                letter: "E"
                onActivated: panel.activated(name)
            }
            PanelRow {
                name: "log"
                visible: panel.screen == "settings"
                icon: "asset:///ic-log.png"
                title: "View log"
                letter: "L"
                onActivated: panel.activated(name)
            }
            PanelRow {
                name: "settings"
                visible: panel.screen != "settings"
                icon: "asset:///ic-settings.png"
                title: "Settings"
                letter: "T"
                onActivated: panel.activated(name)
            }
        }
    }
}
