// The animated opal signature button: a dark base, six colour layers (soft blobs from different
// parts of the pattern, made by tools/make-assets.py) and the glyph on top. Each colour layer fades
// in and out on its own period, so colour flows in and out across the stone rather than pulsing
// all at once. Animations pause while the app is minimised.
import bb.cascades 1.4

Container {
    id: btn
    property string glyph: "camera"        // "camera" | "search"
    property bool pressed: false
    property bool keyArmed: false
    signal clicked()

    // Periods (ms) are deliberately unrelated so the layers drift out of step and never sync up.
    function startAll() {
        f0.play(); f1.play(); f2.play(); f3.play(); f4.play(); f5.play();
    }
    function stopAll() {
        f0.stop(); f1.stop(); f2.stop(); f3.stop(); f4.stop(); f5.stop();
    }
    onCreationCompleted: {
        startAll();
        opal.backgrounded.connect(btn.stopAll);
        opal.foregrounded.connect(btn.startAll);
    }

    preferredWidth: ui.du(12)
    preferredHeight: ui.du(12)
    layout: DockLayout {}
    focusPolicy: FocusPolicy.Key
    navigation.focusPolicy: NavigationFocusPolicy.Focusable
    navigation.defaultHighlightEnabled: false     // purple ring below instead of the blue box

    ImageView {
        imageSource: "asset:///opal-base.png"
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Fill
    }

    Container {     // the colour layers
        id: colours
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Fill
        layout: DockLayout {}
        ImageView {
            imageSource: "asset:///opal-layer-0.png"
            horizontalAlignment: HorizontalAlignment.Fill
            verticalAlignment: VerticalAlignment.Fill
            opacity: 0
            animations: [
                SequentialAnimation {
                    id: f0
                    repeatCount: AnimationRepeatCount.Forever
                    FadeTransition { fromOpacity: 0; toOpacity: 1; duration: 3100; easingCurve: StockCurve.SineInOut }
                    FadeTransition { fromOpacity: 1; toOpacity: 0; duration: 3100; easingCurve: StockCurve.SineInOut }
                }
            ]
        }
        ImageView {
            imageSource: "asset:///opal-layer-1.png"
            horizontalAlignment: HorizontalAlignment.Fill
            verticalAlignment: VerticalAlignment.Fill
            opacity: 1
            animations: [
                SequentialAnimation {
                    id: f1
                    repeatCount: AnimationRepeatCount.Forever
                    FadeTransition { fromOpacity: 1; toOpacity: 0; duration: 4300; easingCurve: StockCurve.SineInOut }
                    FadeTransition { fromOpacity: 0; toOpacity: 1; duration: 4300; easingCurve: StockCurve.SineInOut }
                }
            ]
        }
        ImageView {
            imageSource: "asset:///opal-layer-2.png"
            horizontalAlignment: HorizontalAlignment.Fill
            verticalAlignment: VerticalAlignment.Fill
            opacity: 0
            animations: [
                SequentialAnimation {
                    id: f2
                    repeatCount: AnimationRepeatCount.Forever
                    FadeTransition { fromOpacity: 0; toOpacity: 1; duration: 5200; easingCurve: StockCurve.SineInOut }
                    FadeTransition { fromOpacity: 1; toOpacity: 0; duration: 5200; easingCurve: StockCurve.SineInOut }
                }
            ]
        }
        ImageView {
            imageSource: "asset:///opal-layer-3.png"
            horizontalAlignment: HorizontalAlignment.Fill
            verticalAlignment: VerticalAlignment.Fill
            opacity: 1
            animations: [
                SequentialAnimation {
                    id: f3
                    repeatCount: AnimationRepeatCount.Forever
                    FadeTransition { fromOpacity: 1; toOpacity: 0; duration: 3700; easingCurve: StockCurve.SineInOut }
                    FadeTransition { fromOpacity: 0; toOpacity: 1; duration: 3700; easingCurve: StockCurve.SineInOut }
                }
            ]
        }
        ImageView {
            imageSource: "asset:///opal-layer-4.png"
            horizontalAlignment: HorizontalAlignment.Fill
            verticalAlignment: VerticalAlignment.Fill
            opacity: 0
            animations: [
                SequentialAnimation {
                    id: f4
                    repeatCount: AnimationRepeatCount.Forever
                    FadeTransition { fromOpacity: 0; toOpacity: 1; duration: 5900; easingCurve: StockCurve.SineInOut }
                    FadeTransition { fromOpacity: 1; toOpacity: 0; duration: 5900; easingCurve: StockCurve.SineInOut }
                }
            ]
        }
        ImageView {
            imageSource: "asset:///opal-layer-5.png"
            horizontalAlignment: HorizontalAlignment.Fill
            verticalAlignment: VerticalAlignment.Fill
            opacity: 1
            animations: [
                SequentialAnimation {
                    id: f5
                    repeatCount: AnimationRepeatCount.Forever
                    FadeTransition { fromOpacity: 1; toOpacity: 0; duration: 4700; easingCurve: StockCurve.SineInOut }
                    FadeTransition { fromOpacity: 0; toOpacity: 1; duration: 4700; easingCurve: StockCurve.SineInOut }
                }
            ]
        }
    }

    ImageView {     // glyph stays still on top
        imageSource: btn.glyph == "search" ? "asset:///opal-glyph-search.png" : "asset:///opal-glyph-camera.png"
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Fill
    }
    ImageView {     // pressed: dim the whole stone (same circle as the base)
        visible: btn.pressed
        opacity: 0.45
        imageSource: "asset:///opal-press.png"
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Fill
    }
    ImageView {     // purple trackpad focus ring
        visible: btn.navigation.wantsHighlight || btn.focused
        imageSource: "asset:///opal-focus-ring.png"
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Fill
    }

    onTouch: {
        if (event.isDown()) btn.pressed = true;
        else if (event.isUp()) {
            var inside = event.localX >= 0 && event.localY >= 0 && event.localX <= btn.preferredWidth && event.localY <= btn.preferredHeight;
            btn.pressed = false;
            if (inside) btn.clicked();
        } else if (event.isCancel()) btn.pressed = false;
    }
    keyListeners: KeyListener {
        onKeyPressed: btn.keyArmed = (event.unicode == "\r" || event.unicode == "\n" || event.key == 13)
        onKeyReleased: {
            var enter = event.unicode == "\r" || event.unicode == "\n" || event.key == 13;
            if (enter && btn.keyArmed) btn.clicked();
            btn.keyArmed = false;
        }
    }
    onFocusedChanged: if (!focused) btn.keyArmed = false
}
