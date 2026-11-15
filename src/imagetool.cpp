#include "imagetool.h"
#include "jpegtool.h"
#include "opal.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QThread>
#include <QUrl>
#include <bb/cascades/multimedia/Camera>
#include <bb/cascades/multimedia/CameraSettings>

static const int MAX_EDGE = 1024;   // lets libjpeg decode 8 MP photos at 1/2 scale
static const int QUALITY = 80;

namespace {
// Plain QThread (no Q_OBJECT needed): results are read back in ImageTool::onJobFinished().
class Job : public QThread {
public:
    QString in, out;
    double x, y, w, h, aspect;
    int rc;
    QString info;
protected:
    void run() {
        char buf[600];
        const QByteArray in8 = QFile::encodeName(in), out8 = QFile::encodeName(out);
        rc = jt_process(in8.constData(), out8.constData(), x, y, w, h, aspect, MAX_EDGE, QUALITY, buf, sizeof buf);
        info = QString::fromUtf8(buf);
    }
};
}

ImageTool::ImageTool(Opal *app, QObject *parent) : QObject(parent), m_app(app), m_busy(false)
{
    QDir().mkpath(QDir::homePath() + "/images");
}

void ImageTool::process(const QString &pathIn, double x, double y, double w, double h, double viewAspect)
{
    if (m_busy) {
        m_app->log("images: busy, ignoring");
        return;
    }
    QString path = pathIn;
    if (path.startsWith("file://")) path = QUrl(path).toLocalFile();
    Job *job = new Job;
    job->in = path;
    job->out = QDir::homePath() + "/images/" + QString::number(QDateTime::currentMSecsSinceEpoch(), 16) + ".jpg";
    job->x = x; job->y = y; job->w = w; job->h = h; job->aspect = viewAspect;
    job->rc = -1;
    m_app->log(QString("images: processing %1 (%2 KB), crop %3,%4 %5x%6 view-aspect %7")
                   .arg(path).arg(QFileInfo(path).size() / 1024)
                   .arg(x, 0, 'f', 3).arg(y, 0, 'f', 3).arg(w, 0, 'f', 3).arg(h, 0, 'f', 3).arg(viewAspect, 0, 'f', 3));
    connect(job, SIGNAL(finished()), this, SLOT(onJobFinished()));
    m_busy = true;
    emit busyChanged();
    job->start();
}

void ImageTool::onJobFinished()
{
    Job *job = static_cast<Job *>(sender());
    m_busy = false;
    emit busyChanged();
    m_app->log(QString("images: %1 %2").arg(job->rc == 0 ? "OK" : "FAILED").arg(job->info));
    if (job->rc == 0) emit processed(job->out);
    else emit processFailed("Couldn't read that photo (" + job->info + ")");
    job->deleteLater();
}

bool ImageTool::setFlash(QObject *obj, int mode)
{
    using namespace bb::cascades::multimedia;
    Camera *cam = qobject_cast<Camera *>(obj);
    if (!cam) { m_app->log("images: setFlash: not a Camera"); return false; }
    CameraSettings s;
    cam->getSettings(&s);
    s.setFlashMode((CameraFlashMode::Type)mode);
    const bool ok = cam->applySettings(&s);
    m_app->log(QString("camera: flash mode %1 %2").arg(mode).arg(ok ? "applied" : "FAILED"));
    return ok;
}

bool ImageTool::focusAt(QObject *obj, double fx, double fy)
{
    using namespace bb::cascades::multimedia;
    Camera *cam = qobject_cast<Camera *>(obj);
    if (!cam) return false;
    CameraSettings s;
    cam->getSettings(&s);
    const int before = (int)s.focusMode();
    s.setFocusMode(CameraFocusMode::Auto);
    const QSize res = s.captureResolution();
    QRect region;
    if (res.isValid() && fx >= 0 && fx <= 1 && fy >= 0 && fy <= 1) {
        const int w = qMax(16, res.width() / 8), h = qMax(16, res.height() / 8);
        int x = (int)(fx * res.width()) - w / 2, y = (int)(fy * res.height()) - h / 2;
        x = qBound(0, x, res.width() - w);
        y = qBound(0, y, res.height() - h);
        region = QRect(x, y, w, h);
        s.setFocusRegion(region);
    }
    bool ok = cam->applySettings(&s);
    QString how = region.isNull() ? QString("no region")
        : QString("region %1,%2 %3x%4 of %5x%6").arg(region.x()).arg(region.y()).arg(region.width())
              .arg(region.height()).arg(res.width()).arg(res.height());
    if (!ok && !region.isNull()) {          // region rejected: refocus without one
        CameraSettings plain;
        cam->getSettings(&plain);
        plain.setFocusMode(CameraFocusMode::Auto);
        ok = cam->applySettings(&plain);
        how += ok ? " REJECTED, refocused without region" : " REJECTED, plain refocus failed too";
    }
    m_app->log(QString("camera: tap focus at %1,%2 (mode was %3): %4 %5")
                   .arg(fx, 0, 'f', 2).arg(fy, 0, 'f', 2).arg(before).arg(how).arg(ok ? "applied" : "FAILED"));
    return ok;
}

bool ImageTool::continuousFocus(QObject *obj)
{
    using namespace bb::cascades::multimedia;
    Camera *cam = qobject_cast<Camera *>(obj);
    if (!cam) return false;
    CameraSettings s;
    cam->getSettings(&s);
    if (s.focusMode() == CameraFocusMode::ContinuousAuto) return true;
    s.setFocusMode(CameraFocusMode::ContinuousAuto);
    s.setFocusRegion(QRect());
    const bool ok = cam->applySettings(&s);
    m_app->log(QString("camera: continuous autofocus %1").arg(ok ? "on" : "FAILED"));
    return ok;
}

void ImageTool::removeImage(const QString &path)
{
    // Only ever delete our own processed copies, never camera-roll originals.
    const QString mine = QDir::homePath() + "/images/";
    if (path.startsWith(mine) && !path.contains("..")) {
        QFile::remove(path);
        m_app->log("images: removed " + path);
    }
}
