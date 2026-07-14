#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <fcntl.h>

/* glibc resolver init — no-op for local-only build */
int __res_init(void) { return 0; }

/* ISO C23 variants — redirect to standard versions */
int __isoc23_sscanf(const char *str, const char *format, ...) {
    va_list args;
    va_start(args, format);
    int ret = vsscanf(str, format, args);
    va_end(args);
    return ret;
}

unsigned long long __isoc23_strtoull(const char *nptr, char **endptr, int base) {
    return strtoull(nptr, endptr, base);
}

long long __isoc23_strtoll(const char *nptr, char **endptr, int base) {
    return strtoll(nptr, endptr, base);
}

long __isoc23_strtol(const char *nptr, char **endptr, int base) {
    return strtol(nptr, endptr, base);
}

/* fcntl64 — same as fcntl on 64-bit */
int fcntl64(int fd, int cmd, ...) {
    va_list args;
    va_start(args, cmd);
    long arg = va_arg(args, long);
    va_end(args);
    return fcntl(fd, cmd, arg);
}
