/*
 * uck-vcio-shim.c — LD_PRELOAD shim for Solar Assistant on UCK G2 Plus.
 *
 * WHY: SA's influx-bridge-setup reads a device identity from /dev/vcio via the
 * Broadcom VideoCore mailbox ioctl (_IOC(READ|WRITE, 0x64, 0, 8)). The UCK is a
 * Qualcomm APQ8053 — no VideoCore, so the ioctl returns ENOTTY and setup aborts.
 *
 * WHAT: intercept ioctl() for the VideoCore mailbox request and answer it with a
 * value DERIVED FROM THIS DEVICE'S OWN HARDWARE (eMMC CID). Every UCK therefore
 * yields a DIFFERENT identity — no value is ever hardcoded or shared between units.
 *
 * The shim does NOT hardcode a device id; it computes one at runtime. Safe to
 * commit: contains no serials, no MACs, no private values.
 *
 * Build:  aarch64-linux-gnu-gcc -shared -fPIC -O2 -o uck-vcio-shim.so uck-vcio-shim.c -ldl
 * Use:    LD_PRELOAD=/usr/lib/influx-bridge/uck-vcio-shim.so influx-bridge-setup
 */
#define _GNU_SOURCE
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <errno.h>

typedef int (*ioctl_fn_t)(int, unsigned long, ...);

#define VC_IOCTL_TYPE 0x64            /* VideoCore mailbox property channel */
#define VC_REQ_MAGIC  0x00000000u    /* MAILBOX_PROPERTY_REQUEST */

/* ---- read the eMMC CID: factory-burned, unique per chip, unchangeable ------- */
static int read_emmc_cid(unsigned char *out, size_t outlen) {
    const char *paths[] = {
        "/sys/block/mmcblk0/device/cid",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        int fd = open(paths[i], O_RDONLY);
        if (fd < 0) continue;
        char buf[64] = {0};
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n <= 0) continue;
        /* strip whitespace */
        char *p = buf;
        while (*p == ' ' || *p == '\t' || *p == '\n') p++;
        size_t L = strcspn(p, " \t\r\n");
        if (L == 0) continue;
        size_t k = (L < outlen) ? L : outlen;
        memcpy(out, p, k);
        if (k < outlen) out[k] = 0;
        return (int)k;
    }
    /* fallback: machine-id (always present, still unique per install) */
    int fd = open("/etc/machine-id", O_RDONLY);
    if (fd >= 0) {
        char buf[64] = {0};
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n > 0) {
            size_t k = ((size_t)n < outlen) ? (size_t)n : outlen - 1;
            memcpy(out, buf, k);
            out[k] = 0;
            return (int)k;
        }
    }
    return 0;
}

/* ---- FNV-1a 32-bit over the device id, salted per index -------------------- */
static uint32_t derive_u32(const unsigned char *seed, int seedlen, uint32_t salt) {
    uint32_t h = 2166136261u ^ salt;
    for (int i = 0; i < seedlen; i++) {
        h ^= (uint32_t)seed[i];
        h *= 16777619u;
    }
    h ^= salt;
    return h;
}

int ioctl(int fd, unsigned long request, ...) {
    va_list ap;
    va_start(ap, request);
    void *arg = va_arg(ap, void *);
    va_end(ap);

    unsigned int type = _IOC_TYPE(request);
    unsigned int nr   = _IOC_NR(request);
    unsigned int dir  = _IOC_DIR(request);
    unsigned int size = _IOC_SIZE(request);

    /* Match the VideoCore mailbox property call: type 0x64, 8-byte arg */
    if (type == VC_IOCTL_TYPE && size == 8 && arg != NULL) {
        unsigned char seed[64] = {0};
        int n = read_emmc_cid(seed, sizeof(seed) - 1);
        if (n > 0) {
            /* The arg is a VideoCore property buffer:
             *   u32 size; u32 req_resp; u32 tag; u32 value_len; u32 value;
             * We fill a per-device value into the value field when it is a
             * 4-byte read response (READ set in dir). */
            uint32_t *buf = (uint32_t *)arg;
            uint32_t u = derive_u32(seed, n, 0x55434B31u); /* "UCK1" */
            /* keep the caller's size/req fields, set a device-derived value */
            if (dir & _IOC_READ) {
                /* value slot: for the common 8-byte 1-in-1-out layout, slot 4 */
                buf[1] = u;              /* some callers read the value here */
            }
            if (dir & _IOC_WRITE) {
                /* if the caller provided a request, mirror size */
                if (buf[0] == 0) buf[0] = size;
            }
            return 0;   /* success */
        }
    }

    /* not ours — pass through to the real ioctl */
    ioctl_fn_t real = (ioctl_fn_t)dlsym(RTLD_NEXT, "ioctl");
    if (!real) { errno = ENOSYS; return -1; }
    if (dir == _IOC_NONE) return real(fd, request);
    return real(fd, request, arg);
}
