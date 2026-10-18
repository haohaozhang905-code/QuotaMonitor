#include "CZstd.h"
#include "zstd.h"
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

struct QMZstdReader {
    FILE *file;
    ZSTD_DStream *stream;
    unsigned char input[65536];
    ZSTD_inBuffer pending;
    size_t remaining;
    int saw_frame;
};

QMZstdReader *qm_zstd_open(const char *path) {
    QMZstdReader *r = calloc(1, sizeof(*r));
    if (!r) return NULL;
    r->file = fopen(path, "rb");
    r->stream = ZSTD_createDStream();
    if (!r->file || !r->stream ||
        ZSTD_isError(ZSTD_initDStream(r->stream)) ||
        ZSTD_isError(ZSTD_DCtx_setParameter(r->stream, ZSTD_d_windowLogMax, 27))) {
        qm_zstd_close(r);
        return NULL;
    }
    r->pending.src = r->input;
    r->remaining = 1;
    return r;
}

int qm_zstd_read(QMZstdReader *r, void *output, size_t capacity) {
    if (!r || !output || capacity == 0 || capacity > INT_MAX) return -1;
    ZSTD_outBuffer out = { output, capacity, 0 };
    while (out.pos == 0) {
        if (r->pending.pos == r->pending.size) {
            r->pending.size = fread(r->input, 1, sizeof(r->input), r->file);
            r->pending.pos = 0;
            if (ferror(r->file)) return -1;
            if (r->pending.size == 0 && r->saw_frame && r->remaining == 0) {
                /* 完整帧结束后抵达文件末尾，才算读取成功。 */
                return 0;
            }
        }
        size_t previous = r->pending.pos;
        r->remaining = ZSTD_decompressStream(r->stream, &out, &r->pending);
        if (ZSTD_isError(r->remaining)) return -1;
        if (r->remaining == 0) r->saw_frame = 1;
        /* 没有输入输出进展时按失败处理，涵盖空文件和截断帧。 */
        if (out.pos == 0 && r->pending.pos == previous) return -1;
        /* 继续读取连接帧及可跳过帧，直到完整校验结束。 */
    }
    return (int)out.pos;
}

void qm_zstd_close(QMZstdReader *r) {
    if (!r) return;
    if (r->file) fclose(r->file);
    ZSTD_freeDStream(r->stream);
    free(r);
}
