// Camera search.
//   Search mode (default): the opal button / Space / Enter captures; the whole photo is scaled
//     down on a worker thread (images.process) and ATTACHED to the field as a thumbnail; type a
//     prompt (optional) and press again to ask.
//   Translate mode (the bar's globe button, purple when on): no text field; capturing goes
//     straight to the answer with a translate prompt.
// Flash is off by default; tapping its icon arms it (purple) for the next photo only.
// Tapping the picture refocuses there (one autofocus cycle; continuous autofocus resumes after the
// photo). The viewfinder shows the 4:3 photo letterboxed: on the Classic it fills y = 90..630.
import bb.cascades 1.4
import bb.cascades.multimedia 1.0
import bb.cascades.pickers 1.0

Container {
    id: cam
    property bool translate: false
    property bool rear: true
    property bool opened: false
    property bool reopenAfterClose: false
    property bool wantOpen: false
    property bool closing: false            // close() requested, cameraClosed not yet received
    property bool capturing: false
    property string pendingKind: ""         // search | translate, while capturing/processing
    property string attached: ""            // processed photo waiting for a prompt (search mode)
    property bool flashOn: false            // armed for the next capture only
    property real viewW: 720
    property real viewH: 720
    property real photoW: viewW / viewH < 4 / 3 ? viewW : viewH * 4 / 3
    property real photoH: photoW * 3 / 4
    property real photoLeft: (viewW - photoW) / 2
    property real photoTop: (viewH - photoH) / 2
    property real focusX: 0
    property real focusY: 0
    property bool focusShown: false
    property bool focusLocked: false
    property int focusSerial: 0
    signal submit(string prompt, string label, string image)
    signal toast(string text)

    // ---------------------------------------------------------------- camera control
    function open() {
        wantOpen = true;
        if (closing) {                      // still shutting down: reopen once it has closed
            reopenAfterClose = true;
            return;
        }
        if (opened) return;
        opal.log("camera: open " + (rear ? "rear" : "front"));
        camera.open(rear ? CameraUnit.Rear : CameraUnit.Front);
    }
    function close() {
        wantOpen = false;
        setFlash(false);
        if (opened && !closing) {
            opal.log("camera: close");
            closing = true;
            camera.close();
        }
    }
    function flip() {
        rear = !rear;
        if (opened && !closing) {
            reopenAfterClose = true;
            closing = true;
            camera.close();
        }
    }
    function setFlash(on) {
        flashOn = on;
        if (opened) images.setFlash(camera, on ? 1 : 0);   // CameraFlashMode: 0 Off, 1 On
    }
    function toggleTranslate() {
        translate = !translate;
        if (translate) attached = "";       // translate mode has no attachment step
        else askField.focusField();
        cam.toast(translate ? "Translate: take a photo of the text" : "Search");
    }
    function capture(kind) {
        if (capturing || images.busy) return;
        if (!opened) {
            cam.toast("Camera isn't ready yet");
            return;
        }
        pendingKind = kind;
        capturing = true;
        opal.log("camera: capture (" + kind + (flashOn ? ", flash" : "") + ")");
        camera.capturePhoto();
    }
    function tapFocus(x, y) {
        if (!opened || capturing) return;
        var fx = (x - photoLeft) / photoW, fy = (y - photoTop) / photoH;
        if (fx < 0 || fx > 1 || fy < 0 || fy > 1) return;    // tapped the black letterbox bands
        focusX = x;
        focusY = y;
        focusLocked = false;
        focusShown = true;
        focusSerial = focusSerial + 1;
        images.focusAt(camera, fx, fy);
        opal.callLater(2000, "hideFocus:" + focusSerial);
    }
    function pickPhoto() {
        pendingKind = translate ? "translate" : "search";
        picker.open();
    }
    // Opal button / Space / Enter.
    function primary() {
        if (translate) capture("translate");
        else if (attached != "") send();
        else capture("search");
    }
    function send() {
        if (attached == "") return;
        var typed = askField.text.trim();
        var img = attached;
        attached = "";
        askField.clear();
        cam.submit(promptFor("search", typed), labelFor("search", typed), img);
    }
    function detach() {
        attached = "";
    }

    // ---------------------------------------------------------------- prompts
    function promptFor(kind, typed) {
        if (kind == "translate")
            return "Translate the text in this photo into English. Give the original text first, then the translation.";
        return typed ? typed : "What is this? Identify it and tell me the most useful things to know about it.";
    }
    function labelFor(kind, typed) {
        if (kind == "translate") return "Translate this";
        return typed ? typed : "What is this?";
    }

    onCreationCompleted: {
        images.processed.connect(function(path) {
            if (!cam.pendingKind) return;
            var kind = cam.pendingKind;
            cam.pendingKind = "";
            if (kind == "translate") {
                cam.submit(cam.promptFor("translate", ""), cam.labelFor("translate", ""), path);
            } else {
                cam.attached = path;
                askField.focusField();
            }
        });
        opal.later.connect(function(tag) {
            if (tag == "hideFocus:" + cam.focusSerial) cam.focusShown = false;
        });
        images.processFailed.connect(function(message) {
            cam.pendingKind = "";
            cam.toast(message);
        });
    }

    horizontalAlignment: HorizontalAlignment.Fill
    verticalAlignment: VerticalAlignment.Fill
    layout: DockLayout {}
    background: Color.Black
    attachedObjects: [
        LayoutUpdateHandler {
            onLayoutFrameChanged: {
                cam.viewW = layoutFrame.width;
                cam.viewH = layoutFrame.height;
            }
        },
        FilePicker {
            id: picker
            type: FileType.Picture
            title: "Choose a photo"
            onFileSelected: {
                if (selectedFiles.length == 0) return;
                opal.log("gallery: picked " + selectedFiles[0]);
                images.process(selectedFiles[0], 0, 0, 1, 1, 0);
            }
            onCanceled: cam.pendingKind = ""
        }
    ]

    Camera {
        id: camera
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Fill
        onCameraOpened: {
            cam.opened = true;
            opal.log("camera: opened, starting viewfinder");
            images.setFlash(camera, cam.flashOn ? 1 : 0);
            images.continuousFocus(camera);
            camera.startViewfinder();
            if (!cam.wantOpen) cam.close();
        }
        onCameraOpenFailed: {
            opal.log("camera: OPEN FAILED, error " + error);
            cam.toast("Couldn't open the camera (error " + error + ")");
        }
        onViewfinderStarted: opal.log("camera: viewfinder started")
        onViewfinderStartFailed: opal.log("camera: VIEWFINDER FAILED, error " + error)
        onPhotoCaptureFailed: {
            cam.capturing = false;
            if (cam.flashOn) cam.setFlash(false);
            cam.pendingKind = "";
            opal.log("camera: CAPTURE FAILED, error " + error);
            cam.toast("Couldn't take the photo");
        }
        onPhotoSaveFailed: {
            cam.capturing = false;
            cam.pendingKind = "";
            opal.log("camera: SAVE FAILED, error " + error);
            cam.toast("Couldn't save the photo");
        }
        onPhotoSaved: {
            cam.capturing = false;
            cam.focusShown = false;
            images.continuousFocus(camera);           // a tap-focus lasts for one photo
            if (cam.flashOn) cam.setFlash(false);     // flash is for one photo only
            opal.log("camera: saved " + fileName + " (" + length + " bytes)");
            images.process(fileName, 0, 0, 1, 1, 0);     // whole photo, scaled to 1024 px
        }
        onFocusStateChanged: {
            // CameraFocusState: 0 None, 1 Waiting, 2 Searching, 3 Failed, 4 Locked
            if (cam.focusShown) opal.log("camera: focus state " + state);
            if (state == 4) cam.focusLocked = true;
        }
        onCameraClosed: {
            cam.opened = false;
            cam.closing = false;
            opal.log("camera: closed");
            if (cam.reopenAfterClose) {
                cam.reopenAfterClose = false;
                if (cam.wantOpen) camera.open(cam.rear ? CameraUnit.Rear : CameraUnit.Front);
            }
        }
    }

    // ---- tap catcher over the viewfinder (an overlay receives touches above the
    // native viewfinder on the Classic)
    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Fill
        background: Color.Transparent
        gestureHandlers: TapHandler {
            onTapped: cam.tapFocus(event.x, event.y)
        }
    }

    // ---- tap-to-focus square (white while focusing, purple once locked); taps pass through
    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Fill
        layout: AbsoluteLayout {}
        touchPropagationMode: TouchPropagationMode.None
        visible: cam.focusShown
        ImageView {
            imageSource: cam.focusLocked ? "asset:///focus-square-locked.png" : "asset:///focus-square.png"
            preferredWidth: ui.du(9)
            preferredHeight: ui.du(9)
            layoutProperties: AbsoluteLayoutProperties {
                positionX: cam.focusX - ui.du(4.5)
                positionY: cam.focusY - ui.du(4.5)
            }
        }
    }

    // ---- top row: flash · Opal · gallery
    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Top
        layout: DockLayout {}
        leftPadding: ui.du(3)
        rightPadding: ui.du(3)
        topPadding: ui.du(2)
        ImageView {
            imageSource: cam.flashOn ? "asset:///ic-flash-on.png" : "asset:///ic-flash.png"
            preferredWidth: ui.du(3.2)
            preferredHeight: ui.du(3.2)
            horizontalAlignment: HorizontalAlignment.Left
            gestureHandlers: TapHandler {
                onTapped: {
                    cam.setFlash(!cam.flashOn);
                    opal.log("camera: flash " + (cam.flashOn ? "armed" : "off"));
                }
            }
        }
        Label {
            text: "Opal"
            horizontalAlignment: HorizontalAlignment.Center
            textStyle.color: Color.White
            textStyle.base: SystemDefaults.TextStyles.TitleText
            textStyle.fontSize: FontSize.PercentageValue
            textStyle.fontSizeValue: 95
            textStyle.fontWeight: FontWeight.Bold
        }
        ImageView {
            imageSource: "asset:///ic-gallery.png"
            preferredWidth: ui.du(3.2)
            preferredHeight: ui.du(3.2)
            horizontalAlignment: HorizontalAlignment.Right
            gestureHandlers: TapHandler {
                onTapped: cam.pickPhoto()
            }
        }
    }

    // ---- ask field above the bar (search mode only)
    Container {
        visible: !cam.translate
        horizontalAlignment: HorizontalAlignment.Fill
        verticalAlignment: VerticalAlignment.Bottom
        bottomPadding: ui.du(16.9)
        leftPadding: ui.du(4)
        rightPadding: ui.du(4)
        AskField {
            id: askField
            compact: true
            attachment: cam.attached
            hint: cam.attached != "" ? "Ask about this photo\u2026" : "Ask about this\u2026"
            onSubmitted: cam.primary()
            onAttachmentRemoved: cam.detach()
        }
    }

    // ---- busy overlay while capturing / processing
    Container {
        visible: cam.capturing || images.busy
        horizontalAlignment: HorizontalAlignment.Center
        verticalAlignment: VerticalAlignment.Center
        background: Color.create("#b0000000")
        leftPadding: ui.du(3)
        rightPadding: ui.du(3)
        topPadding: ui.du(2)
        bottomPadding: ui.du(2)
        layout: StackLayout {
            orientation: LayoutOrientation.LeftToRight
        }
        ActivityIndicator {
            running: cam.capturing || images.busy
            preferredWidth: ui.du(5)
            preferredHeight: ui.du(5)
        }
        Label {
            text: cam.capturing ? "Taking photo…" : "Preparing…"
            leftMargin: ui.du(1.5)
            verticalAlignment: VerticalAlignment.Center
            textStyle.color: Color.White
        }
    }
}
