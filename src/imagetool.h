// Photo processing for camera search, exposed to QML as context property "images".
// Crops/scales a camera or gallery JPEG on a worker thread (libjpeg, src/jpegtool.c)
// and writes the result to data/images/. Also sets the camera flash.
#ifndef OPAL_IMAGETOOL_H
#define OPAL_IMAGETOOL_H

#include <QObject>
#include <QString>

class Opal;

class ImageTool : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
public:
    ImageTool(Opal *app, QObject *parent = 0);
    bool busy() const { return m_busy; }

    // Crop rect in fractions (0..1). viewAspect > 0: rect is relative to a viewfinder of that
    // width/height (photo shown aspect-fill); 0: relative to the whole upright photo.
    Q_INVOKABLE void process(const QString &path, double x, double y, double w, double h, double viewAspect);
    // mode: 0 off, 1 on, 2 auto, 3 torch ("light"). camera: the QML Camera object.
    Q_INVOKABLE bool setFlash(QObject *camera, int mode);
    // Tap to focus: one autofocus cycle aimed at (fx, fy), fractions of the photo (0..1).
    // The focus-region coordinate space isn't documented; we use the capture resolution and fall
    // back to a plain refocus if the camera rejects the region. Both outcomes are logged.
    Q_INVOKABLE bool focusAt(QObject *camera, double fx, double fy);
    // Back to continuous autofocus (after a photo, or when the camera opens).
    Q_INVOKABLE bool continuousFocus(QObject *camera);
    // Remove processed images that no chat references any more (called after deleting chats).
    Q_INVOKABLE void removeImage(const QString &path);

signals:
    void busyChanged();
    void processed(const QString &path);
    void processFailed(const QString &message);

private slots:
    void onJobFinished();

private:
    Opal *m_app;
    bool m_busy;
};

#endif
