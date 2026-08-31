#!/usr/bin/env bash
#
# mayhem/build.sh — build runc's go-fuzz harnesses as sanitized libFuzzer binaries
# (OSS-Fuzz Go path: go-fuzz-build -libfuzzer + clang link), plus the project's test
# binaries (normal flags) that mayhem/test.sh merely RUNS.
#
# Runs inside the commit image (GO mayhem/Dockerfile) as `mayhem` in /mayhem.
# GOROOT/GOPATH/GOMODCACHE are pinned by the Dockerfile ENV (under /opt/toolchains —
# absolute, $HOME-independent), so the module cache survives the PATCH re-run identity.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
#   - This FIRST build (online, in CI) populates the module cache under $GOMODCACHE,
#     which doubles as a FILE PROXY at $GOMODCACHE/cache/download.
#   - GOPROXY points at that file proxy FIRST, network LAST: the offline re-run resolves
#     entirely from the cache; the network entries only fill cache-misses on this first
#     online build. -mod=mod lets go-fuzz-build's `go get` of go-fuzz-dep update go.mod
#     from the cache. (GOPROXY=off is NOT enough — it blocks reading the version list
#     from the cache, which `go get` needs.)
#   - runc vendors its deps, but -mod=mod is required (go-fuzz-build injects go-fuzz-dep,
#     which is NOT vendored and cannot be added to vendor/ additively), so the module
#     cache — not vendor/ — is what makes the offline re-run work.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SRC:=/mayhem}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz's Go path links the go-fuzz archive with ASan only (UBSan has no effect on
# gc-compiled Go objects and breaks the link). Keep ASan even if the base default differs.
: "${SANITIZER_FLAGS=-fsanitize=address}"
# DWARF < 4 (SPEC §6.2 item 10): Go's gc compiler always emits DWARF4 and has no downgrade
# flag, but go-fuzz links via cgo/clang and the C shims (_cgo_export.c) land FIRST in the
# binary. Forcing those C compilation units to DWARF3 (CGO_*FLAGS + the final clang link)
# makes the first .debug_info CU DWARF3 — what verify-repo's readelf check reads.
: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
: "${MAYHEM_JOBS:=$(nproc)}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS GO_DEBUG_FLAGS MAYHEM_JOBS

export CGO_CFLAGS="${CGO_CFLAGS:+$CGO_CFLAGS }$GO_DEBUG_FLAGS"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:+$CGO_CXXFLAGS }$GO_DEBUG_FLAGS"

# Resolve modules offline-first from the in-image cache; network only as a fallback.
# $(go env GOMODCACHE) reads the pinned ENV, so it is correct under ANY $HOME.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"

cd "$SRC"
go version

# go-fuzz-build needs go-fuzz-dep on the module graph. With -mod=mod + the file-proxy
# GOPROXY this resolves from the cache offline (no-op once present). Done here rather than
# via a committed go.mod edit so the mayhem layer stays purely additive vs upstream.
go get github.com/dvyukov/go-fuzz/go-fuzz-dep

BUILD="$SRC/mayhem-build"
mkdir -p "$BUILD"

# ── fuzz targets ──────────────────────────────────────────────────────────────
# Both harnesses are UPSTREAM `//go:build gofuzz` functions — the same two that runc's
# tests/fuzzing/oss_fuzz_build.sh builds for OSS-Fuzz:
#   configs_fuzzer -> libcontainer/configs        FuzzUnmarshalJSON   (Hooks.UnmarshalJSON)
#   user_fuzzer    -> github.com/moby/sys/user    FuzzUser            (passwd/group parsing)
# OSS-Fuzz still names `github.com/opencontainers/runc/libcontainer/user`; upstream moved
# that package out to github.com/moby/sys/user (vendored here, and still what runc calls),
# and the fuzzer moved with it — so the FuzzUser code path is preserved, at its new home.
# ── LeakSanitizer off at build time (SPEC §6.2 item 15) ───────────────────────
# The go-fuzz archives below are linked with ASan, which always bundles LeakSanitizer
# in. Compile the hook TU with $SANITIZER_FLAGS and link it into EVERY fuzz binary so
# only the leak pass is skipped; ASan + UBSan stay fully active.
LSAN_OFF_OBJ="$BUILD/lsan_off.o"
echo "=== compiling mayhem/lsan_off.cc (build-time LeakSanitizer hook) ==="
$CXX $SANITIZER_FLAGS $GO_DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$LSAN_OFF_OBJ"

build_target() {
  local pkg="$1" fn="$2" out="$3"
  echo "=== building $out ($pkg $fn, go-fuzz-build -libfuzzer) ==="
  go-fuzz-build -libfuzzer -func "$fn" -o "$BUILD/$(basename "$out").a" "$pkg"
  $CXX $SANITIZER_FLAGS $GO_DEBUG_FLAGS $LIB_FUZZING_ENGINE "$BUILD/$(basename "$out").a" "$LSAN_OFF_OBJ" -o "$out"
  echo "built $out"
}

build_target github.com/opencontainers/runc/libcontainer/configs FuzzUnmarshalJSON /mayhem/configs_fuzzer
build_target github.com/moby/sys/user                            FuzzUser          /mayhem/user_fuzzer

# ── standalone (non-fuzzer) reproducer ────────────────────────────────────────
# The original integration's file-input driver, preserved: one input file, one run, natural
# crash, no libFuzzer runtime. Repro artifact — deliberately NOT a Mayhemfile target.
echo "=== building /mayhem/configs_fuzzer_native (standalone repro driver) ==="
go build -o /mayhem/configs_fuzzer_native ./mayhem/configs_fuzzer_native
echo "built /mayhem/configs_fuzzer_native"

# ── upstream test suite (NORMAL flags, clean build) ───────────────────────────
# test.sh only RUNS these. -linkmode=external makes the test binaries DYNAMICALLY linked
# (Go's internal linker would produce a static ELF), which keeps them observable by the
# verify-repo sabotage check — a statically linked oracle can't be neutered, and so
# couldn't prove it asserts behavior rather than exit status (§6.3).
TESTDIR="$BUILD/tests"
mkdir -p "$TESTDIR"
TEST_PKGS="
libcontainer/configs
libcontainer/configs/validate
libcontainer/specconv
libcontainer/capabilities
libcontainer/utils
libcontainer/logs
libcontainer/system/kernelversion
"
: > "$TESTDIR/manifest"
for p in $TEST_PKGS; do
  n="$(echo "$p" | tr '/' '_')"
  echo "=== building test runner for ./$p ==="
  ( unset CGO_CFLAGS CGO_CXXFLAGS
    go test -c -ldflags=-linkmode=external -o "$TESTDIR/$n.test" "./$p" )
  # manifest: "<package-dir> <test-binary>" — test.sh runs each binary from its package
  # directory (Go test binaries resolve testdata/ relative to CWD).
  printf '%s %s\n' "$p" "$TESTDIR/$n.test" >> "$TESTDIR/manifest"
done
echo "test runners:"; cat "$TESTDIR/manifest"

echo "build.sh complete"
