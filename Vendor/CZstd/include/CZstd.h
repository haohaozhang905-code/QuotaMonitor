#ifndef QUOTAMONITOR_ZSTD_H
#define QUOTAMONITOR_ZSTD_H
#include <stddef.h>

typedef struct QMZstdReader QMZstdReader;
/* 只读流式解码：read 返回字节数，完整校验结束返回 0，失败返回 -1。 */
QMZstdReader *qm_zstd_open(const char *path);
int qm_zstd_read(QMZstdReader *reader, void *output, size_t capacity);
void qm_zstd_close(QMZstdReader *reader);
#endif
