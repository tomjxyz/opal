#include "httpjob.h"

#include <QElapsedTimer>
#include <curl/curl.h>

static size_t onData(char *ptr, size_t size, size_t nmemb, void *userdata)
{
    QByteArray *out = static_cast<QByteArray *>(userdata);
    out->append(ptr, (int)(size * nmemb));
    if (out->size() > 4 * 1024 * 1024) return 0;      // refuse absurd responses
    return size * nmemb;
}

static int onProgress(void *clientp, double, double, double, double)
{
    return static_cast<HttpJob *>(clientp)->aborted ? 1 : 0;   // non-zero aborts the transfer
}

void HttpJob::run()
{
    QElapsedTimer t;
    t.start();
    CURL *c = curl_easy_init();
    if (!c) {
        curlCode = -1;
        error = "curl_easy_init failed";
        return;
    }
    char errbuf[CURL_ERROR_SIZE];
    errbuf[0] = 0;
    struct curl_slist *hdrs = 0;
    QList<QByteArray> keep = headers;    // curl keeps pointers into these until cleanup
    foreach (const QByteArray &h, keep) hdrs = curl_slist_append(hdrs, h.constData());
    const QByteArray url8 = url.toUtf8();
    const QByteArray ca8 = caFile.toUtf8();

    curl_easy_setopt(c, CURLOPT_URL, url8.constData());
    curl_easy_setopt(c, CURLOPT_POST, 1L);
    curl_easy_setopt(c, CURLOPT_POSTFIELDS, body.constData());
    curl_easy_setopt(c, CURLOPT_POSTFIELDSIZE, (long)body.size());
    curl_easy_setopt(c, CURLOPT_HTTPHEADER, hdrs);
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, onData);
    curl_easy_setopt(c, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(c, CURLOPT_ERRORBUFFER, errbuf);
    curl_easy_setopt(c, CURLOPT_NOSIGNAL, 1L);             // required with threads
    curl_easy_setopt(c, CURLOPT_CONNECTTIMEOUT, 10L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT, (long)timeoutSecs);
    curl_easy_setopt(c, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(c, CURLOPT_PROGRESSFUNCTION, onProgress);
    curl_easy_setopt(c, CURLOPT_PROGRESSDATA, this);
    if (!caFile.isEmpty()) curl_easy_setopt(c, CURLOPT_CAINFO, ca8.constData());
    curl_easy_setopt(c, CURLOPT_SSL_VERIFYPEER, verifyPeer ? 1L : 0L);
    curl_easy_setopt(c, CURLOPT_SSL_VERIFYHOST, verifyPeer ? 2L : 0L);

    const CURLcode rc = curl_easy_perform(c);
    curlCode = (int)rc;
    if (rc != CURLE_OK) error = QString::fromUtf8(errbuf[0] ? errbuf : curl_easy_strerror(rc));
    long code = 0;
    curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &code);
    status = (int)code;
    curl_slist_free_all(hdrs);
    curl_easy_cleanup(c);
    elapsedMs = t.elapsed();
}
