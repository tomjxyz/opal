// HttpJob: one HTTPS POST done with libcurl on a worker thread.
//
// Why not QNetworkAccessManager: on the Classic, Qt 4's TLS only gets old cipher suites (it reached
// opencode.ai with ECDHE-ECDSA-AES128-SHA). api.tavily.com accepts nothing but TLS 1.2 with AEAD/GCM
// suites, so the handshake failed. The device libcurl (7.24) uses the system OpenSSL 1.0.2g directly
// and negotiates TLS 1.2 + GCM. Certificates come from assets/cacert.pem (Mozilla bundle) because
// curl doesn't share Qt's certificate store.
//
// Usage: fill the public fields, connect QThread::finished(), start(); read the results in the slot
// (sender() is the job). curl_global_init() must have been called once at startup (main.cpp).
#ifndef OPAL_HTTPJOB_H
#define OPAL_HTTPJOB_H

#include <QByteArray>
#include <QList>
#include <QString>
#include <QThread>
#include <QVariant>

class HttpJob : public QThread {
public:
    HttpJob() : status(0), curlCode(0), elapsedMs(0), verifyPeer(true), timeoutSecs(25), aborted(false) {}

    // in
    QString url;
    QList<QByteArray> headers;          // "Name: value"
    QByteArray body;
    QString caFile;                     // PEM bundle path
    QVariantMap tag;                    // caller's data (e.g. tool call id, query)
    // out
    int status;                         // HTTP status, 0 if no response
    int curlCode;                       // CURLcode, 0 = ok
    QString error;                      // curl's error text when curlCode != 0
    QByteArray response;
    qint64 elapsedMs;
    // options
    bool verifyPeer;
    int timeoutSecs;

    void abort() { aborted = true; }    // checked by curl's progress callback
    volatile bool aborted;

protected:
    void run();
};

#endif
