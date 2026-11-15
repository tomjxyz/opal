#include "jpegtool.h"
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <jpeglib.h>

struct jt_err { struct jpeg_error_mgr mgr; jmp_buf jb; char msg[JMSG_LENGTH_MAX]; };

static void jt_error_exit(j_common_ptr c)
{
    struct jt_err *e = (struct jt_err *)c->err;
    c->err->format_message(c, e->msg);
    longjmp(e->jb, 1);
}

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

/* EXIF orientation (tag 0x0112 in IFD0) from a saved APP1 marker; 1 if absent. */
static int exif_orientation(j_decompress_ptr d)
{
    jpeg_saved_marker_ptr m;
    for (m = d->marker_list; m; m = m->next) {
        const unsigned char *p = m->data;
        unsigned len = m->data_length, ifd, n, i;
        int le;
        if (m->marker != JPEG_APP0 + 1 || len < 14 || memcmp(p, "Exif\0\0", 6) != 0) continue;
        p += 6; len -= 6;
        le = (p[0] == 'I');
#define U16(o) (le ? (unsigned)(p[o] | p[(o)+1] << 8) : (unsigned)(p[o] << 8 | p[(o)+1]))
#define U32(o) (le ? (unsigned)(p[o] | p[(o)+1] << 8 | p[(o)+2] << 16 | (unsigned)p[(o)+3] << 24) \
                   : (unsigned)((unsigned)p[o] << 24 | p[(o)+1] << 16 | p[(o)+2] << 8 | p[(o)+3]))
        ifd = U32(4);
        if (ifd + 2 > len) return 1;
        n = U16(ifd);
        for (i = 0; i < n; i++) {
            unsigned e = ifd + 2 + i * 12;
            if (e + 12 > len) break;
            if (U16(e) == 0x0112) { unsigned v = U16(e + 8); return (v >= 1 && v <= 8) ? (int)v : 1; }
        }
#undef U16
#undef U32
    }
    return 1;
}

int jt_process(const char *in_path, const char *out_path,
               double cx, double cy, double cw, double ch, double view_aspect,
               int max_edge, int quality, char *info, size_t info_len)
{
    struct jpeg_decompress_struct d;
    struct jpeg_compress_struct c;
    struct jt_err err;
    FILE *volatile in = NULL, *volatile out = NULL;   /* volatile: read after longjmp */
    unsigned char *volatile img = NULL, *volatile up = NULL, *volatile dst = NULL;
    double t0 = now_ms(), t_dec, t_rot, t_scale, t_enc;
    int orient, W, H, uw, uh, x0, y0, x1, y1, crw, crh, ow, oh, denom, long_edge, i;
    long out_size;

    info[0] = 0;
    if (cw <= 0 || ch <= 0) { cx = 0; cy = 0; cw = 1; ch = 1; }
    in = fopen(in_path, "rb");
    if (!in) { snprintf(info, info_len, "cannot open %s", in_path); return -1; }

    memset(&d, 0, sizeof d);
    d.err = jpeg_std_error(&err.mgr);
    err.mgr.error_exit = jt_error_exit;
    if (setjmp(err.jb)) {
        snprintf(info, info_len, "libjpeg: %s", err.msg);
        jpeg_destroy_decompress(&d);
        jpeg_destroy_compress(&c);
        if (in) fclose(in);
        if (out) fclose(out);
        free(img); free(up); free(dst);
        return -1;
    }
    memset(&c, 0, sizeof c);       /* so the error path can always destroy it */
    jpeg_create_decompress(&d);
    jpeg_stdio_src(&d, in);
    jpeg_save_markers(&d, JPEG_APP0 + 1, 0xFFFF);
    jpeg_read_header(&d, TRUE);
    orient = exif_orientation(&d);

    /* Viewfinder-relative crop -> photo-relative crop (viewfinder = aspect-fill of the photo). */
    if (view_aspect > 0) {
        double pw = (orient >= 5) ? d.image_height : d.image_width;   /* upright size */
        double ph = (orient >= 5) ? d.image_width : d.image_height;
        double a = pw / ph;
        if (a > view_aspect) {          /* photo wider than view: sides are cut off */
            double vis = view_aspect / a;
            cx = (1 - vis) / 2 + cx * vis; cw *= vis;
        } else {                        /* photo taller: top/bottom cut off */
            double vis = a / view_aspect;
            cy = (1 - vis) / 2 + cy * vis; ch *= vis;
        }
    }

    /* Pick the largest DCT downscale that still leaves the crop's long edge >= max_edge. */
    {
        double crop_long = (cw > ch ? cw : ch) * (d.image_width > d.image_height ? d.image_width : d.image_height); /* approx: long edge */
        denom = 1;
        while (denom < 8 && crop_long / (denom * 2) >= max_edge) denom *= 2;
    }
    d.scale_num = 1; d.scale_denom = denom;
    d.out_color_space = JCS_RGB;
    jpeg_start_decompress(&d);
    W = d.output_width; H = d.output_height;
    img = malloc((size_t)W * H * 3);
    if (!img) { snprintf(info, info_len, "out of memory (%dx%d)", W, H); jpeg_destroy_decompress(&d); fclose(in); return -1; }
    while (d.output_scanline < d.output_height) {
        JSAMPROW row = img + (size_t)d.output_scanline * W * 3;
        jpeg_read_scanlines(&d, &row, 1);
    }
    {
        int sw = d.image_width, sh = d.image_height;
        jpeg_finish_decompress(&d);
        jpeg_destroy_decompress(&d);
        fclose(in); in = NULL;
        t_dec = now_ms();

        /* Upright the image: orientations 3 (180), 6 (90 CW), 8 (90 CCW). Others: as is. */
        if (orient == 3 || orient == 6 || orient == 8) {
            int x, y;
            uw = (orient == 3) ? W : H; uh = (orient == 3) ? H : W;
            up = malloc((size_t)W * H * 3);
            if (!up) { snprintf(info, info_len, "out of memory rotating"); free(img); return -1; }
            for (y = 0; y < H; y++)
                for (x = 0; x < W; x++) {
                    int nx, ny;
                    if (orient == 3)      { nx = W - 1 - x; ny = H - 1 - y; }
                    else if (orient == 6) { nx = H - 1 - y; ny = x; }
                    else                  { nx = y;         ny = W - 1 - x; }
                    memcpy(up + ((size_t)ny * uw + nx) * 3, img + ((size_t)y * W + x) * 3, 3);
                }
            free(img); img = up; up = NULL;
        } else { uw = W; uh = H; }
        t_rot = now_ms();

        /* Crop. */
        x0 = (int)(cx * uw); y0 = (int)(cy * uh);
        x1 = (int)((cx + cw) * uw); y1 = (int)((cy + ch) * uh);
        if (x0 < 0) x0 = 0;
        if (y0 < 0) y0 = 0;
        if (x1 > uw) x1 = uw;
        if (y1 > uh) y1 = uh;
        crw = x1 - x0; crh = y1 - y0;
        if (crw < 8 || crh < 8) { snprintf(info, info_len, "crop too small (%dx%d)", crw, crh); free(img); return -1; }

        /* Box-filter downscale so the long edge is <= max_edge. */
        long_edge = crw > crh ? crw : crh;
        if (long_edge > max_edge) { ow = (int)((double)crw * max_edge / long_edge); oh = (int)((double)crh * max_edge / long_edge); }
        else { ow = crw; oh = crh; }
        if (ow < 1) ow = 1;
        if (oh < 1) oh = 1;
        dst = malloc((size_t)ow * oh * 3);
        if (!dst) { snprintf(info, info_len, "out of memory scaling"); free(img); return -1; }
        {
            int ox, oy;
            for (oy = 0; oy < oh; oy++) {
                int sy0 = y0 + (int)((long long)oy * crh / oh), sy1 = y0 + (int)((long long)(oy + 1) * crh / oh);
                if (sy1 <= sy0) sy1 = sy0 + 1;
                for (ox = 0; ox < ow; ox++) {
                    int sx0 = x0 + (int)((long long)ox * crw / ow), sx1 = x0 + (int)((long long)(ox + 1) * crw / ow);
                    unsigned sum[3] = {0, 0, 0}, cnt = 0;
                    int sx, sy, k;
                    if (sx1 <= sx0) sx1 = sx0 + 1;
                    for (sy = sy0; sy < sy1; sy++)
                        for (sx = sx0; sx < sx1; sx++) {
                            const unsigned char *s = img + ((size_t)sy * uw + sx) * 3;
                            sum[0] += s[0]; sum[1] += s[1]; sum[2] += s[2]; cnt++;
                        }
                    for (k = 0; k < 3; k++) dst[((size_t)oy * ow + ox) * 3 + k] = (unsigned char)(sum[k] / cnt);
                }
            }
        }
        free(img); img = NULL;
        t_scale = now_ms();

        /* Encode. */
        out = fopen(out_path, "wb");
        if (!out) { snprintf(info, info_len, "cannot write %s", out_path); free(dst); return -1; }
        c.err = jpeg_std_error(&err.mgr);
        err.mgr.error_exit = jt_error_exit;
        jpeg_create_compress(&c);
        jpeg_stdio_dest(&c, out);
        c.image_width = ow; c.image_height = oh; c.input_components = 3; c.in_color_space = JCS_RGB;
        jpeg_set_defaults(&c);
        jpeg_set_quality(&c, quality, TRUE);
        jpeg_start_compress(&c, TRUE);
        for (i = 0; i < oh; i++) {
            JSAMPROW row = dst + (size_t)i * ow * 3;
            jpeg_write_scanlines(&c, &row, 1);
        }
        jpeg_finish_compress(&c);
        jpeg_destroy_compress(&c);
        out_size = ftell(out);
        fclose(out); out = NULL;
        free(dst); dst = NULL;
        t_enc = now_ms();

        snprintf(info, info_len,
                 "src %dx%d exif-orient %d, crop %.2f,%.2f %.2fx%.2f, decoded 1/%d -> %dx%d (%.0f ms), upright %dx%d (%.0f ms), "
                 "crop %dx%d -> %dx%d (%.0f ms), jpeg q%d %ld bytes (%.0f ms), total %.0f ms",
                 sw, sh, orient, cx, cy, cw, ch, denom, W, H, t_dec - t0, uw, uh, t_rot - t_dec,
                 crw, crh, ow, oh, t_scale - t_rot, quality, out_size, t_enc - t_scale, t_enc - t0);
    }
    return 0;
}
