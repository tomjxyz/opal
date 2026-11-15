// The tail of data/opal.log, for troubleshooting on the phone.
import bb.cascades 1.4

Container {
    id: logScreen
    signal toast(string text)
    function reload() { logText.text = opal.logTail(300); }

    horizontalAlignment: HorizontalAlignment.Fill
    verticalAlignment: VerticalAlignment.Fill
    bottomPadding: ui.du(12)

    Container {
        leftPadding: ui.du(3)
        rightPadding: ui.du(3)
        topPadding: ui.du(1.5)
        layout: StackLayout {
            orientation: LayoutOrientation.LeftToRight
        }
        Button {
            text: "Refresh"
            layoutProperties: StackLayoutProperties {
                spaceQuota: 1
            }
            onClicked: logScreen.reload()
        }
        Button {
            text: "Copy"
            layoutProperties: StackLayoutProperties {
                spaceQuota: 1
            }
            onClicked: {
                opal.copyText(opal.logTail(1000));
                logScreen.toast("Log copied");
            }
        }
        Button {
            text: "Clear"
            layoutProperties: StackLayoutProperties {
                spaceQuota: 1
            }
            onClicked: {
                opal.clearLog();
                logScreen.reload();
            }
        }
    }
    ScrollView {
        layoutProperties: StackLayoutProperties {
            spaceQuota: 1
        }
        TextArea {
            id: logText
            editable: false
            backgroundVisible: false
            textStyle.fontFamily: "monospace"
            textStyle.fontSize: FontSize.XSmall
            textStyle.color: Color.create("#c8e6c9")
        }
    }
}
