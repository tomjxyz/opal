// App-wide services exposed to QML as context property "opal":
// settings, logging, the provider's model list, clipboard, export.
#ifndef OPAL_OPAL_H
#define OPAL_OPAL_H

#include <QObject>
#include <QElapsedTimer>
#include <QFile>
#include <QStringList>
#include <QVariant>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>

class Opal : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(bool modelsBusy READ modelsBusy NOTIFY modelsBusyChanged)
public:
    explicit Opal(QObject *parent = 0);

    static const char *userAgent();
    QString version() const;
    bool modelsBusy() const { return m_modelsReply != 0; }

    // ---- logging: stdout (logs/log), data/opal.log, and the `logged` signal
    Q_INVOKABLE void log(const QString &msg);
    Q_INVOKABLE QString logTail(int lines) const;
    Q_INVOKABLE void clearLog();

    // ---- settings (data/settings.ini). Keys: base, key, model, quick ("1"/"0"), ignoreSsl
    Q_INVOKABLE QString setting(const QString &key) const;
    Q_INVOKABLE void setSetting(const QString &key, const QString &value);
    QString baseUrl() const;                 // without trailing slash
    // The built-in system prompt; setting("systemPrompt") returns it when the user hasn't changed it.
    Q_INVOKABLE QString defaultSystemPrompt() const;
    QString effortFor(const QString &model) const;   // "" = don't send reasoning_effort

    // ---- models: GET <base>/models, cached in data/models.json
    Q_INVOKABLE void refreshModels();
    Q_INVOKABLE QVariantList imageModels() const;   // [{id, name, price}]
    Q_INVOKABLE void fillModelDropDown(QObject *dropDown);

    // ---- misc
    Q_INVOKABLE void copyText(const QString &text);
    Q_INVOKABLE void openUrl(const QString &url);     // in the phone's browser (web search sources)
    // Writes Documents/Opal/<title> <date>.<ext>; returns the path or "".
    Q_INVOKABLE QString exportText(const QString &title, const QString &text, const QString &ext = "md");
    Q_INVOKABLE void logSystemInfo();
    // Emit later(tag) after ms milliseconds (QML has no timer here). Used e.g. to focus a field
    // once a screen is really shown; focusing during a screen switch or at startup is ignored.
    Q_INVOKABLE void callLater(int ms, const QString &tag);

signals:
    void logged(const QString &line);
    void modelsBusyChanged();
    void modelsUpdated(bool ok, const QString &message);
    void backgrounded();                   // app minimised / screen off: release the camera
    void foregrounded();
    void later(const QString &tag);

private slots:
    void onModelsFinished();
    void onLaterTimeout();

private:
    QVariantList readModelCache() const;

    QFile m_logFile;
    QElapsedTimer m_clock;
    QNetworkAccessManager m_net;
    QNetworkReply *m_modelsReply;
};

#endif
