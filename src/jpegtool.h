/* jpegtool: decode a camera JPEG, apply EXIF orientation, crop, downscale, re-encode.
 * Plain C (libjpeg's setjmp error handling stays out of C++). */
#ifndef JPEGTOOL_H
#define JPEGTOOL_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Crop rect (cx, cy, cw, ch) is in fractions (0..1). If view_aspect > 0 the rect is
 * relative to a viewfinder of that width/height ratio which shows the upright photo
 * scaled to FILL it (centre-cropped); otherwise it is relative to the upright photo.
 * The result's long edge is at most max_edge. Returns 0 on success; on success
 * and failure, `info` gets a one-line human-readable description. */
int jt_process(const char *in_path, const char *out_path,
               double cx, double cy, double cw, double ch, double view_aspect,
               int max_edge, int quality, char *info, size_t info_len);
#ifdef __cplusplus
}
#endif
#endif
