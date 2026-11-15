/*
 * crashlog.h - print a symbolisable crash report to stderr (= the app's
 * logs/log on BlackBerry 10), then die with the original signal.
 *
 *   #define CRASHLOG_IMPLEMENTATION   (in exactly one .c file)
 *   #include "crashlog.h"
 *   crashlog_install();               (early in main)
 *
 * Output, for SIGSEGV/SIGBUS/SIGILL/SIGFPE/SIGABRT:
 *   CRASH: signal 11 (SIGSEGV) fault addr 0x00000000 code 1
 *     pc 0x7810a2c4  libfoo.so.1 + 0x1a2c4  (foo_parse+0x30)
 *     lr 0x7810a1f0  libfoo.so.1 + 0x1a1f0  (foo_load+0x88)
 *     #0 ...                                  (unwound frames, if unwind info exists)
 * Symbolise on the build host with:
 *   arm-unknown-nto-qnx8.0.0eabi-addr2line -f -C -e <unstripped libfoo.so.1> 0x1a2c4
 *
 * PC/LR come from the signal context and are always right. The unwound list
 * needs -funwind-tables (ARM EHABI .ARM.exidx) in the code being unwound.
 * Uses snprintf in a signal handler: not strictly async-signal-safe, but the
 * process is dying anyway and this is a best-effort report. C99 and C++.
 */
#ifndef CRASHLOG_H
#define CRASHLOG_H

#ifdef __cplusplus
extern "C" {
#endif
void crashlog_install(void);
#ifdef __cplusplus
}
#endif

#ifdef CRASHLOG_IMPLEMENTATION
#include <dlfcn.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <ucontext.h>
#include <unistd.h>
#include <unwind.h>

static void crashlog_put(const char *s) { (void)!write(2, s, strlen(s)); }

static void crashlog_addr(const char *tag, uintptr_t a)
{
    char line[320];
    Dl_info di;
    memset(&di, 0, sizeof di);
    if (a && dladdr((void *)a, &di) && di.dli_fname) {
        const char *base = strrchr(di.dli_fname, '/');
        base = base ? base + 1 : di.dli_fname;
        if (di.dli_sname)
            snprintf(line, sizeof line, "  %-3s 0x%08lx  %s + 0x%lx  (%s+0x%lx)\n", tag, (unsigned long)a, base,
                     (unsigned long)(a - (uintptr_t)di.dli_fbase), di.dli_sname,
                     (unsigned long)(a - (uintptr_t)di.dli_saddr));
        else
            snprintf(line, sizeof line, "  %-3s 0x%08lx  %s + 0x%lx\n", tag, (unsigned long)a, base,
                     (unsigned long)(a - (uintptr_t)di.dli_fbase));
    } else {
        snprintf(line, sizeof line, "  %-3s 0x%08lx  (unknown module)\n", tag, (unsigned long)a);
    }
    crashlog_put(line);
}

struct crashlog_bt { int n; };

static _Unwind_Reason_Code crashlog_frame(struct _Unwind_Context *ctx, void *arg)
{
    struct crashlog_bt *bt = (struct crashlog_bt *)arg;
    char tag[8];
    uintptr_t ip = (uintptr_t)_Unwind_GetIP(ctx);
    if (!ip || bt->n >= 32) return _URC_END_OF_STACK;
    snprintf(tag, sizeof tag, "#%d", bt->n++);
    crashlog_addr(tag, ip & ~(uintptr_t)1);
    return _URC_NO_REASON;
}

static const char *crashlog_signame(int sig)
{
    switch (sig) {
    case SIGSEGV: return "SIGSEGV";
    case SIGBUS:  return "SIGBUS";
    case SIGILL:  return "SIGILL";
    case SIGFPE:  return "SIGFPE";
    case SIGABRT: return "SIGABRT";
    default:      return "?";
    }
}

static void crashlog_handler(int sig, siginfo_t *si, void *uctx)
{
    char line[200];
    snprintf(line, sizeof line, "\nCRASH: signal %d (%s) fault addr 0x%08lx code %d\n", sig,
             crashlog_signame(sig), (unsigned long)(uintptr_t)(si ? si->si_addr : 0), si ? si->si_code : 0);
    crashlog_put(line);
#if defined(__ARM__) || defined(__arm__)
    if (uctx) {
        const ucontext_t *uc = (const ucontext_t *)uctx;
        crashlog_addr("pc", uc->uc_mcontext.cpu.gpr[ARM_REG_PC]);
        crashlog_addr("lr", uc->uc_mcontext.cpu.gpr[ARM_REG_LR] & ~1u);
    }
#else
    (void)uctx;
#endif
    struct crashlog_bt bt = { 0 };
    _Unwind_Backtrace(crashlog_frame, &bt);
    crashlog_put("END CRASH\n");
    signal(sig, SIG_DFL);      /* die with the real signal so the parent / OS sees it */
    raise(sig);
}

void crashlog_install(void)
{
    static const int sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT };
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = crashlog_handler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    for (unsigned i = 0; i < sizeof sigs / sizeof sigs[0]; i++)
        sigaction(sigs[i], &sa, NULL);
}
#endif /* CRASHLOG_IMPLEMENTATION */
#endif /* CRASHLOG_H */
