// Text field with the rainbow rim while focused (light grey outline otherwise). The rim is four stretched strips
// (rim-*.png), so no nine-slice image is needed. Optional: a camera icon on the right,
// and an attached photo shown as a thumbnail on the left (tap it to remove).
// Sizes at 720 px: Home field ~87 px tall, compact (camera/follow-up) ~59 px.
import bb.cascades 1.4

Container {
    id: ask
    property alias text: field.text
    property alias hint: field.hintText
    property bool showCamera: false
    property bool compact: false
    property bool enabledInput: true
    property string attachment: ""        // local path of an attached photo, or ""
    signal submitted(string text)
    signal cameraTapped()
    signal attachmentRemoved()

    function focusField() { field.requestFocus(); }
    function isFocused() { return field.focused; }
    function clear() { field.text = ""; }

    horizontalAlignment: HorizontalAlignment.Fill
    layout: DockLayout {}
    background: Color.create("#1c1c1c")

    ImageView {
        imageSource: "asset:///rim-top.png"
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Top
        preferredHeight: 3
        preferredWidth: 1      // stretched by Fill; don't let the 512 px image size the field
        scalingMethod: ScalingMethod.Fill
        visible: field.focused
    }
    ImageView {
        imageSource: "asset:///rim-bottom.png"
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Bottom
        preferredHeight: 3
        preferredWidth: 1
        scalingMethod: ScalingMethod.Fill
        visible: field.focused
    }
    ImageView {
        imageSource: "asset:///rim-left.png"
        horizontalAlignment: HorizontalAlignment.Left
        verticalAlignment: VerticalAlignment.Fill
        preferredWidth: 3
        preferredHeight: 1     // stretched by Fill; the 128 px image height used to set the field's height
        scalingMethod: ScalingMethod.Fill
        visible: field.focused
    }
    ImageView {
        imageSource: "asset:///rim-right.png"
        horizontalAlignment: HorizontalAlignment.Right
        verticalAlignment: VerticalAlignment.Fill
        preferredWidth: 3
        preferredHeight: 1
        scalingMethod: ScalingMethod.Fill
        visible: field.focused
    }

    // Not focused: a plain light grey outline instead of the rainbow rim, so it's obvious which
    // field takes typing.
    Container {
        visible: !field.focused
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Top
        preferredWidth: 1
        preferredHeight: 2
        background: Color.create("#8c8c8c")
    }
    Container {
        visible: !field.focused
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Bottom
        preferredWidth: 1
        preferredHeight: 2
        background: Color.create("#8c8c8c")
    }
    Container {
        visible: !field.focused
        horizontalAlignment: HorizontalAlignment.Left
        verticalAlignment: VerticalAlignment.Fill
        preferredWidth: 2
        preferredHeight: 1
        background: Color.create("#8c8c8c")
    }
    Container {
        visible: !field.focused
        horizontalAlignment: HorizontalAlignment.Right
        verticalAlignment: VerticalAlignment.Fill
        preferredWidth: 2
        preferredHeight: 1
        background: Color.create("#8c8c8c")
    }

    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Center
        leftPadding: ui.du(1.2)
        rightPadding: ui.du(2.5)
        topPadding: 2
        bottomPadding: 2
        layout: StackLayout {
            orientation: LayoutOrientation.LeftToRight
        }
        Container {     // attached photo
            visible: ask.attachment != ""
            verticalAlignment: VerticalAlignment.Center
            leftMargin: ui.du(0.5)
            layout: DockLayout {}
            ImageView {
                imageSource: ask.attachment != "" ? "file://" + ask.attachment : ""
                preferredWidth: ui.du(5.5)
                preferredHeight: ui.du(5.5)
                scalingMethod: ScalingMethod.AspectFill
            }
            Label {     // small "×" badge
                text: "×"
                horizontalAlignment: HorizontalAlignment.Right
                verticalAlignment: VerticalAlignment.Top
                textStyle.color: Color.White
                textStyle.base: SystemDefaults.TextStyles.SmallText
                textStyle.fontWeight: FontWeight.Bold
            }
            gestureHandlers: TapHandler {
                onTapped: ask.attachmentRemoved()
            }
        }
        TextField {
            id: field
            layoutProperties: StackLayoutProperties {
                spaceQuota: 1
            }
            verticalAlignment: VerticalAlignment.Center
            // The TextField's own default height made every field far taller than intended
            // (~87 px on Home, ~59 px compact at 720 px), so pin it.
            preferredHeight: ask.compact ? ui.du(6.7) : ui.du(10.2)
            minHeight: ask.compact ? ui.du(6.7) : ui.du(10.2)
            maxHeight: ask.compact ? ui.du(6.7) : ui.du(10.2)
            backgroundVisible: false
            focusHighlightEnabled: false
            navigation.defaultHighlightEnabled: false   // the rainbow rim already marks the field
            clearButtonVisible: false
            enabled: ask.enabledInput
            textStyle.color: Color.White
            textStyle.base: SystemDefaults.TextStyles.TitleText
            textStyle.fontSize: FontSize.PercentageValue
            textStyle.fontSizeValue: 95
            input.submitKey: SubmitKey.Send
            input.onSubmitted: ask.submitted(field.text.trim())
        }
        ImageView {
            visible: ask.showCamera
            imageSource: "asset:///ic-camera.png"
            preferredWidth: ui.du(3.6)
            preferredHeight: ui.du(3.6)
            leftMargin: ui.du(1)
            verticalAlignment: VerticalAlignment.Center
            scalingMethod: ScalingMethod.AspectFit
            gestureHandlers: TapHandler {
                onTapped: ask.cameraTapped()
            }
        }
    }
}
