#include "opal.h"
#include "json.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QSettings>
#include <QTextStream>
#include <QTime>
#include <QTimer>
#include <QUrl>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QSslConfiguration>
#include <QtNetwork/QSslSocket>
#include <bb/cascades/DropDown>
#include <bb/cascades/Option>
#include <bb/platform/PlatformInfo>
#include <bb/system/Clipboard>
#include <bb/system/InvokeManager>
#include <bb/system/InvokeRequest>
#include <bb/system/InvokeTargetReply>
#include <openssl/crypto.h>
#include <stdio.h>

static const char *DEFAULT_BASE = "https://opencode.ai/inference/go/v1";
static const char *DEFAULT_MODEL = "claude-haiku-5-5";
#define OPAL_VERSION "1.0.0"          // also in bar-descriptor.xml <versionNumber>
static const char *VERSION = OPAL_VERSION;
// Default system prompt. The '# ' title line is what AnswerScreen.qml
// shows as the answer's title; the rest is rendered as markdown (lists, tables, code, quotes, bold,
// italic, links).
static const char *SYSTEM_PROMPT =
    "You are Opal, a helpful assistant inside a BlackBerry Classic app.\n"
    "Your first line should have '# ' followed by a short title for the answer.";

static const qint64 LOG_MAX = 512 * 1024;   // trim data/opal.log beyond this at startup

static QString settingsPath() { return QDir::homePath() + "/settings.ini"; }
static QString modelsPath() { return QDir::homePath() + "/models.json"; }

Opal::Opal(QObject *parent) : QObject(parent), m_modelsReply(0)
{
    m_clock.start();
    const QString path = QDir::homePath() + "/opal.log";
    QFileInfo fi(path);
    if (fi.exists() && fi.size() > LOG_MAX) {
        // Keep the newest half.
        QFile old(path);
        if (old.open(QIODevice::ReadOnly)) {
            old.seek(fi.size() - LOG_MAX / 2);
            QByteArray tail = old.readAll();
            old.close();
            int nl = tail.indexOf('\n');
            if (nl >= 0) tail = tail.mid(nl + 1);
            if (old.open(QIODevice::WriteOnly | QIODevice::Truncate)) { old.write(tail); old.close(); }
        }
    }
    m_logFile.setFileName(path);
    m_logFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
    log(QString("==== Opal %1 start %2 ====").arg(VERSION, QDateTime::currentDateTime().toString(Qt::ISODate)));
}

const char *Opal::userAgent() { return "Opal-BB10/" OPAL_VERSION; }
QString Opal::version() const { return QString::fromLatin1(VERSION); }

void Opal::log(const QString &msg)
{
    const qint64 ms = m_clock.elapsed();
    const QString line = QString("%1 [%2.%3] %4")
                             .arg(QTime::currentTime().toString("HH:mm:ss"))
                             .arg(ms / 1000, 4).arg(ms % 1000, 3, 10, QChar('0'))
                             .arg(msg);
    const QByteArray utf8 = line.toUtf8();
    fprintf(stdout, "%s\n", utf8.constData());
    if (m_logFile.isOpen()) {
        m_logFile.write(utf8);
        m_logFile.write("\n");
        m_logFile.flush();
    }
    emit logged(line);
}

QString Opal::logTail(int lines) const
{
    QFile f(m_logFile.fileName());
    if (!f.open(QIODevice::ReadOnly)) return QString();
    const qint64 size = f.size();
    f.seek(size > 128 * 1024 ? size - 128 * 1024 : 0);
    QStringList all = QString::fromUtf8(f.readAll()).split('\n', QString::SkipEmptyParts);
    if (all.size() > lines) all = all.mid(all.size() - lines);
    return all.join("\n");
}

void Opal::clearLog()
{
    m_logFile.close();
    m_logFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text);
    log("log cleared");
}

QString Opal::setting(const QString &key) const
{
    QSettings s(settingsPath(), QSettings::IniFormat);
    QString def;
    if (key == "base") def = DEFAULT_BASE;
    else if (key == "model") def = DEFAULT_MODEL;
    else if (key == "quick") def = "1";
    else if (key == "ignoreSsl") def = "0";
    else if (key == "search") def = "1";
    else if (key == "systemPrompt") def = QString::fromUtf8(SYSTEM_PROMPT);
    const QString v = s.value(key, def).toString();
    return v.isEmpty() && (key == "base" || key == "model" || key == "systemPrompt") ? def : v;
}

void Opal::setSetting(const QString &key, const QString &valueIn)
{
    QString value = valueIn;
    // An unchanged (or reset) prompt is stored as "" so future default improvements still apply.
    if (key == "systemPrompt" && value.trimmed() == defaultSystemPrompt().trimmed()) value = QString();
    {
        QSettings current(settingsPath(), QSettings::IniFormat);
        if (current.value(key).toString() == value && (current.contains(key) || value.isEmpty())) return;
    }
    QSettings s(settingsPath(), QSettings::IniFormat);
    s.setValue(key, value);
    s.sync();
    if (key == "key" || key == "tavilyKey") log(QString("settings: %1 changed (%2 chars)").arg(key == "key" ? "API key" : "Tavily key").arg(value.size()));
    else if (key == "systemPrompt") log(value.isEmpty() ? QString("settings: system prompt reset to default")
                                                        : QString("settings: system prompt changed (%1 chars)").arg(value.size()));
    else log(QString("settings: %1 = %2").arg(key, value));
}

QString Opal::defaultSystemPrompt() const { return QString::fromUtf8(SYSTEM_PROMPT); }

QString Opal::baseUrl() const
{
    QString b = setting("base").trimmed();
    while (b.endsWith('/')) b.chop(1);
    return b;
}

QString Opal::effortFor(const QString &model) const
{
    if (setting("quick") != "1") return QString();
    // Lowest effort the model advertises (from the cached /models metadata).
    static const char *order[] = { "none", "minimal", "low", "medium", "high", 0 };
    foreach (const QVariant &v, readModelCache()) {
        const QVariantMap m = v.toMap();
        if (m.value("id").toString() != model) continue;
        const QVariantList efforts = m.value("efforts").toList();
        QStringList e;
        foreach (const QVariant &x, efforts) e << x.toString();
        for (int i = 0; order[i]; i++)
            if (e.contains(order[i])) return QString::fromLatin1(order[i]);
        return QString();
    }
    return QString();
}

// ---------------------------------------------------------------- models

void Opal::refreshModels()
{
    if (m_modelsReply) return;
    QNetworkRequest req(QUrl(baseUrl() + "/models"));
    QSslConfiguration conf = QSslConfiguration::defaultConfiguration();
    conf.setProtocol(QSsl::SecureProtocols);
    req.setSslConfiguration(conf);
    req.setRawHeader("User-Agent", userAgent());
    const QString key = setting("key").trimmed();
    if (!key.isEmpty()) req.setRawHeader("Authorization", "Bearer " + key.toLatin1());
    log("models: GET " + baseUrl() + "/models");
    m_modelsReply = m_net.get(req);
    connect(m_modelsReply, SIGNAL(finished()), this, SLOT(onModelsFinished()));
    emit modelsBusyChanged();
}

void Opal::onModelsFinished()
{
    QNetworkReply *r = m_modelsReply;
    m_modelsReply = 0;
    r->deleteLater();
    emit modelsBusyChanged();
    const int status = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray body = r->readAll();
    if (r->error() != QNetworkReply::NoError || status != 200) {
        log(QString("models: failed, HTTP %1, %2").arg(status).arg(r->errorString()));
        emit modelsUpdated(false, status ? QString("Model list failed (HTTP %1)").arg(status) : "Couldn't reach the server");
        return;
    }
    bool ok = false;
    const QVariantList data = Json::parse(QString::fromUtf8(body), &ok).toMap().value("data").toList();
    if (!ok || data.isEmpty()) {
        log("models: response had no data[]");
        emit modelsUpdated(false, "The server's model list was empty or unreadable");
        return;
    }
    QVariantList cache;
    int images = 0;
    foreach (const QVariant &v, data) {
        const QVariantMap m = v.toMap();
        bool image = false;
        foreach (const QVariant &in, m.value("modalities").toMap().value("input").toList())
            if (in.toString().startsWith("image")) image = true;
        QVariantMap c;
        c["id"] = m.value("id");
        c["name"] = m.value("name").toString().isEmpty() ? m.value("id") : m.value("name");
        c["image"] = image;
        c["efforts"] = m.value("capabilities").toMap().value("reasoning").toMap().value("effort");
        const QVariantMap text = m.value("cost").toMap().value("text").toMap();
        c["in"] = text.value("input").toMap().value("price");
        c["out"] = text.value("output").toMap().value("price");
        cache << c;
        if (image) images++;
    }
    QFile f(modelsPath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) f.write(Json::stringify(cache).toUtf8());
    log(QString("models: %1 models, %2 accept images").arg(cache.size()).arg(images));
    emit modelsUpdated(true, QString("%1 models, %2 accept photos").arg(cache.size()).arg(images));
}

QVariantList Opal::readModelCache() const
{
    QFile f(modelsPath());
    if (!f.open(QIODevice::ReadOnly)) return QVariantList();
    return Json::parse(QString::fromUtf8(f.readAll())).toList();
}

QVariantList Opal::imageModels() const
{
    QVariantList out;
    foreach (const QVariant &v, readModelCache()) {
        const QVariantMap m = v.toMap();
        if (!m.value("image").toBool()) continue;
        QVariantMap o;
        o["id"] = m.value("id");
        o["name"] = m.value("name");
        const QVariant in = m.value("in"), outp = m.value("out");
        o["price"] = in.isValid() ? QString("$%1 / $%2 per M tokens").arg(in.toString(), outp.toString()) : QString();
        out << o;
    }
    return out;
}

void Opal::fillModelDropDown(QObject *obj)
{
    bb::cascades::DropDown *dd = qobject_cast<bb::cascades::DropDown *>(obj);
    if (!dd) { log("fillModelDropDown: not a DropDown"); return; }
    const QString current = setting("model");
    QVariantList models = imageModels();
    bool haveCurrent = false;
    foreach (const QVariant &v, models)
        if (v.toMap().value("id").toString() == current) haveCurrent = true;
    if (!haveCurrent) {   // e.g. before the first /models fetch
        QVariantMap m;
        m["id"] = current; m["name"] = current; m["price"] = QString();
        models.prepend(m);
    }
    dd->removeAll();
    foreach (const QVariant &v, models) {
        const QVariantMap m = v.toMap();
        bb::cascades::Option *o = bb::cascades::Option::create()
                                      .text(m.value("name").toString())
                                      .description(m.value("id").toString() + (m.value("price").toString().isEmpty() ? QString() : "  ·  " + m.value("price").toString()))
                                      .value(m.value("id"));
        dd->add(o);
        if (m.value("id").toString() == current) dd->setSelectedOption(o);
    }
}

// ---------------------------------------------------------------- misc

void Opal::openUrl(const QString &url)
{
    const QUrl u(url);
    if (!u.isValid() || (u.scheme() != "http" && u.scheme() != "https")) {
        log("openUrl: refusing " + url);
        return;
    }
    // One manager for the app's lifetime: the invocation completes asynchronously.
    static bb::system::InvokeManager *mgr = 0;
    if (!mgr) mgr = new bb::system::InvokeManager(this);
    bb::system::InvokeRequest req;
    req.setAction("bb.action.OPEN");
    req.setUri(u);
    bb::system::InvokeTargetReply *reply = mgr->invoke(req);
    log(QString("openUrl: %1 %2").arg(url).arg(reply ? "invoked" : "FAILED"));
    if (reply) connect(reply, SIGNAL(finished()), reply, SLOT(deleteLater()));
}

void Opal::copyText(const QString &text)
{
    bb::system::Clipboard cb;
    cb.clear();
    const bool ok = cb.insert("text/plain", text.toUtf8());
    log(QString("clipboard: %1 chars %2").arg(text.size()).arg(ok ? "copied" : "FAILED"));
}

QString Opal::exportText(const QString &title, const QString &text, const QString &extIn)
{
    QString ext = extIn.toLower();
    if (ext != "md" && ext != "txt") ext = "md";
    const QString dir = QDir::homePath() + "/../shared/documents/Opal";
    QDir().mkpath(dir);
    QString safe;
    foreach (QChar c, title.left(48))
        safe += (c.isLetterOrNumber() || c == ' ' || c == '-') ? c : QChar('_');
    safe = safe.trimmed();
    if (safe.isEmpty()) safe = "Opal chat";
    const QString path = QDir(dir).absoluteFilePath(
        safe + " " + QDateTime::currentDateTime().toString("yyyy-MM-dd HHmm") + "." + ext);
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        log("export: cannot write " + path);
        return QString();
    }
    f.write(text.toUtf8());
    f.close();
    log("export: wrote " + path);
    return path;
}

void Opal::logSystemInfo()
{
    bb::platform::PlatformInfo pi;
    // (No CA count here: QSslSocket::systemCaCertificates() takes ~4.5 s on the Classic.)
    log(QString("system: OS %1, Qt %2, %3, SSL %4")
            .arg(pi.osVersion(), qVersion(), SSLeay_version(SSLEAY_VERSION))
            .arg(QSslSocket::supportsSsl() ? "yes" : "NO"));
    log(QString("settings: web search %1").arg(setting("search") != "1" ? "off"
            : (setting("tavilyKey").isEmpty() ? "on but no Tavily key" : "on")));
    log(QString("settings: base %1, model %2, quick %3, key %4")
            .arg(baseUrl(), setting("model"), setting("quick"),
                 setting("key").isEmpty() ? "NOT SET" : "set"));
}

void Opal::callLater(int ms, const QString &tag)
{
    QTimer *t = new QTimer(this);
    t->setSingleShot(true);
    t->setProperty("tag", tag);
    connect(t, SIGNAL(timeout()), this, SLOT(onLaterTimeout()));
    t->start(ms);
}

void Opal::onLaterTimeout()
{
    QTimer *t = qobject_cast<QTimer *>(sender());
    if (!t) return;
    const QString tag = t->property("tag").toString();
    t->deleteLater();
    emit later(tag);
}
