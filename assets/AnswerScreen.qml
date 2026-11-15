// Conversation view: question bubble, answer title, paragraphs, lists, tables and sources,
// then a follow-up field. Answers are markdown, re-parsed into blocks as they stream in.
import bb.cascades 1.4
import opal.helpers 1.0 as Helpers

Container {
    id: screen
    property bool busy: false
    property int liveStart: -1          // index of the first block of the streaming answer
    property string pendingImage: ""    // photo attached to the follow-up field (after Edit)
    // While an answer streams in, its question bubble is kept at the top of the screen (as far as
    // the list can scroll), the same place a fresh load of the chat shows, until the user scrolls.
    // Re-pinning is unanimated: an animated scroll on a short answer overshot and bounced.
    property bool pinLive: false
    property int liveUser: -1           // index of the question bubble of the streaming answer
    signal followUp(string text)
    signal retry()

    // ---------------------------------------------------------------- parsing (markdown)
    // Markdown -> blocks: title, heading{level}, para{html}, li{html,indent,marker}, code{text},
    // quote{html}, rule, trow{cells,cols,header}. Inline markdown becomes the HTML subset Cascades
    // renders (b, i, a href, span style, br).
    function escapeHtml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    function stripHtml(s) {
        return s.replace(/<br\s*\/?>/g, "\n").replace(/<[^>]+>/g, "")
                .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&amp;/g, "&");
    }
    // Inline markdown -> HTML. Code spans first (their contents stay literal), then links, bold, italic.
    function inlineMd(src) {
        var parts = src.split("`");
        var out = "";
        for (var i = 0; i < parts.length; i++) {
            var p = parts[i];
            if (i % 2 == 1 && i < parts.length - 1) {          // inside `code`
                out += "<span style='font-family:monospace;color:#e6c07b'>" + escapeHtml(p) + "</span>";
                continue;
            }
            if (i % 2 == 1) p = "`" + p;                         // unmatched backtick: keep it
            var h = escapeHtml(p);
            h = h.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, "<a href='$2'>$1</a>");
            h = h.replace(/\*\*(?=\S)([\s\S]*?\S)\*\*/g, "<b>$1</b>");
            h = h.replace(/__(?=\S)([\s\S]*?\S)__/g, "<b>$1</b>");
            h = h.replace(/(^|[^*\w])\*(?=\S)([^*]*?\S)\*(?![*\w])/g, "$1<i>$2</i>");
            h = h.replace(/(^|[^_\w])_(?=\S)([^_]*?\S)_(?![_\w])/g, "$1<i>$2</i>");
            h = h.replace(/~~(?=\S)([\s\S]*?\S)~~/g, "$1");     // no strikethrough in Cascades: drop markers
            out += h;
        }
        return out;
    }
    function plainInline(src) { return stripHtml(inlineMd(src)); }
    function splitRow(line) {
        var t = line.replace(/^\s*\|/, "").replace(/\|\s*$/, "");
        var cells = t.split("|");
        for (var i = 0; i < cells.length; i++) cells[i] = cells[i].replace(/^\s+|\s+$/g, "");
        return cells;
    }
    // A table row block: up to 4 columns; extra cells are merged into the last one.
    function tableRow(cells, cols, isHeader) {
        var c = [];
        for (var k = 0; k < cols; k++) c.push(k < cells.length ? inlineMd(cells[k]) : "");
        if (cells.length > cols) c[cols - 1] = inlineMd(cells.slice(cols - 1).join(" | "));
        return { type: "trow", cells: c, cols: cols, header: isHeader };
    }
    function isTableSep(line) { return line.indexOf("-") >= 0 && /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(line); }

    function parseMarkdown(text) {
        var blocks = [];
        var para = [], quote = [];
        var haveTitle = false;
        var lines = text.split("\n");
        function flushPara() {
            if (para.length) blocks.push({ type: "para", html: para.join("<br/>") });
            para = [];
        }
        function flushQuote() {
            if (quote.length) blocks.push({ type: "quote", html: quote.join("<br/>") });
            quote = [];
        }
        function flushAll() { flushPara(); flushQuote(); }
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].replace(/\s+$/, "");
            var t = line.replace(/^\s+/, "");
            var m;
            // fenced code block (an unclosed fence while streaming runs to the end)
            if (/^```/.test(t)) {
                flushAll();
                var code = [];
                for (i++; i < lines.length && !/^\s*```/.test(lines[i]); i++) code.push(lines[i].replace(/\s+$/, ""));
                blocks.push({ type: "code", text: code.join("\n") });
                continue;
            }
            if (t.length == 0) { flushAll(); continue; }
            if ((m = t.match(/^(#{1,6})\s+(.*)$/))) {
                flushAll();
                var htext = plainInline(m[2].replace(/\s+#+$/, ""));
                if (!haveTitle && blocks.length == 0) blocks.push({ type: "title", text: htext });
                else blocks.push({ type: "heading", text: htext, level: m[1].length });
                haveTitle = true;
                continue;
            }
            if (/^([-*_])(\s*\1){2,}$/.test(t)) { flushAll(); blocks.push({ type: "rule" }); continue; }
            // table: a row line followed by a separator line
            if (t.charAt(0) == "|" && i + 1 < lines.length && isTableSep(lines[i + 1])) {
                flushAll();
                var header = splitRow(t);
                var rows = [];
                for (i += 2; i < lines.length && /^\s*\|/.test(lines[i]); i++) rows.push(splitRow(lines[i]));
                i--;
                var cols = Math.min(4, header.length);
                blocks.push(tableRow(header, cols, true));
                for (var r = 0; r < rows.length; r++) blocks.push(tableRow(rows[r], cols, false));
                continue;
            }
            if ((m = line.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/))) {
                flushAll();
                var indent = Math.min(3, Math.floor(m[1].replace(/\t/g, "    ").length / 2));
                var marker = /\d/.test(m[2]) ? m[2].replace(")", ".") : (indent > 0 ? "◦" : "•");
                blocks.push({ type: "li", html: inlineMd(m[3]), indent: indent, marker: marker });
                continue;
            }
            if ((m = t.match(/^>\s?(.*)$/))) { flushPara(); quote.push(inlineMd(m[1])); continue; }
            // a wrapped continuation of the previous list item
            if (para.length == 0 && quote.length == 0 && blocks.length && blocks[blocks.length - 1].type == "li" && /^\s+/.test(line)) {
                blocks[blocks.length - 1].html += " " + inlineMd(t);
                continue;
            }
            flushQuote();
            para.push(inlineMd(t));
        }
        flushAll();
        return blocks;
    }
    // Plain text of an answer (Copy / Export / chat title fallback).
    function plainBlocks(blocks) {
        var out = "";
        for (var i = 0; i < blocks.length; i++) {
            var b = blocks[i], line = "";
            if (b.type == "title" || b.type == "heading") line = b.text;
            else if (b.type == "para") line = stripHtml(b.html);
            else if (b.type == "quote") line = "> " + stripHtml(b.html).replace(/\n/g, "\n> ");
            else if (b.type == "li") line = new Array(b.indent + 1).join("  ") + b.marker + " " + stripHtml(b.html);
            else if (b.type == "code") line = b.text;
            else if (b.type == "rule") line = "---";
            else if (b.type == "trow") {
                var cs = [];
                for (var k = 0; k < b.cells.length; k++) cs.push(stripHtml(b.cells[k]));
                line = cs.join(" | ");
            }
            // list items and table rows sit on consecutive lines; everything else is a paragraph
            var tight = i > 0 && blocks[i - 1].type == b.type && (b.type == "li" || b.type == "trow");
            out += (i == 0 ? "" : (tight ? "\n" : "\n\n")) + line;
        }
        return out;
    }

    function parseAnswer(text) { return parseMarkdown(text); }
    function plainText(text) { return plainBlocks(parseMarkdown(text)); }

    // ---------------------------------------------------------------- model updates
    // A string that changes whenever anything visible in the block changes (JSON key order isn't
    // stable across the C++ model round trip, so compare this instead of whole objects).
    function blockSig(b) {
        return [b.type, b.text, b.html, b.label, b.image, b.indent, b.marker, b.level, b.header, b.open,
                b.cells ? b.cells.join("\u0001") : ""].join("\u0002");
    }
    function sameBlock(a, b) {
        return a && b && a.sig == b.sig;
    }
    function setBlocksFrom(start, blocks) {
        for (var j = 0; j < blocks.length; j++) blocks[j].sig = blockSig(blocks[j]);
        for (var i = 0; i < blocks.length; i++) {
            var idx = start + i;
            if (idx < blocksModel.size()) {
                if (!sameBlock(blocksModel.value(idx), blocks[i])) blocksModel.replace(idx, blocks[i]);
            } else {
                blocksModel.append(blocks[i]);
            }
        }
        while (blocksModel.size() > start + blocks.length) blocksModel.removeAt(blocksModel.size() - 1);
    }
    function pin() {
        if (pinLive && liveUser >= 0) list.scrollToItem([liveUser], ScrollAnimation.None);
    }
    function settle() {     // finished: one last (unanimated) pin, then leave the view alone
        pin();
        pinLive = false;
    }
    // ---- web search sources: a chip under the answer that expands into tappable rows
    function sourcesBlock(sources) {
        return { type: "sources", items: sources, open: false, text: sources.length + (sources.length == 1 ? " source" : " sources") };
    }
    function hostOf(url) {
        return url.replace(/^https?:\/\//, "").split("/")[0].replace(/^www\./, "");
    }
    function toggleSources(i) {
        var chip = blocksModel.value(i);
        if (!chip || chip.type != "sources") return;
        if (chip.open) {
            while (i + 1 < blocksModel.size() && blocksModel.value(i + 1).type == "source") blocksModel.removeAt(i + 1);
        } else {
            var items = chip.items || [];
            for (var k = items.length - 1; k >= 0; k--)
                blocksModel.insert(i + 1, { type: "source", text: items[k].title, url: items[k].url, label: hostOf(items[k].url) });
        }
        chip.open = !chip.open;
        blocksModel.replace(i, chip);
    }
    // Shortcut / menu: open (or close) the sources of the latest answer that has some.
    function toggleLatestSources() {
        for (var i = blocksModel.size() - 1; i >= 0; i--) {
            if (blocksModel.value(i).type == "sources") {
                toggleSources(i);
                list.scrollToItem([i], ScrollAnimation.Default);
                return true;
            }
        }
        return false;
    }
    function userBlock(m) {
        return { type: "user", text: m.label || m.text || (m.image ? "(photo)" : ""), image: m.image ? "file://" + m.image : "" };
    }
    // 950 -> "950", 1234 -> "1.2K", 12345 -> "12K", 1234567 -> "1.2M"
    function fmtTokens(n) {
        if (n < 1000) return "" + n;
        if (n < 1000000) { var k = n / 1000; return (k < 10 ? k.toFixed(1).replace(/\.0$/, "") : Math.round(k)) + "K"; }
        var m = n / 1000000;
        return (m < 10 ? m.toFixed(1).replace(/\.0$/, "") : Math.round(m)) + "M";
    }
    // Grey line under an answer: "model | 1.2K in / 365 out" (+ " | cut short")
    function metaText(m) {
        var parts = [];
        if (m.model) parts.push(m.model);
        if (m.tokensIn !== undefined && m.tokensIn >= 0)
            parts.push(fmtTokens(m.tokensIn) + " in / " + fmtTokens(m.tokensOut >= 0 ? m.tokensOut : 0) + " out");
        if (m.cutShort) parts.push("cut short");
        return parts.join(" | ");
    }
    // Rebuild everything from a saved chat. If its last question has no answer (it failed, or the
    // app was closed while waiting), offer Try again.
    function showChat(chat) {
        blocksModel.clear();
        liveStart = -1;
        pinLive = false;
        liveUser = -1;
        var msgs = chat.messages || [];
        var lastUser = 0;
        for (var i = 0; i < msgs.length; i++) {
            var m = msgs[i];
            if (m.role == "user") {
                lastUser = blocksModel.size();
                blocksModel.append(userBlock(m));
            } else {
                var bl = parseAnswer(m.text);
                for (var j = 0; j < bl.length; j++) blocksModel.append(bl[j]);
                if (m.sources && m.sources.length) blocksModel.append(sourcesBlock(m.sources));
                if (metaText(m)) blocksModel.append({ type: "meta", text: metaText(m) });
            }
        }
        if (msgs.length && msgs[msgs.length - 1].role == "user")
            blocksModel.append({ type: "error", text: "This question wasn't answered." });
        list.scrollToItem([lastUser], ScrollAnimation.None);
    }
    // A new question was sent: show its bubble and a "Thinking…" row.
    function beginAnswer(userMsg) {
        liveUser = blocksModel.size();
        blocksModel.append(userBlock(userMsg));
        liveStart = blocksModel.size();
        blocksModel.append({ type: "status", text: "Asking\u2026" });
        pinLive = true;
        list.scrollToItem([liveUser], ScrollAnimation.Default);
    }
    function setStatus(text) {
        if (liveStart < 0) return;
        setBlocksFrom(liveStart, [{ type: "status", text: text }]);
        pin();
    }
    function updateAnswer(text) {
        if (liveStart < 0) return;
        var bl = parseAnswer(text);
        if (bl.length == 0) bl = [{ type: "status", text: "Thinking\u2026" }];
        setBlocksFrom(liveStart, bl);
        pin();
    }
    function finishAnswer(text, model, sources) {
        if (liveStart < 0) return;
        var bl = parseAnswer(text);
        if (sources && sources.length) bl.push(sourcesBlock(sources));
        if (model) bl.push({ type: "meta", text: model });
        setBlocksFrom(liveStart, bl);
        liveStart = -1;
        settle();
    }
    function showError(message) {
        if (liveStart < 0) liveStart = blocksModel.size();
        setBlocksFrom(liveStart, [{ type: "error", text: message }]);
        liveStart = -1;
        settle();
    }
    function dropTrailingError() {
        var last = blocksModel.size() - 1;
        if (last >= 0 && blocksModel.value(last).type == "error") blocksModel.removeAt(last);
    }
    // Retry: drop the error row and show "Asking…" again (the question bubble stays).
    function restartAnswer() {
        dropTrailingError();
        liveUser = blocksModel.size() - 1;      // the question bubble just above
        liveStart = blocksModel.size();
        blocksModel.append({ type: "status", text: "Asking\u2026" });
        pinLive = true;
        pin();
    }
    function focusFollowUp() { followField.focusField(); }
    // Edit: put a question (and its photo) back into the follow-up field.
    function editQuestion(text, image) {
        followField.text = text;
        pendingImage = image || "";
        followField.focusField();
    }
    // Give the trackpad to the answer (it scrolls; no highlight), unless a follow-up is being typed.
    // (The system itself moves focus to the follow-up field when this screen appears, so "field is
    // focused" doesn't mean the user is typing; text in it does.)
    function focusAnswer() {
        if (followField.text.length > 0) return;
        list.requestFocus();
        opal.log("ui: focus answer list -> " + (list.focused ? "ok" : "NOT taken"));
    }

    // ---------------------------------------------------------------- layout
    // Layout at 720 px: bubble right-aligned 32 px from the edge, title ~22 px caps,
    // body ~17 px caps, fact label column ~120 px, follow-up field 517-576 px from the top.
    // Answer items are not trackpad-focusable: the trackpad scrolls the answer, and only at the
    // end moves on to the follow-up field and the bar.
    horizontalAlignment: HorizontalAlignment.Fill
    verticalAlignment: VerticalAlignment.Fill
    bottomPadding: ui.du(18)

    ListView {
        id: list
        property real itemWidth: 720
        layoutProperties: StackLayoutProperties {
            spaceQuota: 1
        }
        navigation.defaultHighlightEnabled: false
        navigation.focusPolicy: NavigationFocusPolicy.Focusable
        focusPolicy: FocusPolicy.Key
        dataModel: ArrayDataModel {
            id: blocksModel
        }
        attachedObjects: [
            LayoutUpdateHandler {
                onLayoutFrameChanged: {
                    list.itemWidth = layoutFrame.width;
                    list.viewHeight = layoutFrame.height;
                }
            },
            ListScrollStateHandler {
                id: scrollState
            }
        ]
        // Trackpad scrolling done by us: the built-in navigation scrolling of a list without
        // focusable items queued steps and kept jumping after the finger stopped. We scroll 1:1 with
        // the raw trackpad movement, then add a fling like native scrolling had: a quick swipe glides
        // on, a hard one jumps to the top/bottom. Up/Down are consumed only while there is somewhere
        // to scroll, so at the end Down still moves on to the follow-up field and the bar.
        property real trackpadSpeed: 2          // px of scroll per unit of trackpad deltaY
        property real flingMinSpeed: 60         // units/s at release below which there's no fling
        property real flingGlide: 0.3           // fling distance = release speed x this many seconds
        property real flingJumpScreens: 1.5     // a fling longer than this many screens jumps to the end
        property real viewHeight: 500
        property real gestureDelta: 0
        property real gestureScroll: 0
        property variant samples: []            // [[time ms, deltaY], ...] of the last ~120 ms

        // Release speed in trackpad units per second, from the last 120 ms of movement
        // (0 if the finger had already stopped moving before lifting).
        function releaseSpeed() {
            var now = new Date().getTime();
            var sm = samples, sum = 0, first = now;
            for (var i = 0; i < sm.length; i++) {
                if (now - sm[i][0] <= 120) {
                    sum += sm[i][1];
                    if (sm[i][0] < first) first = sm[i][0];
                }
            }
            if (sm.length == 0 || now - sm[sm.length - 1][0] > 80) return 0;
            return sum / Math.max(40, now - first) * 1000;
        }
        function fling() {
            var v = releaseSpeed();
            var what = "none";
            if (Math.abs(v) >= flingMinSpeed) {
                var dist = v * flingGlide * trackpadSpeed;
                if (Math.abs(dist) > flingJumpScreens * viewHeight) {
                    scrollToPosition(dist > 0 ? ScrollPosition.End : ScrollPosition.Beginning, ScrollAnimation.Default);
                    what = dist > 0 ? "jump to end" : "jump to top";
                } else {
                    scroll(dist, ScrollAnimation.Default);
                    what = "glide " + Math.round(dist) + " px";
                }
            }
            opal.log("trackpad: gesture deltaY " + gestureDelta.toFixed(1) + " -> scrolled "
                     + Math.round(gestureScroll) + " px, release " + Math.round(v) + " units/s, fling: " + what);
        }

        eventHandlers: [
            Helpers.TrackpadHandler {
                consumeTrackpadEvents: (scrollState.atBeginning ? 0 : Helpers.ConsumeTrackpadEvent.Up)
                                     | (scrollState.atEnd ? 0 : Helpers.ConsumeTrackpadEvent.Down)
                onTrackpad: {
                    if (event.isBegin()) {
                        list.gestureDelta = 0;
                        list.gestureScroll = 0;
                        list.samples = [];
                    } else if (event.trackpadEventType == Helpers.TrackpadEventType.Move) {
                        screen.pinLive = false;         // the user is scrolling: stop keeping the title at the top
                        var dy = event.deltaY;
                        var now = new Date().getTime();
                        var sm = list.samples;
                        sm.push([now, dy]);
                        while (sm.length && now - sm[0][0] > 150) sm.shift();
                        list.samples = sm;
                        if ((dy < 0 && scrollState.atBeginning) || (dy > 0 && scrollState.atEnd)) return;
                        list.gestureDelta += dy;
                        list.gestureScroll += dy * list.trackpadSpeed;
                        list.scroll(dy * list.trackpadSpeed, ScrollAnimation.None);
                    } else if (event.isEnd() && list.gestureDelta != 0) {
                        list.fling();
                    }
                }
            }
        ]
        function itemType(data, indexPath) { return data.type; }
        onTriggered: {
            var d = dataModel.data(indexPath);
            if (!d) return;
            if (d.type == "sources") screen.toggleSources(indexPath[0]);
            else if (d.type == "source") opal.openUrl(d.url);
        }
        onTouch: if (event.isDown()) screen.pinLive = false
        function requestRetry() { screen.retry(); }

        listItemComponents: [
            ListItemComponent {
                type: "user"
                Container {
                    id: userRoot
                    preferredWidth: userRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(12)
                    rightPadding: ui.du(4)
                    topPadding: ui.du(3)
                    bottomPadding: ui.du(1)
                    layout: DockLayout {}
                    Container {
                        horizontalAlignment: HorizontalAlignment.Right
                        background: Color.create("#24223a")
                        leftPadding: ui.du(1.5)
                        rightPadding: ui.du(2)
                        topPadding: ui.du(1.5)
                        bottomPadding: ui.du(1.5)
                        layout: StackLayout {
                            orientation: LayoutOrientation.LeftToRight
                        }
                        ImageView {
                            visible: ListItemData.image != ""
                            imageSource: ListItemData.image
                            preferredWidth: ui.du(7)
                            preferredHeight: ui.du(7)
                            rightMargin: ui.du(2)
                            verticalAlignment: VerticalAlignment.Center
                            scalingMethod: ScalingMethod.AspectFill
                        }
                        Label {
                            text: ListItemData.text
                            multiline: true
                            verticalAlignment: VerticalAlignment.Center
                            textStyle.color: Color.White
                            textStyle.base: SystemDefaults.TextStyles.BodyText
                            textStyle.fontSize: FontSize.PercentageValue
                            textStyle.fontSizeValue: 92
                        }
                    }
                }
            },
            ListItemComponent {
                type: "title"
                Container {
                    id: titleRoot
                    preferredWidth: titleRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(4)
                    rightPadding: ui.du(4)
                    topPadding: ui.du(2)
                    Label {
                        text: ListItemData.text
                        multiline: true
                        textStyle.color: Color.White
                        textStyle.base: SystemDefaults.TextStyles.BigText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: 108
                    }
                }
            },
            ListItemComponent {
                type: "heading"
                Container {
                    id: headRoot
                    preferredWidth: headRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(4)
                    rightPadding: ui.du(4)
                    topPadding: ui.du(1.8)
                    Label {
                        text: ListItemData.text
                        multiline: true
                        textStyle.color: Color.White
                        textStyle.base: SystemDefaults.TextStyles.BodyText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: ListItemData.level <= 2 ? 92 : 84
                        textStyle.fontWeight: FontWeight.Bold
                    }
                }
            },
            ListItemComponent {
                type: "para"
                Container {
                    id: paraRoot
                    preferredWidth: paraRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(2.5)
                    rightPadding: ui.du(2.5)
                    // Read-only TextArea (not Label) so long-press selection works; HTML for inline
                    // markdown; ActiveText makes links tappable.
                    TextArea {
                        text: "<html>" + ListItemData.html + "</html>"
                        textFormat: TextFormat.Html
                        content.flags: TextContentFlag.ActiveText
                        editable: false
                        backgroundVisible: false
                        focusHighlightEnabled: false
                        navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                        navigation.defaultHighlightEnabled: false
                        textStyle.color: Color.create("#d6d6d6")
                        textStyle.base: SystemDefaults.TextStyles.BodyText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: 78
                    }
                }
            },
            ListItemComponent {
                type: "li"
                Container {     // list item: marker + text, indented by nesting level
                    id: liRoot
                    preferredWidth: liRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(3.5) + ListItemData.indent * ui.du(3)
                    rightPadding: ui.du(2.5)
                    layout: StackLayout {
                        orientation: LayoutOrientation.LeftToRight
                    }
                    Label {
                        text: ListItemData.marker
                        minWidth: ui.du(3)
                        topMargin: ui.du(1)
                        textStyle.color: Color.create("#b9a6f0")
                        textStyle.base: SystemDefaults.TextStyles.BodyText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: 78
                    }
                    TextArea {
                        layoutProperties: StackLayoutProperties {
                            spaceQuota: 1
                        }
                        text: "<html>" + ListItemData.html + "</html>"
                        textFormat: TextFormat.Html
                        content.flags: TextContentFlag.ActiveText
                        editable: false
                        backgroundVisible: false
                        focusHighlightEnabled: false
                        navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                        navigation.defaultHighlightEnabled: false
                        textStyle.color: Color.create("#d6d6d6")
                        textStyle.base: SystemDefaults.TextStyles.BodyText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: 78
                    }
                }
            },
            ListItemComponent {
                type: "code"
                Container {     // fenced code block: monospace on a dark panel
                    id: codeRoot
                    preferredWidth: codeRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(4)
                    rightPadding: ui.du(4)
                    topPadding: ui.du(1)
                    bottomPadding: ui.du(1)
                    Container {
                        horizontalAlignment: HorizontalAlignment.Fill
                        background: Color.create("#1b1b1b")
                        leftPadding: ui.du(1)
                        rightPadding: ui.du(1)
                        TextArea {
                            text: ListItemData.text
                            textFormat: TextFormat.Plain
                            editable: false
                            backgroundVisible: false
                            focusHighlightEnabled: false
                            navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                            navigation.defaultHighlightEnabled: false
                            textStyle.fontFamily: "monospace"
                            textStyle.color: Color.create("#e6e6e6")
                            textStyle.base: SystemDefaults.TextStyles.BodyText
                            textStyle.fontSize: FontSize.PercentageValue
                            textStyle.fontSizeValue: 64
                        }
                    }
                }
            },
            ListItemComponent {
                type: "quote"
                Container {     // > quote: purple bar + muted text
                    id: quoteRoot
                    preferredWidth: quoteRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(4)
                    rightPadding: ui.du(2.5)
                    topPadding: ui.du(0.5)
                    bottomPadding: ui.du(0.5)
                    layout: StackLayout {
                        orientation: LayoutOrientation.LeftToRight
                    }
                    Container {
                        verticalAlignment: VerticalAlignment.Fill
                        preferredWidth: 4
                        minWidth: 4
                        background: Color.create("#6B52A8")
                    }
                    TextArea {
                        layoutProperties: StackLayoutProperties {
                            spaceQuota: 1
                        }
                        text: "<html>" + ListItemData.html + "</html>"
                        textFormat: TextFormat.Html
                        content.flags: TextContentFlag.ActiveText
                        editable: false
                        backgroundVisible: false
                        focusHighlightEnabled: false
                        navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                        navigation.defaultHighlightEnabled: false
                        textStyle.color: Color.create("#a8a8a8")
                        textStyle.base: SystemDefaults.TextStyles.BodyText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: 76
                        textStyle.fontStyle: FontStyle.Italic
                    }
                }
            },
            ListItemComponent {
                type: "rule"
                Container {
                    id: ruleRoot
                    preferredWidth: ruleRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(4)
                    rightPadding: ui.du(4)
                    topPadding: ui.du(1.5)
                    bottomPadding: ui.du(1.5)
                    Container {
                        horizontalAlignment: HorizontalAlignment.Fill
                        preferredHeight: 1
                        background: Color.create("#3a3a3a")
                    }
                }
            },
            ListItemComponent {
                type: "trow"
                Container {     // table row; 2-column tables read as fact rows
                    id: rowRootT
                    preferredWidth: rowRootT.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(4)
                    rightPadding: ui.du(4)
                    Container {
                        horizontalAlignment: HorizontalAlignment.Fill
                        preferredHeight: 1
                        background: Color.create("#333333")
                    }
                    Container {
                        horizontalAlignment: HorizontalAlignment.Fill
                        background: ListItemData.header ? Color.create("#1c1c1c") : Color.Transparent
                        topPadding: ui.du(1)
                        bottomPadding: ui.du(1)
                        layout: StackLayout {
                            orientation: LayoutOrientation.LeftToRight
                        }
                        Label {
                            layoutProperties: StackLayoutProperties {
                                spaceQuota: ListItemData.cols == 2 ? 1 : 1.2
                            }
                            text: "<html>" + ListItemData.cells[0] + "</html>"
                            textFormat: TextFormat.Html
                            multiline: true
                            textStyle.color: ListItemData.header ? Color.create("#9a9a9a") : Color.White
                            textStyle.fontWeight: (ListItemData.header || ListItemData.cols == 2) ? FontWeight.Bold : FontWeight.Normal
                            textStyle.base: SystemDefaults.TextStyles.BodyText
                            textStyle.fontSize: FontSize.PercentageValue
                            textStyle.fontSizeValue: ListItemData.cols > 2 ? 70 : 78
                        }
                        Label {
                            visible: ListItemData.cols > 1
                            leftMargin: ui.du(1.5)
                            layoutProperties: StackLayoutProperties {
                                spaceQuota: ListItemData.cols == 2 ? 2.4 : 1
                            }
                            text: ListItemData.cols > 1 ? "<html>" + ListItemData.cells[1] + "</html>" : ""
                            textFormat: TextFormat.Html
                            multiline: true
                            textStyle.color: ListItemData.header ? Color.create("#9a9a9a") : Color.create("#d6d6d6")
                            textStyle.fontWeight: ListItemData.header ? FontWeight.Bold : FontWeight.Normal
                            textStyle.base: SystemDefaults.TextStyles.BodyText
                            textStyle.fontSize: FontSize.PercentageValue
                            textStyle.fontSizeValue: ListItemData.cols > 2 ? 70 : 78
                        }
                        Label {
                            visible: ListItemData.cols > 2
                            leftMargin: ui.du(1.5)
                            layoutProperties: StackLayoutProperties {
                                spaceQuota: 1
                            }
                            text: ListItemData.cols > 2 ? "<html>" + ListItemData.cells[2] + "</html>" : ""
                            textFormat: TextFormat.Html
                            multiline: true
                            textStyle.color: ListItemData.header ? Color.create("#9a9a9a") : Color.create("#d6d6d6")
                            textStyle.fontWeight: ListItemData.header ? FontWeight.Bold : FontWeight.Normal
                            textStyle.base: SystemDefaults.TextStyles.BodyText
                            textStyle.fontSize: FontSize.PercentageValue
                            textStyle.fontSizeValue: 70
                        }
                        Label {
                            visible: ListItemData.cols > 3
                            leftMargin: ui.du(1.5)
                            layoutProperties: StackLayoutProperties {
                                spaceQuota: 1
                            }
                            text: ListItemData.cols > 3 ? "<html>" + ListItemData.cells[3] + "</html>" : ""
                            textFormat: TextFormat.Html
                            multiline: true
                            textStyle.color: ListItemData.header ? Color.create("#9a9a9a") : Color.create("#d6d6d6")
                            textStyle.fontWeight: ListItemData.header ? FontWeight.Bold : FontWeight.Normal
                            textStyle.base: SystemDefaults.TextStyles.BodyText
                            textStyle.fontSize: FontSize.PercentageValue
                            textStyle.fontSizeValue: 70
                        }
                    }
                }
            },
            ListItemComponent {
                type: "status"
                Container {
                    id: statusRoot
                    preferredWidth: statusRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(4)
                    topPadding: ui.du(2)
                    layout: StackLayout {
                        orientation: LayoutOrientation.LeftToRight
                    }
                    ActivityIndicator {
                        running: true
                        preferredWidth: ui.du(3.5)
                        preferredHeight: ui.du(3.5)
                        verticalAlignment: VerticalAlignment.Center
                    }
                    Label {
                        text: ListItemData.text
                        leftMargin: ui.du(1.5)
                        verticalAlignment: VerticalAlignment.Center
                        textStyle.color: Color.create("#9a9a9a")
                        textStyle.base: SystemDefaults.TextStyles.BodyText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: 78
                    }
                }
            },
            ListItemComponent {
                type: "meta"
                Container {
                    id: metaRoot
                    preferredWidth: metaRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(4)
                    topPadding: ui.du(0.5)
                    bottomPadding: ui.du(1)
                    Label {
                        text: ListItemData.text
                        textStyle.color: Color.create("#6f6f6f")
                        textStyle.base: SystemDefaults.TextStyles.SmallText
                    }
                }
            },
            ListItemComponent {
                type: "sources"
                Container {     // "N sources ›" chip
                    id: srcRoot
                    preferredWidth: srcRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(4)
                    topPadding: ui.du(1.5)
                    bottomPadding: ui.du(0.5)
                    Container {
                        background: srcRoot.ListItem.active ? Color.create("#6B52A8") : Color.create("#1e1e1e")
                        leftPadding: ui.du(1.5)
                        rightPadding: ui.du(2)
                        topPadding: ui.du(1)
                        bottomPadding: ui.du(1)
                        layout: StackLayout {
                            orientation: LayoutOrientation.LeftToRight
                        }
                        ImageView {
                            imageSource: "asset:///ic-translate.png"
                            preferredWidth: ui.du(3)
                            preferredHeight: ui.du(3)
                            verticalAlignment: VerticalAlignment.Center
                        }
                        Label {
                            text: ListItemData.text
                            leftMargin: ui.du(1.5)
                            verticalAlignment: VerticalAlignment.Center
                            textStyle.color: Color.create("#dddddd")
                            textStyle.base: SystemDefaults.TextStyles.BodyText
                            textStyle.fontSize: FontSize.PercentageValue
                            textStyle.fontSizeValue: 78
                        }
                        Label {
                            text: ListItemData.open ? "hide" : "\u203a"
                            leftMargin: ui.du(1.5)
                            verticalAlignment: VerticalAlignment.Center
                            textStyle.color: Color.create("#9a9a9a")
                            textStyle.base: SystemDefaults.TextStyles.BodyText
                        }
                    }
                }
            },
            ListItemComponent {
                type: "source"
                Container {     // one source: title + site; tap opens it in the browser
                    id: rowRoot
                    preferredWidth: rowRoot.ListItem.view.itemWidth
                    navigation.focusPolicy: NavigationFocusPolicy.NotFocusable
                    leftPadding: ui.du(5)
                    rightPadding: ui.du(4)
                    topPadding: ui.du(1)
                    bottomPadding: ui.du(1)
                    background: rowRoot.ListItem.active ? Color.create("#2a2a2a") : Color.Transparent
                    Label {
                        text: ListItemData.text
                        multiline: true
                        textStyle.color: Color.create("#b9a6f0")
                        textStyle.base: SystemDefaults.TextStyles.BodyText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: 76
                    }
                    Label {
                        text: ListItemData.label
                        topMargin: 0
                        textStyle.color: Color.create("#7a7a7a")
                        textStyle.base: SystemDefaults.TextStyles.SmallText
                    }
                }
            },
            ListItemComponent {
                type: "error"
                Container {
                    id: errRoot
                    preferredWidth: errRoot.ListItem.view.itemWidth
                    leftPadding: ui.du(4)
                    rightPadding: ui.du(4)
                    topPadding: ui.du(2)
                    Label {
                        text: ListItemData.text
                        multiline: true
                        textStyle.color: Color.create("#ff8a80")
                        textStyle.base: SystemDefaults.TextStyles.BodyText
                        textStyle.fontSize: FontSize.PercentageValue
                        textStyle.fontSizeValue: 80
                    }
                    FocusFrame {
                        target: retryButton
                        horizontalAlignment: HorizontalAlignment.Left
                        Button {
                            id: retryButton
                            navigation.defaultHighlightEnabled: false
                            text: "Try again"
                            onClicked: errRoot.ListItem.view.requestRetry()
                        }
                    }
                }
            }
        ]
    }

    Container {
        horizontalAlignment: HorizontalAlignment.Fill
        leftPadding: ui.du(4)
        rightPadding: ui.du(4)
        topPadding: ui.du(1)
        AskField {
            id: followField
            hint: "Ask a follow-up…"
            compact: true
            attachment: screen.pendingImage
            onAttachmentRemoved: screen.pendingImage = ""
            onSubmitted: {
                if (text == "" && screen.pendingImage == "") return;
                screen.followUp(text);
                followField.clear();
            }
        }
    }
}
