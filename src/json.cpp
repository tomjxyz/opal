#include "json.h"

#include <QStringList>
#include <QtScript/QScriptEngine>
#include <QtScript/QScriptValue>

namespace Json {

QVariant parse(const QString &text, bool *ok)
{
    // One engine per thread would be faster, but parsing is rare (a few calls per
    // answer for history/models; SSE uses its own engine in ChatClient).
    QScriptEngine eng;
    QScriptValue parser = eng.globalObject().property("JSON").property("parse");
    QScriptValue v;
    if (parser.isFunction()) {
        v = parser.call(QScriptValue(), QScriptValueList() << QScriptValue(&eng, text));
    }   // (QtScript 4.8 always has JSON; without it, parsing simply fails rather than eval'ing)
    if (eng.hasUncaughtException() || !(v.isObject() || v.isArray())) {
        if (ok) *ok = false;
        eng.clearExceptions();
        return QVariant();
    }
    if (ok) *ok = true;
    return v.toVariant();
}

QString quote(const QString &s)
{
    QString o;
    o.reserve(s.size() + 2);
    o += QLatin1Char('"');
    for (int i = 0; i < s.size(); i++) {
        const QChar ch = s.at(i);
        const ushort u = ch.unicode();
        switch (u) {
        case '"': o += QLatin1String("\\\""); break;
        case '\\': o += QLatin1String("\\\\"); break;
        case '\n': o += QLatin1String("\\n"); break;
        case '\r': o += QLatin1String("\\r"); break;
        case '\t': o += QLatin1String("\\t"); break;
        default:
            if (u < 0x20) o += QString().sprintf("\\u%04x", u);
            else o += ch;
        }
    }
    o += QLatin1Char('"');
    return o;
}

QString stringify(const QVariant &v)
{
    switch (v.type()) {
    case QVariant::Invalid:
        return QLatin1String("null");
    case QVariant::Bool:
        return v.toBool() ? QLatin1String("true") : QLatin1String("false");
    case QVariant::Int: case QVariant::UInt: case QVariant::LongLong: case QVariant::ULongLong:
        return v.toString();
    case QVariant::Double: {
        double d = v.toDouble();
        if (d == (double)(qint64)d && d > -9e15 && d < 9e15) return QString::number((qint64)d);
        return QString::number(d, 'g', 15);
    }
    case QVariant::Map: {
        const QVariantMap m = v.toMap();
        QStringList parts;
        for (QVariantMap::const_iterator it = m.constBegin(); it != m.constEnd(); ++it)
            parts << quote(it.key()) + QLatin1Char(':') + stringify(it.value());
        return QLatin1Char('{') + parts.join(QLatin1String(",")) + QLatin1Char('}');
    }
    case QVariant::List: case QVariant::StringList: {
        const QVariantList l = v.toList();
        QStringList parts;
        foreach (const QVariant &e, l) parts << stringify(e);
        return QLatin1Char('[') + parts.join(QLatin1String(",")) + QLatin1Char(']');
    }
    default:
        if (v.canConvert<QVariantMap>() && !v.canConvert<QString>()) return stringify(v.toMap());
        return quote(v.toString());
    }
}

} // namespace Json
