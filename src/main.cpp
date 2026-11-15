// Opal: a Lens-style AI assistant for the BlackBerry Classic.
#include <bb/cascades/AbstractPane>
#include <bb/cascades/Application>
#include <bb/cascades/Page>
#include <bb/cascades/QmlDocument>
#include <bb/cascades/ScrollView>
#include <bb/cascades/TextArea>
#include <bb/system/SystemToast>
#include <bb/cascades/multimedia/Camera>
#include <bb/cascades/multimedia/CameraTypes.hpp>
#include <bb/cascades/pickers/FilePicker>
#include <bb/cascades/pickers/FilePickerMode>
#include <bb/cascades/pickers/FileType>
#include <bb/cascades/TrackpadHandler>
#include <bb/cascades/TrackpadEventType>
#include <bb/cascades/ConsumeTrackpadEvent>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QThread>
#include <QtDeclarative/QDeclarativeError>
#include <QtDeclarative/qdeclarative.h>
#include <QtNetwork/QSslConfiguration>
#include <stdio.h>
#include <curl/curl.h>

#include "chatclient.h"
#include "crashlog.h"
#include "history.h"
#include "imagetool.h"
#include "opal.h"

using namespace bb::cascades;

static Opal *g_opal = 0;

// Route Qt/QML warnings (QML errors, console.log) into Opal's log; otherwise they only reach slog2.
static void msgHandler(QtMsgType type, const char *msg)
{
    const char *tag = type == QtDebugMsg ? "qt" : type == QtWarningMsg ? "qt-warning"
                    : type == QtCriticalMsg ? "qt-critical" : "qt-fatal";
    fprintf(stderr, "%s: %s\n", tag, msg);
    if (g_opal && QCoreApplication::instance() && QThread::currentThread() == QCoreApplication::instance()->thread())
        g_opal->log(QString("%1: %2").arg(tag, QString::fromUtf8(msg)));
    if (type == QtFatalMsg) abort();
}

// Loading the system CA store takes ~4.5 s on the Classic and Qt does it on the first
// HTTPS request. Do it once in the background at startup so the first question is fast.
class SslWarmup : public QThread {
public:
    qint64 ms;
    SslWarmup() : ms(-1) {}
protected:
    void run() {
        QElapsedTimer t;
        t.start();
        QSslConfiguration::defaultConfiguration();
        ms = t.elapsed();
        fprintf(stdout, "ssl warm-up: CA store loaded in %lld ms\n", (long long)ms);
    }
};

Q_DECL_EXPORT int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    crashlog_install();
    qInstallMsgHandler(msgHandler);
    curl_global_init(CURL_GLOBAL_ALL);     // once, before any thread uses curl (web search, src/httpjob.cpp)
    Application app(argc, argv);

    qmlRegisterType<bb::system::SystemToast>("bb.system", 1, 2, "SystemToast");
    {
        using namespace bb::cascades::multimedia;
        qmlRegisterType<Camera>("bb.cascades.multimedia", 1, 0, "Camera");
        qmlRegisterUncreatableType<CameraUnit>("bb.cascades.multimedia", 1, 0, "CameraUnit", "enum");
        qmlRegisterUncreatableType<CameraError>("bb.cascades.multimedia", 1, 0, "CameraError", "enum");
    }
    {
        using namespace bb::cascades::pickers;
        qmlRegisterType<FilePicker>("bb.cascades.pickers", 1, 0, "FilePicker");
        qmlRegisterUncreatableType<FilePickerMode>("bb.cascades.pickers", 1, 0, "FilePickerMode", "enum");
        qmlRegisterUncreatableType<FileType>("bb.cascades.pickers", 1, 0, "FileType", "enum");
    }
    // Trackpad types (10.3.1) under our own module, imported qualified in QML ("as Helpers"), so the
    // UI loads even if a firmware doesn't expose them from bb.cascades.
    qmlRegisterType<bb::cascades::TrackpadHandler>("opal.helpers", 1, 0, "TrackpadHandler");
    qmlRegisterUncreatableType<bb::cascades::TrackpadEventType>("opal.helpers", 1, 0, "TrackpadEventType", "enum");
    qmlRegisterUncreatableType<bb::cascades::ConsumeTrackpadEvent>("opal.helpers", 1, 0, "ConsumeTrackpadEvent", "enum");

    Opal *opal = new Opal(&app);
    g_opal = opal;
    opal->logSystemInfo();
    History *history = new History(opal, &app);
    ChatClient *chat = new ChatClient(opal, &app);
    ImageTool *images = new ImageTool(opal, &app);
    QObject::connect(&app, SIGNAL(thumbnail()), opal, SIGNAL(backgrounded()));
    QObject::connect(&app, SIGNAL(invisible()), opal, SIGNAL(backgrounded()));
    QObject::connect(&app, SIGNAL(fullscreen()), opal, SIGNAL(foregrounded()));

    SslWarmup *warm = new SslWarmup;
    QObject::connect(warm, SIGNAL(finished()), warm, SLOT(deleteLater()));
    warm->start(QThread::LowPriority);

    QmlDocument *qml = QmlDocument::create("asset:///main.qml").parent(&app);
    qml->setContextProperty("opal", opal);
    qml->setContextProperty("history", history);
    qml->setContextProperty("chat", chat);
    qml->setContextProperty("images", images);
    AbstractPane *root = qml->hasErrors() ? 0 : qml->createRootObject<AbstractPane>();
    if (!root) {
        QString report = "Opal's UI failed to load:\n";
        foreach (const QDeclarativeError &e, qml->errors()) report += e.toString() + "\n";
        opal->log("FATAL: " + report);
        TextArea *ta = TextArea::create().text(report + "\nAlso in data/opal.log");
        ta->setEditable(false);
        app.setScene(Page::create().content(ScrollView::create(ta)));
    } else {
        app.setScene(root);
    }
    return Application::exec();
}
