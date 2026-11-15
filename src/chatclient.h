// Streaming OpenAI-style Chat Completions client (OpenCode Go or any compatible server), with
// optional web search: the model gets a `web_search` function tool; when it calls it, we run the
// queries on Tavily (api.tavily.com) in parallel, hand the results back as tool messages and stream
// the final answer. (OpenCode Go strips the providers' built-in search tools but passes function
// tools through.) Searches go through libcurl (src/httpjob.h): Qt 4's TLS can't
// reach api.tavily.com. Exposed to QML as context property "chat".
#ifndef OPAL_CHATCLIENT_H
#define OPAL_CHATCLIENT_H

#include <QObject>
#include <QElapsedTimer>
#include <QList>
#include <QMap>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QSslError>
#include <QtScript/QScriptEngine>

class Opal;
class HttpJob;

class ChatClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
public:
    ChatClient(Opal *app, QObject *parent = 0);
    bool busy() const { return m_active; }

    // messages: [{role: "user"|"assistant", text: "...", image: "/path.jpg" (optional)}]
    // session: stable id for this conversation (x-opencode-session header).
    Q_INVOKABLE void send(const QVariantList &messages, const QString &session);
    Q_INVOKABLE void cancel();

signals:
    void busyChanged();
    void thinking();                       // model streams reasoning (shown as "Thinking…")
    void delta(const QString &text);       // answer text as it arrives
    void searching(const QString &queries);    // a search round started (answer text so far is discarded)
    void notice(const QString &message);   // non-fatal problem worth a toast (e.g. search failed)
    // sources: [{title, url}] from the web searches used for this answer (may be empty)
    // tokensIn/Out: totals over all rounds of this question (search rounds included), -1 if unknown
    void finished(const QString &text, const QString &model, const QString &finishReason, const QVariantList &sources,
                  int tokensIn, int tokensOut);
    void failed(const QString &message, const QString &detail);

private slots:
    void onReadyRead();
    void onFinished();
    void onSslErrors(const QList<QSslError> &errors);
    void onStall();
    void onSearchFinished();

private:
    struct ToolCall { QString id, name, args; };

    QNetworkRequest jsonRequest(const QUrl &url) const;
    bool searchEnabled() const;
    QString systemPrompt() const;
    void startRound();
    void handleLine(const QByteArray &line);
    void runSearches();
    void finishSearchRound();
    void fail(const QString &message, const QString &detail);
    void setActive(bool active);
    QString friendlyError(int status, const QString &body) const;

    Opal *m_app;
    QNetworkAccessManager m_net;
    QNetworkReply *m_reply;                // the current chat stream
    QList<HttpJob *> m_searches;           // Tavily requests in flight (curl worker threads)
    QScriptEngine m_engine;
    QTimer m_stall;
    QElapsedTimer m_clock;                 // whole question, all rounds
    QByteArray m_buf;
    QString m_text, m_model, m_finish, m_streamError, m_session;
    QStringList m_msgs;                    // JSON message objects for the request, grows with tool rounds
    QList<ToolCall> m_calls;               // tool calls of the current round (streamed in pieces)
    QMap<QString, QString> m_toolResults;  // tool_call_id -> result text
    QVariantList m_sources;
    QStringList m_seenUrls;
    int m_round;                           // completed search rounds
    int m_roundIn, m_roundOut;             // usage reported for the current round (-1 = none yet)
    int m_totalIn, m_totalOut;             // summed over the question's rounds (-1 = never reported)
    qint64 m_firstText;
    int m_events;
    bool m_active, m_thinkingSent, m_cancelled, m_stalled, m_noticeSent;
};

#endif
