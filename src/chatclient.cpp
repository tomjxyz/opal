#include "chatclient.h"
#include "httpjob.h"
#include "json.h"
#include "opal.h"

#include <QDate>
#include <QDir>
#include <QFile>
#include <QUrl>
#include <QtNetwork/QSslConfiguration>
#include <QtNetwork/QSslSocket>
#include <QtScript/QScriptValue>

static const int STALL_MS = 60000;        // abort if no bytes arrive for this long
static const int MAX_SEARCH_ROUNDS = 2;   // a confused model can't search forever
static const int MAX_SOURCES = 8;
static const char *TAVILY_URL = "https://api.tavily.com/search";

static const char *SEARCH_TOOL =
    "{\"type\":\"function\",\"function\":{\"name\":\"web_search\","
    "\"description\":\"Search the web for current or specific information: news, recent events, prices, "
    "schedules, opening hours, product details, sports results, anything after your training data or that "
    "you are unsure about. Not needed for general knowledge you are confident about.\","
    "\"parameters\":{\"type\":\"object\",\"properties\":{"
    "\"query\":{\"type\":\"string\",\"description\":\"A concise search query\"},"
    "\"topic\":{\"type\":\"string\",\"enum\":[\"general\",\"news\"],\"description\":\"Use news for recent events\"}},"
    "\"required\":[\"query\"]}}}";

ChatClient::ChatClient(Opal *app, QObject *parent)
    : QObject(parent), m_app(app), m_reply(0), m_round(0), m_roundIn(-1), m_roundOut(-1),
      m_totalIn(-1), m_totalOut(-1), m_firstText(-1), m_events(0),
      m_active(false), m_thinkingSent(false), m_cancelled(false), m_stalled(false), m_noticeSent(false)
{
    m_stall.setSingleShot(true);
    m_stall.setInterval(STALL_MS);
    connect(&m_stall, SIGNAL(timeout()), this, SLOT(onStall()));
}

QNetworkRequest ChatClient::jsonRequest(const QUrl &url) const
{
    QNetworkRequest req(url);
    QSslConfiguration conf = QSslConfiguration::defaultConfiguration();
    conf.setProtocol(QSsl::SecureProtocols);
    req.setSslConfiguration(conf);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader("User-Agent", Opal::userAgent());
    return req;
}

bool ChatClient::searchEnabled() const
{
    return m_app->setting("search") == "1" && !m_app->setting("tavilyKey").trimmed().isEmpty();
}

QString ChatClient::systemPrompt() const
{
    // The user's prompt (Settings), plus facts the model can't know: today's date, and the search tool.
    QString p = m_app->setting("systemPrompt");
    p += "\n\nToday is " + QDate::currentDate().toString("dddd d MMMM yyyy") + ".";
    if (searchEnabled())
        p += " You can use the web_search tool for current or specific facts (news, prices, schedules, recent "
             "events, anything you're unsure of); don't search for general knowledge. Use a few focused queries "
             "at once rather than many. Don't put URLs or citation markers like [1] in your answer: the app "
             "lists the sources under it.";
    return p;
}

void ChatClient::setActive(bool active)
{
    if (m_active == active) return;
    m_active = active;
    emit busyChanged();
}

void ChatClient::send(const QVariantList &messages, const QString &session)
{
    if (m_active) {
        m_app->log("chat: already busy, ignoring send");
        return;
    }
    if (m_app->setting("key").trimmed().isEmpty()) {
        emit failed("Add your API key in Settings first.", "no API key");
        return;
    }

    // Request messages, built by hand (Qt 4 has no JSON writer for nested image parts).
    m_msgs.clear();
    m_msgs << QString("{\"role\":\"system\",\"content\":%1}").arg(Json::quote(systemPrompt()));
    int images = 0;
    qint64 imageBytes = 0;
    foreach (const QVariant &mv, messages) {
        const QVariantMap m = mv.toMap();
        const QString role = m.value("role").toString() == "assistant" ? "assistant" : "user";
        const QString text = m.value("text").toString();
        const QString image = m.value("image").toString();
        if (!image.isEmpty() && role == "user") {
            QFile f(image);
            if (f.open(QIODevice::ReadOnly)) {
                const QByteArray b64 = f.readAll().toBase64();
                imageBytes += b64.size();
                images++;
                m_msgs << QString("{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":%1},"
                                  "{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/jpeg;base64,%2\"}}]}")
                              .arg(Json::quote(text), QString::fromLatin1(b64));
                continue;
            }
            m_app->log("chat: image missing, sending text only: " + image);
        }
        m_msgs << QString("{\"role\":\"%1\",\"content\":%2}").arg(role, Json::quote(text));
    }

    m_session = session;
    m_round = 0;
    m_totalIn = m_totalOut = -1;
    m_sources.clear();
    m_seenUrls.clear();
    m_cancelled = m_stalled = m_noticeSent = false;
    m_clock.start();
    m_app->log(QString("chat: question with %1 messages, %2 image(s) %3 KB, search %4")
                   .arg(messages.size()).arg(images).arg(imageBytes / 1024).arg(searchEnabled() ? "on" : "off"));
    setActive(true);
    startRound();
}

void ChatClient::startRound()
{
    const QString base = m_app->baseUrl();
    const QString model = m_app->setting("model").trimmed();
    QString body = QString("{\"model\":%1,\"stream\":true,\"max_tokens\":4000,").arg(Json::quote(model));
    const QString effort = m_app->effortFor(model);
    if (!effort.isEmpty()) body += QString("\"reasoning_effort\":%1,").arg(Json::quote(effort));
    // Keep offering the tool on later rounds too: providers reject tool messages without tool definitions.
    if (searchEnabled()) body += QString("\"tools\":[%1],").arg(QString::fromLatin1(SEARCH_TOOL));
    body += QString("\"messages\":[%1]}").arg(m_msgs.join(","));
    const QByteArray payload = body.toUtf8();

    QNetworkRequest req = jsonRequest(QUrl(base + "/chat/completions"));
    req.setRawHeader("Accept", "text/event-stream");
    req.setRawHeader("Authorization", "Bearer " + m_app->setting("key").trimmed().toLatin1());
    req.setRawHeader("x-opencode-session", m_session.toLatin1());

    m_buf.clear();
    m_text.clear();
    m_finish.clear();
    m_streamError.clear();
    m_calls.clear();
    m_roundIn = m_roundOut = -1;
    m_model = model;
    m_firstText = -1;
    m_events = 0;
    m_thinkingSent = false;

    m_app->log(QString("chat: POST %1/chat/completions model %2 effort %3, round %4, body %5 KB")
                   .arg(base, model, effort.isEmpty() ? "-" : effort).arg(m_round).arg(payload.size() / 1024));
    m_reply = m_net.post(req, payload);
    connect(m_reply, SIGNAL(readyRead()), this, SLOT(onReadyRead()));
    connect(m_reply, SIGNAL(finished()), this, SLOT(onFinished()));
    connect(m_reply, SIGNAL(sslErrors(QList<QSslError>)), this, SLOT(onSslErrors(QList<QSslError>)));
    m_stall.start();
}

void ChatClient::fail(const QString &message, const QString &detail)
{
    if (!m_active) return;
    m_stall.stop();
    setActive(false);
    emit failed(message, detail);
}

void ChatClient::cancel()
{
    if (!m_active) return;
    m_app->log("chat: cancelled by user");
    m_cancelled = true;
    if (m_reply) m_reply->abort();
    foreach (HttpJob *j, m_searches) j->abort();
    fail("Stopped.", "cancelled");
}

void ChatClient::onStall()
{
    if (!m_active) return;
    m_app->log(QString("chat: no data for %1 s, aborting").arg(STALL_MS / 1000));
    m_stalled = true;
    if (m_reply) m_reply->abort();
    foreach (HttpJob *j, m_searches) j->abort();
    fail("No response for a minute, so Opal gave up. Check your connection and try again.", "stall timeout");
}

void ChatClient::onSslErrors(const QList<QSslError> &errors)
{
    QNetworkReply *r = qobject_cast<QNetworkReply *>(sender());
    foreach (const QSslError &e, errors)
        m_app->log("chat: SSL error: " + e.errorString());
    if (m_app->setting("ignoreSsl") == "1" && r) {
        m_app->log("chat: ignoring SSL errors (Settings > Ignore SSL errors is on)");
        r->ignoreSslErrors();
    }
}

void ChatClient::onReadyRead()
{
    if (!m_reply) return;
    m_stall.start();
    m_buf += m_reply->readAll();
    const int status = m_reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (status >= 300) return;              // error body: keep it whole for onFinished
    int nl;
    while ((nl = m_buf.indexOf('\n')) >= 0) {
        QByteArray line = m_buf.left(nl);
        m_buf.remove(0, nl + 1);
        if (line.endsWith('\r')) line.chop(1);
        handleLine(line);
    }
}

void ChatClient::handleLine(const QByteArray &line)
{
    if (!line.startsWith("data:")) return;   // comments, event: lines, blank separators
    const QByteArray payload = line.mid(5).trimmed();
    if (payload.isEmpty() || payload == "[DONE]") return;
    m_events++;
    // JSON.parse, not evaluate(): server data must never run as script.
    QScriptValue parser = m_engine.globalObject().property("JSON").property("parse");
    QScriptValue v = parser.isFunction()
        ? parser.call(QScriptValue(), QScriptValueList() << QScriptValue(&m_engine, QString::fromUtf8(payload)))
        : QScriptValue();
    if (m_engine.hasUncaughtException() || !v.isObject()) {
        m_engine.clearExceptions();
        m_app->log("chat: unparsable SSE line: " + QString::fromUtf8(payload.left(200)));
        return;
    }
    QScriptValue err = v.property("error");
    if (err.isObject()) {
        m_streamError = err.property("message").toString();
        m_app->log("chat: error in stream: " + QString::fromUtf8(payload.left(400)));
        return;
    }
    QScriptValue model = v.property("model");
    if (model.isString() && !model.toString().isEmpty()) m_model = model.toString();
    QScriptValue choice = v.property("choices").property(0);
    QScriptValue dlt = choice.property("delta");
    QScriptValue reasoning = dlt.property("reasoning_content");
    if (!m_thinkingSent && reasoning.isString() && !reasoning.toString().isEmpty()) {
        m_thinkingSent = true;
        emit thinking();
    }
    QScriptValue content = dlt.property("content");
    if (content.isString() && !content.toString().isEmpty()) {
        if (m_firstText < 0) {
            m_firstText = m_clock.elapsed();
            m_app->log(QString("chat: first text after %1 ms").arg(m_firstText));
        }
        m_text += content.toString();
        emit delta(content.toString());
    }
    // Tool calls arrive in pieces: {index, id?, function: {name?, arguments: "partial json"}}.
    QScriptValue tcs = dlt.property("tool_calls");
    if (tcs.isArray()) {
        const int n = tcs.property("length").toInt32();
        for (int i = 0; i < n; i++) {
            QScriptValue tc = tcs.property(i);
            const int idx = tc.property("index").isNumber() ? tc.property("index").toInt32() : i;
            if (idx < 0 || idx > 15) continue;
            while (m_calls.size() <= idx) m_calls.append(ToolCall());
            ToolCall &c = m_calls[idx];
            if (tc.property("id").isString() && !tc.property("id").toString().isEmpty()) c.id = tc.property("id").toString();
            QScriptValue fn = tc.property("function");
            if (fn.property("name").isString() && !fn.property("name").toString().isEmpty()) c.name = fn.property("name").toString();
            if (fn.property("arguments").isString()) c.args += fn.property("arguments").toString();
        }
    }
    QScriptValue fr = choice.property("finish_reason");
    if (fr.isString()) m_finish = fr.toString();
    QScriptValue usage = v.property("usage");
    if (usage.isObject() && usage.property("prompt_tokens").isNumber()) {
        // Usually only in the last chunk; if repeated, the latest value for the round wins.
        m_roundIn = usage.property("prompt_tokens").toInt32();
        m_roundOut = usage.property("completion_tokens").isNumber() ? usage.property("completion_tokens").toInt32() : 0;
        m_app->log(QString("chat: usage prompt %1 / completion %2 tokens").arg(m_roundIn).arg(m_roundOut));
    }
}

QString ChatClient::friendlyError(int status, const QString &body) const
{
    QString msg;
    bool ok = false;
    const QVariantMap j = Json::parse(body, &ok).toMap();
    if (ok) {
        const QVariant e = j.value("error");
        msg = e.type() == QVariant::Map ? e.toMap().value("message").toString() : e.toString();
    }
    switch (status) {
    case 401: case 403: return "The API key was rejected. Check it in Settings.";
    case 404: return "The server doesn't know this model or URL. Check Settings." + (msg.isEmpty() ? QString() : "\n" + msg);
    case 429: return "Usage limit reached (OpenCode Go has 5-hour and weekly caps). Try again later." + (msg.isEmpty() ? QString() : "\n" + msg);
    default: break;
    }
    if (status == 502 || status == 503 || status == 504)
        return "The model's provider is unavailable right now (HTTP " + QString::number(status) + ")."
               + (msg.isEmpty() ? QString() : "\n" + msg)
               + "\nTry again, or pick another model in Settings.";
    if (status >= 500) return "The server had a problem (HTTP " + QString::number(status) + "). Try again."
                              + (msg.isEmpty() ? QString() : "\n" + msg);
    if (!msg.isEmpty()) return msg;
    return "Request failed (HTTP " + QString::number(status) + ").";
}

void ChatClient::onFinished()
{
    QNetworkReply *r = qobject_cast<QNetworkReply *>(sender());
    if (!r || r != m_reply) { if (r) r->deleteLater(); return; }
    m_buf += r->readAll();
    const int status = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QNetworkReply::NetworkError err = r->error();
    const QString errString = r->errorString();
    const qint64 ms = m_clock.elapsed();
    m_reply = 0;
    r->deleteLater();
    if (!m_active || m_cancelled || m_stalled) return;     // already reported

    if (status >= 200 && status < 300 && !m_buf.trimmed().isEmpty()) handleLine(m_buf.trimmed());
    if (m_roundIn >= 0) {       // add this round's usage to the question's total
        m_totalIn = qMax(0, m_totalIn) + m_roundIn;
        m_totalOut = qMax(0, m_totalOut) + qMax(0, m_roundOut);
        m_roundIn = m_roundOut = -1;
    }

    if (status == 0 || (err != QNetworkReply::NoError && status < 300)) {
        m_app->log(QString("chat: network error %1 (%2) after %3 ms").arg((int)err).arg(errString).arg(ms));
        QString msg = "Couldn't reach the server. Check your connection.";
        if (err == QNetworkReply::SslHandshakeFailedError) msg = "Secure connection failed (TLS). See Settings > View log.";
        fail(msg, errString);
        return;
    }
    if (status >= 300) {
        const QString body = QString::fromUtf8(m_buf.left(2000));
        m_app->log(QString("chat: HTTP %1 after %2 ms: %3").arg(status).arg(ms).arg(body.left(600)));
        fail(friendlyError(status, body), body.left(600));
        return;
    }
    if (!m_streamError.isEmpty() && m_text.isEmpty() && m_calls.isEmpty()) {
        fail(m_streamError, "error event in stream");
        return;
    }

    // The model asked to search: run the queries and go round again.
    if (!m_calls.isEmpty()) {
        if (m_round >= MAX_SEARCH_ROUNDS) {
            m_app->log("chat: model still wants to search after the limit; stopping");
            if (m_text.trimmed().isEmpty()) {
                fail("The model kept searching without answering. Try again or rephrase.", "search loop");
                return;
            }
        } else {
            m_round++;
            runSearches();
            return;
        }
    }

    m_app->log(QString("chat: done in %1 ms, %2 events, %3 chars, finish %4, model %5, %6 search round(s), %7 sources")
                   .arg(ms).arg(m_events).arg(m_text.size()).arg(m_finish.isEmpty() ? "-" : m_finish, m_model)
                   .arg(m_round).arg(m_sources.size()));
    if (m_text.trimmed().isEmpty()) {
        fail("The model returned an empty answer. Try again or pick another model in Settings.", "empty");
        return;
    }
    m_stall.stop();
    setActive(false);
    emit finished(m_text, m_model, m_finish, m_sources, m_totalIn, m_totalOut);
}

// ---------------------------------------------------------------- web search (Tavily)

void ChatClient::runSearches()
{
    // Record the assistant's tool-call turn exactly as the model sent it.
    QStringList callJson;
    for (int i = 0; i < m_calls.size(); i++) {
        ToolCall &c = m_calls[i];
        if (c.id.isEmpty()) c.id = QString("call_%1_%2").arg(m_round).arg(i);
        if (c.name.isEmpty()) c.name = "web_search";
        callJson << QString("{\"id\":%1,\"type\":\"function\",\"function\":{\"name\":%2,\"arguments\":%3}}")
                        .arg(Json::quote(c.id), Json::quote(c.name), Json::quote(c.args.isEmpty() ? QString("{}") : c.args));
    }
    m_msgs << QString("{\"role\":\"assistant\",\"content\":%1,\"tool_calls\":[%2]}")
                  .arg(m_text.isEmpty() ? QString("null") : Json::quote(m_text), callJson.join(","));

    m_toolResults.clear();
    // Parallel curl searches use OpenSSL 1.0.2 from several threads, which is only safe once its
    // locking callbacks are installed. Qt installs them when it loads its SSL support (normally
    // already done by the startup warm-up in main.cpp); this makes sure, and is free afterwards.
    QSslSocket::supportsSsl();
    QStringList queries;
    const QString key = m_app->setting("tavilyKey").trimmed();
    foreach (const ToolCall &c, m_calls) {
        if (c.name != "web_search") {
            m_toolResults[c.id] = "Unknown tool: " + c.name;
            continue;
        }
        bool ok = false;
        const QVariantMap a = Json::parse(c.args, &ok).toMap();
        QString query = ok ? a.value("query").toString().trimmed() : c.args.trimmed();
        const QString topic = a.value("topic").toString() == "news" ? "news" : "general";
        if (query.isEmpty()) {
            m_toolResults[c.id] = "Search failed: empty query.";
            continue;
        }
        if (query.size() > 300) query = query.left(300);
        queries << query;
        QString body = QString("{\"query\":%1,\"search_depth\":\"basic\",\"max_results\":5,\"topic\":%2,\"include_answer\":false")
                           .arg(Json::quote(query), Json::quote(topic));
        if (topic == "news") body += ",\"time_range\":\"week\"";
        body += "}";
        HttpJob *job = new HttpJob;
        job->url = QString::fromLatin1(TAVILY_URL);
        job->headers << "Content-Type: application/json" << ("Authorization: Bearer " + key.toLatin1())
                     << (QByteArray("User-Agent: ") + Opal::userAgent());
        job->body = body.toUtf8();
        job->caFile = QDir::currentPath() + "/app/native/assets/cacert.pem";
        job->verifyPeer = m_app->setting("ignoreSsl") != "1";
        job->tag["callId"] = c.id;
        job->tag["query"] = query;
        connect(job, SIGNAL(finished()), this, SLOT(onSearchFinished()));
        m_searches << job;
        job->start();
    }
    m_app->log(QString("search: round %1, %2 quer%3: %4").arg(m_round).arg(queries.size())
                   .arg(queries.size() == 1 ? "y" : "ies").arg(queries.join(" | ")));
    emit searching(queries.join(" · "));
    m_stall.start();
    if (m_searches.isEmpty()) finishSearchRound();
}

void ChatClient::onSearchFinished()
{
    QThread *t = qobject_cast<QThread *>(sender());
    if (!t) return;
    HttpJob *job = static_cast<HttpJob *>(t);
    m_searches.removeAll(job);
    job->deleteLater();
    if (!m_active || m_cancelled || m_stalled) return;

    const QString id = job->tag.value("callId").toString();
    const QString query = job->tag.value("query").toString();
    const int status = job->status;
    const QByteArray body = job->response;
    const qint64 ms = job->elapsedMs;

    QString problem;
    if (job->curlCode != 0 && status == 0) problem = "couldn't reach Tavily (" + job->error + ")";
    else if (status == 401 || status == 403) problem = "Tavily rejected the search key (check Settings)";
    else if (status == 429) problem = "Tavily rate limit reached";
    else if (status == 432 || status == 433) problem = "Tavily plan/credit limit reached";
    else if (status != 200) problem = QString("Tavily error HTTP %1").arg(status);

    QString result;
    if (problem.isEmpty()) {
        bool ok = false;
        const QVariantList results = Json::parse(QString::fromUtf8(body), &ok).toMap().value("results").toList();
        if (!ok) problem = "unreadable Tavily response";
        else {
            QStringList parts;
            int n = 0;
            foreach (const QVariant &v, results) {
                const QVariantMap m = v.toMap();
                const QString title = m.value("title").toString().trimmed();
                const QString url = m.value("url").toString().trimmed();
                QString content = m.value("content").toString().simplified();
                if (content.size() > 700) content = content.left(700) + "…";
                const QString date = m.value("published_date").toString();
                parts << QString("[%1] %2\n%3%4\n%5").arg(++n).arg(title, url,
                                                              date.isEmpty() ? QString() : "\nPublished: " + date, content);
                if (!url.isEmpty() && !m_seenUrls.contains(url) && m_sources.size() < MAX_SOURCES) {
                    m_seenUrls << url;
                    QVariantMap s;
                    s["title"] = title.isEmpty() ? url : title;
                    s["url"] = url;
                    m_sources << s;
                }
            }
            result = parts.isEmpty() ? QString("No results for \"%1\".").arg(query)
                                     : QString("Web results for \"%1\":\n\n%2").arg(query, parts.join("\n\n"));
            m_app->log(QString("search: \"%1\" -> %2 results in %3 ms").arg(query).arg(results.size()).arg(ms));
        }
    }
    if (!problem.isEmpty()) {
        m_app->log(QString("search: \"%1\" FAILED: %2 %3").arg(query, problem, QString::fromUtf8(body.left(300))));
        result = "Search failed: " + problem + ". Answer from your own knowledge and say briefly that the web search didn't work.";
        if (!m_noticeSent) {
            m_noticeSent = true;
            emit notice("Web search failed: " + problem);
        }
    }
    if (m_round >= MAX_SEARCH_ROUNDS) result += "\n\n(Search limit reached: answer now from these results.)";
    m_toolResults[id] = result;
    if (m_searches.isEmpty()) finishSearchRound();
}

void ChatClient::finishSearchRound()
{
    foreach (const ToolCall &c, m_calls)
        m_msgs << QString("{\"role\":\"tool\",\"tool_call_id\":%1,\"content\":%2}")
                      .arg(Json::quote(c.id), Json::quote(m_toolResults.value(c.id, "No result.")));
    m_calls.clear();
    startRound();
}
