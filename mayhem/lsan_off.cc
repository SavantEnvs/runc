// mayhem/lsan_off.cc — turn LeakSanitizer OFF at BUILD time (SPEC §6.2 item 15).
//
// Every target here is linked with `-fsanitize=address`, and ASan always bundles
// LeakSanitizer in — there is no flag that keeps ASan's memory-corruption checks
// while dropping just leak detection. Leaks are not the bug class this fleet
// fuzzes for (ASan's heap-buffer-overflow / use-after-free / etc. and UBSan are),
// and a long-lived Go fuzz process reports them constantly.
//
// Linking this TU into every fuzz binary makes the ASan runtime query this hook
// once at exit and skip the leak pass. ASan and UBSan stay fully active; only
// leak detection is affected. This is the build-time form the spec mandates —
// it is not a runtime toggle and it does not override Mayhem's sanitizer option
// set, which Mayhem alone owns.
extern "C" int __lsan_is_turned_off() { return 1; }
