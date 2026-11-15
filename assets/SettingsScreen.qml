// Settings: provider URL, API key, model (from the server's /models list), quick answers.
import bb.cascades 1.4

Container {
    id: settings
    signal showLog()
    signal toast(string text)

    function load() {
        baseField.text = opal.setting("base");
        keyField.text = opal.setting("key");
        promptArea.text = opal.setting("systemPrompt");
        tavilyField.text = opal.setting("tavilyKey");
        searchToggle.checked = opal.setting("search") == "1";
        quick.checked = opal.setting("quick") == "1";
        ignoreSsl.checked = opal.setting("ignoreSsl") == "1";
        filling = true;
        opal.fillModelDropDown(modelDrop);
        filling = false;
        if (opal.imageModels().length == 0 && opal.setting("key") != "") opal.refreshModels();
    }
    // Text fields are saved when leaving the screen (and on Enter).
    function save() {
        opal.setSetting("base", baseField.text.trim());
        opal.setSetting("key", keyField.text.trim());
        if (promptArea.text.trim() != "") opal.setSetting("systemPrompt", promptArea.text);
        opal.setSetting("tavilyKey", tavilyField.text.trim());
    }
    property bool filling: false

    onCreationCompleted: {
        opal.modelsUpdated.connect(function(ok, message) {
            filling = true;
            opal.fillModelDropDown(modelDrop);
            filling = false;
            settings.toast(message);
        });
    }

    horizontalAlignment: HorizontalAlignment.Fill
    verticalAlignment: VerticalAlignment.Fill
    bottomPadding: ui.du(12)

    ScrollView {
        horizontalAlignment: HorizontalAlignment.Fill
        Container {
            leftPadding: ui.du(4)
            rightPadding: ui.du(4)
            topPadding: ui.du(2.5)
            bottomPadding: ui.du(8)

            Label {
                text: "Settings"
                textStyle.color: Color.White
                textStyle.base: SystemDefaults.TextStyles.BigText
                textStyle.fontSize: FontSize.PercentageValue
                textStyle.fontSizeValue: 108
            }

            Label {
                text: "API KEY"
                topMargin: ui.du(2)
                textStyle.color: Color.create("#9a9a9a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
                textStyle.fontWeight: FontWeight.Bold
            }
            FocusFrame {
                target: keyField
                TextField {
                    navigation.defaultHighlightEnabled: false
                    id: keyField
                    hintText: "Paste your OpenCode Go key"
                    inputMode: TextFieldInputMode.Password
                    input.submitKey: SubmitKey.Done
                    input.onSubmitted: settings.save()
                }
            }

            Label {
                text: "MODEL"
                topMargin: ui.du(2)
                textStyle.color: Color.create("#9a9a9a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
                textStyle.fontWeight: FontWeight.Bold
            }
            FocusFrame {
                target: modelDrop
                DropDown {
                    navigation.defaultHighlightEnabled: false
                    id: modelDrop
                    title: "Model"
                    onSelectedValueChanged: {
                        if (!settings.filling && selectedValue) opal.setSetting("model", selectedValue);
                    }
                }
            }
            Container {
                layout: StackLayout {
                    orientation: LayoutOrientation.LeftToRight
                }
                FocusFrame {
                    target: refreshButton
                    horizontalAlignment: HorizontalAlignment.Left
                    Button {
                        navigation.defaultHighlightEnabled: false
                        id: refreshButton
                        text: opal.modelsBusy ? "Loading…" : "Refresh model list"
                        enabled: !opal.modelsBusy
                        onClicked: {
                            settings.save();
                            opal.refreshModels();
                        }
                    }
                }
                ActivityIndicator {
                    running: opal.modelsBusy
                    visible: opal.modelsBusy
                    leftMargin: ui.du(2)
                    verticalAlignment: VerticalAlignment.Center
                }
            }
            Label {
                text: "Only models that accept photos are listed."
                multiline: true
                textStyle.color: Color.create("#7a7a7a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
            }

            Container {
                topMargin: ui.du(2)
                layout: DockLayout {}
                horizontalAlignment: HorizontalAlignment.Fill
                Label {
                    text: "Quick answers"
                    verticalAlignment: VerticalAlignment.Center
                    textStyle.color: Color.White
                    textStyle.base: SystemDefaults.TextStyles.BodyText
                    textStyle.fontSize: FontSize.PercentageValue
                    textStyle.fontSizeValue: 85
                }
                FocusFrame {
                    target: quick
                    horizontalAlignment: HorizontalAlignment.Right
                    ToggleButton {
                        navigation.defaultHighlightEnabled: false
                        id: quick
                        horizontalAlignment: HorizontalAlignment.Right
                        onCheckedChanged: opal.setSetting("quick", checked ? "1" : "0")
                    }
                }
            }
            Label {
                text: "Asks the model to think as little as it allows. Turn off for harder questions."
                multiline: true
                textStyle.color: Color.create("#7a7a7a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
            }

            Label {
                text: "WEB SEARCH"
                topMargin: ui.du(2)
                textStyle.color: Color.create("#9a9a9a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
                textStyle.fontWeight: FontWeight.Bold
            }
            Container {
                horizontalAlignment: HorizontalAlignment.Fill
                layout: DockLayout {}
                Label {
                    text: "Search the web when needed"
                    verticalAlignment: VerticalAlignment.Center
                    textStyle.color: Color.White
                    textStyle.base: SystemDefaults.TextStyles.BodyText
                    textStyle.fontSize: FontSize.PercentageValue
                    textStyle.fontSizeValue: 85
                }
                FocusFrame {
                    target: searchToggle
                    horizontalAlignment: HorizontalAlignment.Right
                    ToggleButton {
                        id: searchToggle
                        navigation.defaultHighlightEnabled: false
                        onCheckedChanged: opal.setSetting("search", checked ? "1" : "0")
                    }
                }
            }
            FocusFrame {
                target: tavilyField
                TextField {
                    id: tavilyField
                    navigation.defaultHighlightEnabled: false
                    hintText: "Tavily API key (tvly-\u2026)"
                    inputMode: TextFieldInputMode.Password
                    input.submitKey: SubmitKey.Done
                    input.onSubmitted: settings.save()
                }
            }
            Label {
                text: "The model searches only when a question needs current or specific facts; answers then list their sources. Uses Tavily (tavily.com, about 1,000 free searches a month)."
                multiline: true
                textStyle.color: Color.create("#7a7a7a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
            }

            Label {
                text: "SYSTEM PROMPT"
                topMargin: ui.du(2)
                textStyle.color: Color.create("#9a9a9a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
                textStyle.fontWeight: FontWeight.Bold
            }
            FocusFrame {
                target: promptArea
                TextArea {
                    id: promptArea
                    navigation.defaultHighlightEnabled: false
                    minHeight: ui.du(22)
                    hintText: "Instructions sent with every question"
                    textFormat: TextFormat.Plain
                    textStyle.base: SystemDefaults.TextStyles.BodyText
                    textStyle.fontSize: FontSize.PercentageValue
                    textStyle.fontSizeValue: 72
                }
            }
            Label {
                text: "Sent with every question. Keep the '# ' title line rule: it gives each answer its title. Saved when you leave Settings."
                multiline: true
                textStyle.color: Color.create("#7a7a7a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
            }
            FocusFrame {
                target: resetPromptButton
                horizontalAlignment: HorizontalAlignment.Left
                Button {
                    id: resetPromptButton
                    navigation.defaultHighlightEnabled: false
                    text: "Reset to default"
                    onClicked: {
                        promptArea.text = opal.defaultSystemPrompt();
                        opal.setSetting("systemPrompt", "");
                        settings.toast("System prompt reset");
                    }
                }
            }

            Label {
                text: "SERVER"
                topMargin: ui.du(2)
                textStyle.color: Color.create("#9a9a9a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
                textStyle.fontWeight: FontWeight.Bold
            }
            FocusFrame {
                target: baseField
                TextField {
                    navigation.defaultHighlightEnabled: false
                    id: baseField
                    hintText: "Base URL (OpenAI-compatible)"
                    inputMode: TextFieldInputMode.Url
                    input.submitKey: SubmitKey.Done
                    input.onSubmitted: settings.save()
                }
            }
            Label {
                text: "Any OpenAI-compatible server works. Default: https://opencode.ai/inference/go/v1"
                multiline: true
                textStyle.color: Color.create("#7a7a7a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
            }
            Container {     // CheckBox text can't be resized, so label it separately
                topMargin: ui.du(1.5)
                horizontalAlignment: HorizontalAlignment.Fill
                layout: DockLayout {}
                Label {
                    text: "Ignore certificate errors"
                    verticalAlignment: VerticalAlignment.Center
                    textStyle.color: Color.White
                    textStyle.base: SystemDefaults.TextStyles.BodyText
                    textStyle.fontSize: FontSize.PercentageValue
                    textStyle.fontSizeValue: 85
                }
                FocusFrame {
                    target: ignoreSsl
                    horizontalAlignment: HorizontalAlignment.Right
                    CheckBox {
                        navigation.defaultHighlightEnabled: false
                        id: ignoreSsl
                        horizontalAlignment: HorizontalAlignment.Right
                        onCheckedChanged: opal.setSetting("ignoreSsl", checked ? "1" : "0")
                    }
                }
            }
            Label {
                text: "Insecure. Only for troubleshooting connection problems."
                multiline: true
                textStyle.color: Color.create("#7a7a7a")
                textStyle.base: SystemDefaults.TextStyles.SmallText
            }

            FocusFrame {
                target: logButton
                Button {
                    navigation.defaultHighlightEnabled: false
                    id: logButton
                    text: "View log"
                    topMargin: ui.du(2)
                    horizontalAlignment: HorizontalAlignment.Fill
                    onClicked: settings.showLog()
                }
            }
            Label {
                text: "Opal " + opal.version + " · log: data/opal.log"
                topMargin: ui.du(1)
                textStyle.color: Color.create("#6f6f6f")
                textStyle.base: SystemDefaults.TextStyles.SmallText
            }
        }
    }
}
