// List of saved chats (title + relative date). Used on Home ("Recent") and the Chats screen.
// Tap the dim × (or long-press an item) to delete it.
import bb.cascades 1.4

ListView {
    id: list
    property int limit: 0          // 0 = all
    property real itemWidth: 720   // list items size to their content unless told the width
    signal openChat(string id)
    signal deleteChat(string id)

    function load(entries) {
        chatModel.clear();
        var n = limit > 0 ? Math.min(limit, entries.length) : entries.length;
        for (var i = 0; i < n; i++) {
            var e = entries[i];
            chatModel.append({ type: "chat", id: e.id, title: e.title || "Untitled", when: fmtDate(e.updated), image: e.image || "" });
        }
    }
    function fmtDate(ms) {
        var d = new Date(ms);
        var now = new Date();
        var day = 24 * 3600 * 1000;
        var startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        if (ms >= startToday) {
            var h = d.getHours(), m = d.getMinutes();
            return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
        }
        if (ms >= startToday - day) return "Yesterday";
        if (ms >= startToday - 6 * day) return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()];
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        var s = d.getDate() + " " + months[d.getMonth()];
        if (d.getFullYear() != now.getFullYear()) s += " " + d.getFullYear();
        return s;
    }
    // A tap on the × must not also open a chat: after the delete the list reloads, so the same
    // tap's trigger could even land on the next row. Ignore opens just after a delete.
    property real deletedAt: 0
    function requestDelete(id) {
        deletedAt = new Date().getTime();
        list.deleteChat(id);
    }

    navigation.defaultHighlightEnabled: false
    dataModel: ArrayDataModel {
        id: chatModel
    }
    attachedObjects: [
        LayoutUpdateHandler {
            onLayoutFrameChanged: list.itemWidth = layoutFrame.width
        }
    ]
    function itemType(data, indexPath) { return "chat"; }

    listItemComponents: [
        ListItemComponent {
            type: "chat"
            Container {
                id: itemRoot
                preferredWidth: itemRoot.ListItem.view.itemWidth
                preferredHeight: ui.du(9)
                navigation.defaultHighlightEnabled: false     // purple instead of the system's blue box
                background: itemRoot.navigation.wantsHighlight ? Color.create("#6B52A8")
                          : (itemRoot.ListItem.active ? Color.create("#2a2a2a") : Color.Transparent)
                layout: DockLayout {}
                Container {
                    leftPadding: ui.du(4)
                    rightPadding: ui.du(9)      // room for the ×
                    verticalAlignment: VerticalAlignment.Center
                    Label {
                        text: ListItemData.title
                        bottomMargin: 0
                        textStyle.color: Color.White
                        textStyle.base: SystemDefaults.TextStyles.TitleText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: 92
                    }
                    Label {
                        text: ListItemData.when
                        topMargin: 0
                        textStyle.color: Color.create("#9a9a9a")
                        textStyle.base: SystemDefaults.TextStyles.SubtitleText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: 72
                    }
                }
                Container {     // dim grey ×: delete this chat
                    horizontalAlignment: HorizontalAlignment.Right
                    verticalAlignment: VerticalAlignment.Fill
                    preferredWidth: ui.du(9)
                    layout: DockLayout {}
                    ImageView {
                        imageSource: "asset:///ic-close-dim.png"
                        preferredWidth: ui.du(2.6)
                        preferredHeight: ui.du(2.6)
                        horizontalAlignment: HorizontalAlignment.Center
                        verticalAlignment: VerticalAlignment.Center
                    }
                    gestureHandlers: TapHandler {
                        onTapped: itemRoot.ListItem.view.requestDelete(ListItemData.id)
                    }
                }
                Container {     // full-width divider
                    horizontalAlignment: HorizontalAlignment.Fill
                    verticalAlignment: VerticalAlignment.Bottom
                    preferredHeight: 1
                    background: Color.create("#2c2c2c")
                }
                contextActions: [
                    ActionSet {
                        title: ListItemData.title
                        DeleteActionItem {
                            title: "Delete chat"
                            onTriggered: itemRoot.ListItem.view.requestDelete(ListItemData.id)
                        }
                    }
                ]
            }
        }
    ]

    onTriggered: {
        var d = dataModel.data(indexPath);
        if (!d || !d.id) return;
        if (new Date().getTime() - deletedAt < 600) return;
        list.openChat(d.id);
    }
}
