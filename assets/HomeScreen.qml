// Home: logo + title, the ask field, recent chats.
// Measurements at 720 px: header 87 px with a full-width divider, field 32 px from
// the sides and ~87 px tall, "RECENT" rule, list rows ~72 px.
import bb.cascades 1.4

Container {
    id: home
    signal ask(string text)
    signal cameraTapped()
    signal openChat(string id)
    signal deleteChat(string id)

    function reload() {
        var entries = history.list();
        recent.load(entries);
        empty.visible = entries.length == 0;
    }
    function focusAsk() { askField.focusField(); }
    function clearAsk() { askField.clear(); }

    horizontalAlignment: HorizontalAlignment.Fill
    verticalAlignment: VerticalAlignment.Fill
    bottomPadding: ui.du(12)

    // header
    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        preferredHeight: ui.du(10.9)
        leftPadding: ui.du(4)
        layout: StackLayout {
            orientation: LayoutOrientation.LeftToRight
        }
        ImageView {
            imageSource: "asset:///logo.png"
            preferredWidth: ui.du(4.5)
            preferredHeight: ui.du(4.5)
            verticalAlignment: VerticalAlignment.Center
            scalingMethod: ScalingMethod.AspectFit
        }
        Label {
            text: "Opal"
            leftMargin: ui.du(2)
            verticalAlignment: VerticalAlignment.Center
            textStyle.color: Color.White
            textStyle.base: SystemDefaults.TextStyles.BigText
            textStyle.fontSize: FontSize.PercentageValue
            textStyle.fontSizeValue: 108
        }
    }
    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        preferredHeight: 1
        background: Color.create("#2c2c2c")
    }

    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        leftPadding: ui.du(4)
        rightPadding: ui.du(4)
        topPadding: ui.du(2.6)
        AskField {
            id: askField
            hint: "Ask anything…"
            onSubmitted: if (text != "") home.ask(text)
        }
    }

    // "RECENT ———"
    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        leftPadding: ui.du(4)
        rightPadding: ui.du(4)
        topPadding: ui.du(3)
        bottomPadding: ui.du(0.5)
        layout: StackLayout {
            orientation: LayoutOrientation.LeftToRight
        }
        Label {
            text: "RECENT"
            verticalAlignment: VerticalAlignment.Center
            textStyle.color: Color.create("#9a9a9a")
            textStyle.base: SystemDefaults.TextStyles.SmallText
            textStyle.fontWeight: FontWeight.Bold
        }
        Container {
            layoutProperties: StackLayoutProperties {
                spaceQuota: 1
            }
            leftMargin: ui.du(2)
            verticalAlignment: VerticalAlignment.Center
            preferredHeight: 1
            background: Color.create("#3a3a3a")
        }
    }

    Container {
        id: empty
        visible: false
        leftPadding: ui.du(4)
        rightPadding: ui.du(4)
        topPadding: ui.du(2)
        Label {
            text: "Your questions will appear here. Type one above, or tap the opal button to search with the camera."
            multiline: true
            textStyle.color: Color.create("#7a7a7a")
            textStyle.base: SystemDefaults.TextStyles.BodyText
            textStyle.fontSize: FontSize.PercentageValue
            textStyle.fontSizeValue: 80
        }
    }
    ChatList {
        id: recent
        layoutProperties: StackLayoutProperties {
            spaceQuota: 1
        }
        onOpenChat: home.openChat(id)
        onDeleteChat: home.deleteChat(id)
    }
}
