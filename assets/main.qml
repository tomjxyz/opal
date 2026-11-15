// Opal main page: one Page holding every screen, the custom bar and the overflow panel.
// Screens: home | answer | camera | settings | log.
// Context properties from C++: opal (settings/log/models), history, chat (streaming client).
import bb.cascades 1.4
import bb.system 1.2

Page {
    id: page
    actionBarVisibility: ChromeVisibility.Hidden

    property string screen: "home"
    property variant backStack: []
    property variant current: ({})        // the open chat (see src/history.h for the shape)
    property string liveText: ""
    property bool panelOpen: false
    property real screenW: 720

    // ---------------------------------------------------------------- navigation
    function go(name) {
        if (name == screen) return;
        if (screen == "settings") settingsScreen.save();
        var s = backStack;
        s.push(screen);
        backStack = s;
        show(name);
    }
    function back() {
        if (panelOpen) { panelOpen = false; return; }
        opal.log("ui: back from " + screen);
        if (screen == "answer") { goHome(); return; }      // answers always go back to Home
        if (screen == "settings") settingsScreen.save();
        var s = backStack;
        var prev = s.length ? s.pop() : "home";
        backStack = s;
        show(prev);
    }
    function show(name) {
        if (screen == "camera" && name != "camera") cameraScreen.close();
        screen = name;
        panelOpen = false;
        opal.log("ui: screen " + name);
        if (name == "camera") cameraScreen.open();
        if (name == "home") {
            homeScreen.reload();
            homeScreen.focusAsk();
            opal.callLater(250, "focusHome");    // again once the switch has settled (see opal.h)
        } else if (name == "settings") {
            settingsScreen.load();
        } else if (name == "log") {
            logScreen.reload();
        }
    }
    function goHome() {
        backStack = [];
        show("home");
    }

    // ---------------------------------------------------------------- chats
    function newChat() {
        if (chat.busy) chat.cancel();
        current = ({});
        homeScreen.clearAsk();
        goHome();
    }
    function openChat(id) {
        // Still answering this chat (you went back mid-answer): return to the live view.
        if (chat.busy && current.id == id) {
            go("answer");
            focusAnswerSoon();
            return;
        }
        var c = history.load(id);
        if (!c || !c.id) {
            toast.body = "Couldn't open that chat";
            toast.show();
            return;
        }
        current = c;
        answerScreen.showChat(c);
        go("answer");
        focusAnswerSoon();
    }
    function deleteChat(id) {
        var old = history.load(id);
        var om = (old && old.messages) ? old.messages : [];
        for (var i = 0; i < om.length; i++)
            if (om[i].image) images.removeImage(om[i].image);
        history.remove(id);
        if (current.id == id) current = ({});
        homeScreen.reload();
    }
    function apiMessages(c) {
        var out = [];
        var msgs = c.messages || [];
        for (var i = 0; i < msgs.length; i++) {
            var m = msgs[i];
            var o = { role: m.role, text: m.text };   // the full prompt, not the short label
            if (m.image) o.image = m.image;
            out.push(o);
        }
        return out;
    }
    // Ask a question. From Answer it's a follow-up; from Home it starts a new chat; from the camera it
    // follows up if the camera was opened from an answer (cameraContinuesChat), else starts a new chat.
    // label: short text for the question bubble (camera prompts are long); defaults to text.
    function ask(text, image, label) {
        if (chat.busy) {
            toast.body = "Still answering the last question";
            toast.show();
            return;
        }
        var cont = current.id && (screen == "answer" || (screen == "camera" && cameraContinuesChat));
        var c = cont ? current : history.create();
        var msgs = c.messages || [];
        var m = { role: "user", text: text, time: new Date().getTime() };
        if (image) m.image = image;
        if (label && label != text) m.label = label;
        msgs.push(m);
        c.messages = msgs;
        if (!c.title) c.title = (label || text || "Photo").substring(0, 60);
        current = c;
        history.save(c);
        opal.log("ui: ask from " + screen + " (" + msgs.length + " messages" + (image ? ", photo" : "") + ")");
        if (screen != "answer") {
            if (screen == "home") homeScreen.clearAsk();
            answerScreen.showChat({ messages: cont ? msgs.slice(0, msgs.length - 1) : [] });
            go("answer");
        }
        answerScreen.dropTrailingError();
        answerScreen.beginAnswer(m);
        sendCurrent();
        focusAnswerSoon();
    }
    // Focus the answer now and again once a screen switch has settled (an early request can be ignored).
    function focusAnswerSoon() {
        answerScreen.focusAnswer();
        opal.callLater(200, "focusAnswer");
    }
    function sendCurrent() {
        liveText = "";
        answerScreen.busy = true;
        chat.send(apiMessages(current), current.session);
    }
    function retry() {
        answerScreen.restartAnswer();
        sendCurrent();
    }
    // Chat title from the first answer: its "# " title line, else the start of the answer.
    function titleFromAnswer(text) {
        var blocks = answerScreen.parseAnswer(text);
        for (var i = 0; i < blocks.length; i++)
            if (blocks[i].type == "title" && blocks[i].text) return blocks[i].text.substring(0, 60);
        var plain = answerScreen.plainText(text).replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "");
        if (plain.length <= 48) return plain;
        var cut = plain.substring(0, 48);
        var sp = cut.lastIndexOf(" ");
        if (sp > 24) cut = cut.substring(0, sp);
        return cut.replace(/[\s.,;:!?-]+$/, "") + "\u2026";
    }
    function lastAnswer() {
        var msgs = current.messages || [];
        for (var i = msgs.length - 1; i >= 0; i--)
            if (msgs[i].role == "assistant") return msgs[i].text;
        return "";
    }
    // Edit: drop the latest question and its answer, and put the question (and its photo) back in
    // the follow-up field so it can be changed and asked again.
    property bool suppressStopError: false
    function editLast() {
        var c = current;
        var msgs = c.messages || [];
        var u = -1;
        for (var i = msgs.length - 1; i >= 0; i--)
            if (msgs[i].role == "user") { u = i; break; }
        if (u < 0) {
            toast.body = "Nothing to edit";
            toast.show();
            return;
        }
        if (chat.busy) {
            suppressStopError = true;       // don't show "Stopped." for the answer we're discarding
            chat.cancel();
        }
        var q = msgs[u];
        c.messages = msgs.slice(0, u);
        current = c;
        history.save(c);
        answerScreen.busy = false;
        answerScreen.showChat({ messages: c.messages });
        answerScreen.editQuestion(q.label || q.text, q.image || "");
        opal.log("ui: edit question " + u + (q.image ? " (with photo)" : ""));
    }
    function copyAnswer() {
        var t = lastAnswer();
        if (!t) {
            toast.body = "No answer to copy yet";
            toast.show();
            return;
        }
        opal.copyText(answerScreen.plainText(t));
        toast.body = "Answer copied";
        toast.show();
    }
    // Export the chat as a markdown document (Documents/Opal/<title> <date>.md): the chat title,
    // each question as "## …", each answer as the model's own markdown with its headings moved two
    // levels down (so they sit under the question), then its sources as links.
    function demoteHeadings(md) {
        return md.replace(/^(#{1,6})(\s)/gm, function(all, hashes, sp) {
            return (hashes.length + 2 > 6 ? "######" : hashes + "##") + sp;
        });
    }
    function exportChat() {
        var msgs = current.messages || [];
        if (!msgs.length) return;
        var out = ["# " + (current.title || "Opal chat"), ""];
        for (var i = 0; i < msgs.length; i++) {
            var m = msgs[i];
            if (m.role == "user") {
                out.push("## " + (m.label || m.text || "Photo").replace(/\s*\n\s*/g, " "));
                if (m.image) out.push("", "*(asked about a photo)*");
            } else {
                out.push(demoteHeadings(m.text.replace(/^\s+|\s+$/g, "")));
                var src = m.sources || [];
                if (src.length) {
                    out.push("", "**Sources**", "");
                    for (var k = 0; k < src.length; k++)
                        out.push("- [" + src[k].title.replace(/[\[\]]/g, "") + "](" + src[k].url + ")");
                }
                if (m.model) out.push("", "*" + answerScreen.metaText(m) + "*");
            }
            out.push("");
        }
        var path = opal.exportText(current.title, out.join("\n"), "md");
        toast.body = path ? "Saved to Documents/Opal" : "Export failed (see log)";
        toast.show();
    }
    // Opened from an answer, the camera adds its photo to that chat; from Home it starts a new one.
    property bool cameraContinuesChat: false
    function openCamera() {
        if (screen != "camera") cameraContinuesChat = (screen == "answer" && current.id) ? true : false;
        go("camera");
    }

    // Closing the panel hides its focused row; hand focus back once the slide-out has finished.
    onPanelOpenChanged: {
        if (panelOpen) return;
        if (screen == "answer") opal.callLater(250, "focusAnswer");
        else if (screen == "home") opal.callLater(250, "focusHome");
    }

    // ---------------------------------------------------------------- bar / menu actions
    function action(name) {
        opal.log("ui: action " + name + " on " + screen);
        panelOpen = false;
        if (name == "back") back();
        else if (name == "new") newChat();
        else if (name == "camera") openCamera();
        else if (name == "settings") go("settings");
        else if (name == "log") go("log");
        else if (name == "copy") copyAnswer();
        else if (name == "edit") editLast();
        else if (name == "sources") {
            if (!answerScreen.toggleLatestSources()) {
                toast.body = "This chat has no web sources";
                toast.show();
            }
        }
        else if (name == "export") exportChat();
        else if (name == "more") panelOpen = true;
        else if (name == "search") cameraScreen.primary();
        else if (name == "translate") cameraScreen.toggleTranslate();
        else if (name == "flip") cameraScreen.flip();
    }

    onCreationCompleted: {
        chat.delta.connect(function(t) {
            liveText = liveText + t;
            answerScreen.updateAnswer(liveText);
        });
        chat.thinking.connect(function() { answerScreen.setStatus("Thinking…"); });
        chat.searching.connect(function(queries) {
            liveText = "";      // text before a search round is discarded
            answerScreen.setStatus("Searching: " + queries);
        });
        chat.notice.connect(function(message) {
            toast.body = message;
            toast.show();
        });
        chat.finished.connect(function(text, model, finish, sources, tokensIn, tokensOut) {
            answerScreen.busy = false;
            var c = current;
            var msgs = c.messages || [];
            var am = { role: "assistant", text: text, model: model, time: new Date().getTime() };
            if (sources && sources.length) am.sources = sources;
            if (tokensIn >= 0) { am.tokensIn = tokensIn; am.tokensOut = tokensOut; }
            if (finish == "length") am.cutShort = true;
            msgs.push(am);
            c.messages = msgs;
            var answers = 0;
            for (var i = 0; i < msgs.length; i++) if (msgs[i].role == "assistant") answers++;
            if (answers == 1) {
                var t = titleFromAnswer(text);
                if (t) c.title = t;
            }
            current = c;
            history.save(c);
            answerScreen.finishAnswer(text, answerScreen.metaText(am), sources);
            if (page.screen == "answer") focusAnswerSoon();
        });
        opal.later.connect(function(tag) {
            if (tag == "focusHome" && page.screen == "home") homeScreen.focusAsk();
            if (tag == "focusAnswer" && page.screen == "answer") answerScreen.focusAnswer();
            if (tag == "focusPanel" && page.panelOpen) overflowPanel.focusFirst();
        });
        opal.backgrounded.connect(function() { if (page.screen == "camera") cameraScreen.close(); });
        opal.foregrounded.connect(function() { if (page.screen == "camera") cameraScreen.open(); });
        chat.failed.connect(function(message, detail) {
            if (page.suppressStopError) {
                page.suppressStopError = false;
                return;
            }
            answerScreen.busy = false;
            answerScreen.showError(message);
        });
        show("home");
    }

    // ---------------------------------------------------------------- keys
    shortcuts: [
        Shortcut {
            key: "n"
            onTriggered: page.action("new")
        },
        Shortcut {
            key: "k"
            onTriggered: page.action("camera")
        },
        Shortcut {
            key: "t"
            onTriggered: page.action("settings")
        },
        Shortcut {
            key: "y"
            onTriggered: if (page.screen == "answer") page.action("copy")
        },
        Shortcut {
            key: "e"
            onTriggered: if (page.screen == "answer") page.action("export")
        },
        Shortcut {
            key: "o"
            onTriggered: if (page.screen == "answer") page.action("sources")
        },
        Shortcut {
            key: "l"
            onTriggered: if (page.screen == "settings") page.action("log")
        },
        Shortcut {
            key: "Space"
            onTriggered: {
                if (page.screen == "answer") answerScreen.focusFollowUp();
                else if (page.screen == "camera") cameraScreen.primary();
            }
        },
        DeviceShortcut {
            type: DeviceShortcuts.MenuTap
            onTriggered: page.panelOpen = !page.panelOpen
        },
        DeviceShortcut {
            type: DeviceShortcuts.BackTap
            onTriggered: page.back()
        }
    ]

    // ---------------------------------------------------------------- layout
    Container {
        layout: DockLayout {}
        background: Color.create("#121212")
        attachedObjects: [
            LayoutUpdateHandler {
                onLayoutFrameChanged: page.screenW = layoutFrame.width
            },
            SystemToast {
                id: toast
            }
        ]

        HomeScreen {
            id: homeScreen
            visible: page.screen == "home"
            onAsk: page.ask(text, "", "")
            onCameraTapped: page.openCamera()
            onOpenChat: page.openChat(id)
            onDeleteChat: page.deleteChat(id)
        }
        AnswerScreen {
            id: answerScreen
            visible: page.screen == "answer"
            onFollowUp: {
                // A photo may be attached after Edit; with no text, ask the default photo question.
                var img = answerScreen.pendingImage;
                answerScreen.pendingImage = "";
                if (text == "" && img)
                    page.ask("What is this? Identify it and tell me the most useful things to know about it.", img, "What is this?");
                else
                    page.ask(text, img, "");
            }
            onRetry: page.retry()
        }
        CameraScreen {
            id: cameraScreen
            visible: page.screen == "camera"
            onSubmit: page.ask(prompt, image, label)
            onToast: {
                toast.body = text;
                toast.show();
            }
        }
        SettingsScreen {
            id: settingsScreen
            visible: page.screen == "settings"
            onShowLog: page.go("log")
            onToast: {
                toast.body = text;
                toast.show();
            }
        }
        LogScreen {
            id: logScreen
            visible: page.screen == "log"
            onToast: {
                toast.body = text;
                toast.show();
            }
        }

        OverflowPanel {
            id: overflowPanel
            open: page.panelOpen
            screen: page.screen
            screenWidth: page.screenW
            onActivated: page.action(name)
            onCloseRequested: page.panelOpen = false
        }

        // Bar per screen: home = [Camera] ⋮; camera = ‹ Translate [Search] Flip ⋮;
        // answer = ‹ Export [Camera] Edit ⋮ (Copy is in the ⋮ menu); settings/log = ‹ [Camera] ⋮.
        OpalBar {
            property bool onCam: page.screen == "camera"
            property bool onAnswer: page.screen == "answer"
            barWidth: page.screenW
            s1Name: page.screen == "home" ? "" : "back"
            s1Icon: "asset:///ic-back.png"
            s1Label: ""
            s2Name: onCam ? "translate" : (onAnswer ? "export" : "")
            s2Icon: onCam ? (cameraScreen.translate ? "asset:///ic-translate-on.png" : "asset:///ic-translate.png") : "asset:///ic-export.png"
            s2Label: onCam ? "Translate" : "Export"
            s3Name: onCam ? "flip" : (onAnswer ? "edit" : "")
            s3Icon: onCam ? "asset:///ic-flip.png" : "asset:///ic-edit.png"
            s3Label: onCam ? "Flip" : "Edit"
            s4Name: "more"
            s4Icon: "asset:///ic-more.png"
            s4Label: ""
            centreName: onCam ? "search" : "camera"
            centreGlyph: onCam ? "search" : "camera"
            centreLabel: onCam ? (cameraScreen.translate ? "Translate" : (cameraScreen.attached != "" ? "Ask" : "Search")) : "Camera"
            onActivated: page.action(name)
        }
    }
}
