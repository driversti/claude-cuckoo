# tests/lib.sh — zero-dependency assert helpers + sandbox.
TESTS_RUN=0; TESTS_FAILED=0
CUCKOO_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/cuckoo"
cuckoo() { bash "$CUCKOO_BIN" "$@"; }

# sandbox: isolated global + project dirs in a temp tree; sets the env seams.
new_sandbox() {
  SANDBOX="$(mktemp -d)"
  export CUCKOO_HOME="$SANDBOX/global"
  export CLAUDE_PROJECT_DIR="$SANDBOX/project"
  mkdir -p "$CUCKOO_HOME" "$CLAUDE_PROJECT_DIR"
  unset CUCKOO_NOW_OVERRIDE
}

assert_eq()       { TESTS_RUN=$((TESTS_RUN+1)); [ "$1" = "$2" ] || { TESTS_FAILED=$((TESTS_FAILED+1)); printf 'FAIL: %s\n  expected:[%s]\n  actual:  [%s]\n' "$3" "$1" "$2"; }; }
assert_empty()    { TESTS_RUN=$((TESTS_RUN+1)); [ -z "$1" ] || { TESTS_FAILED=$((TESTS_FAILED+1)); printf 'FAIL: %s (expected empty, got [%s])\n' "$2" "$1"; }; }
assert_contains() { TESTS_RUN=$((TESTS_RUN+1)); case "$1" in *"$2"*) ;; *) TESTS_FAILED=$((TESTS_FAILED+1)); printf 'FAIL: %s (missing [%s])\n' "$3" "$2";; esac; }
assert_missing()  { TESTS_RUN=$((TESTS_RUN+1)); case "$1" in *"$2"*) TESTS_FAILED=$((TESTS_FAILED+1)); printf 'FAIL: %s (should NOT contain [%s])\n' "$3" "$2";; *) ;; esac; }
finish() { printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"; [ "$TESTS_FAILED" -eq 0 ]; }
