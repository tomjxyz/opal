// Chat history on disk: data/chats/<id>.json per chat + data/chats/index.json for lists.
// Exposed to QML as context property "history".
//
// Chat object (QVariantMap, also what QML passes around):
//   { id, title, session, created (ms since epoch), updated,
//     messages: [ { role: "user"|"assistant", text, image?, model?, time } ] }
#ifndef OPAL_HISTORY_H
#define OPAL_HISTORY_H

#include <QObject>
#include <QVariant>

class Opal;

class History : public QObject {
    Q_OBJECT
public:
    History(Opal *app, QObject *parent = 0);

    Q_INVOKABLE QVariantMap create();                 // new empty chat with id + session
    Q_INVOKABLE QVariantList list() const;            // index entries, newest first: {id,title,updated,image}
    Q_INVOKABLE QVariantMap load(const QString &id) const;
    Q_INVOKABLE void save(const QVariantMap &chat);
    Q_INVOKABLE void remove(const QString &id);

signals:
    void changed();

private:
    QString dir() const;
    QVariantList readIndex() const;
    void writeIndex(const QVariantList &index) const;
    Opal *m_app;
};

#endif
