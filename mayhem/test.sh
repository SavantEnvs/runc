#!/usr/bin/env bash
#
# mayhem/test.sh — the UPSTREAM functional oracle: RUNS runc's own `go test` suites for the
# packages behind the fuzz harnesses (Hooks JSON unmarshalling, config validation, spec
# conversion, capabilities, utils, logs, kernel-version parsing). It never compiles — the
# test binaries are produced by mayhem/build.sh (a missing runner is a hard failure here).
#
# These are known-answer / golden-value tests written by runc's authors, so a PATCH that
# no-ops the library FAILS them (§6.3 anti-reward-hacking). build.sh links the runners with
# -linkmode=external so they are DYNAMICALLY linked and verify-repo's sabotage check (an
# LD_PRELOAD _exit(0) constructor) can actually neuter them: under sabotage each runner
# exits silently, this script sees no PASS lines, and the CTRF report goes red.
#
# Emits a CTRF (ctrf.io) summary line and exits non-zero iff failed>0.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

TESTDIR="$SRC/mayhem-build/tests"
MANIFEST="$TESTDIR/manifest"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if [ ! -s "$MANIFEST" ]; then
  echo "FATAL: $MANIFEST missing — mayhem/build.sh did not build the test runners (test.sh never compiles)" >&2
  emit_ctrf go-test 0 1
  exit 1
fi

passed=0; failed=0; skipped=0
log="$(mktemp)"
while read -r pkg bin; do
  [ -n "${pkg:-}" ] || continue
  if [ ! -x "$bin" ]; then
    echo "FAIL: test runner $bin missing for ./$pkg" >&2
    failed=$((failed+1)); continue
  fi
  echo "=== running ./$pkg tests ==="
  ( cd "$SRC/$pkg" && "$bin" -test.v ) >"$log" 2>&1
  rc=$?
  # Count only TOP-LEVEL results (subtests are indented); `strings` because a failing Go
  # test binary can emit non-UTF8 bytes in its output.
  p=$(strings "$log" | grep -cE '^--- PASS: ' || true)
  f=$(strings "$log" | grep -cE '^--- FAIL: ' || true)
  s=$(strings "$log" | grep -cE '^--- SKIP: ' || true)
  if [ "$((p + f + s))" -eq 0 ]; then
    # No test result lines at all: the runner did not actually execute the suite (crashed,
    # was neutered, or produced nothing). That is a FAILURE, never a silent pass.
    echo "FAIL: ./$pkg produced no test results (rc=$rc); tail:" >&2
    strings "$log" | tail -8 >&2
    failed=$((failed+1)); continue
  fi
  if [ "$f" -gt 0 ] || [ "$rc" -ne 0 ]; then
    echo "FAIL: ./$pkg — $p passed, $f failed, $s skipped (rc=$rc); tail:" >&2
    strings "$log" | tail -12 >&2
    [ "$f" -eq 0 ] && f=1
  else
    echo "PASS: ./$pkg — $p passed, $s skipped"
  fi
  passed=$((passed + p)); failed=$((failed + f)); skipped=$((skipped + s))
done < "$MANIFEST"
rm -f "$log"

emit_ctrf go-test "$passed" "$failed" "$skipped"
