#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <pthread.h>

static long long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static long long ops = 0;
static long long dur_ms = 2000;

static void *worker(void *arg) {
    (void)arg;
    long long end = now_ns() + dur_ms * 1000000LL;
    long long n = 0;
    while (now_ns() < end) { sched_yield(); n++; }
    __sync_fetch_and_add(&ops, n);
    return NULL;
}

int main(int argc, char **argv) {
    int threads = argc > 1 ? atoi(argv[1]) : 1;
    dur_ms = argc > 2 ? atoi(argv[2]) : 2000;
    long long start = now_ns();
    if (threads == 1) {
        long long end = now_ns() + dur_ms * 1000000LL;
        long long n = 0;
        while (now_ns() < end) { sched_yield(); n++; }
        double ns = (double)(now_ns() - start) / (double)n;
        printf("threads=1   sched_yield: %.0f ns/op   (%lld ops in %d ms)\n", ns, n, dur_ms);
        return 0;
    }
    pthread_t t[64];
    for (int i = 0; i < threads; i++) { pthread_create(&t[i], NULL, worker, NULL); }
    for (int i = 0; i < threads; i++) { pthread_join(t[i], NULL); }
    double total = (double)(now_ns() - start) / 1e9;
    printf("threads=%-3d sched_yield: %.0f ns/op aggregate   (%.1f Mops/s, wall %.1f s)\n",
           threads, total * 1e9 / (double)ops, (double)ops / total / 1e6, total);
    return 0;
}
