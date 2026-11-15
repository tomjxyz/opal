// Minimal JSON for Qt 4.8 (no QJsonDocument): parse via QtScript's JSON.parse,
// serialise QVariant (map/list/string/number/bool/null) by hand.
#ifndef OPAL_JSON_H
#define OPAL_JSON_H

#include <QString>
#include <QVariant>

namespace Json {
// Returns an invalid QVariant and sets *ok=false on a syntax error.
QVariant parse(const QString &text, bool *ok = 0);
QString stringify(const QVariant &v);
QString quote(const QString &s);   // a JSON string literal, with quotes
}

#endif
