# Shared helpers for the test scripts. Output is TAP-like: "ok", "not ok", and
# "not ok ... # TODO" for known gaps, which don't fail the run.

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export ROOT

# The tests point HOME at a scratch directory; a desktop session's XDG
# variables would still point at the real one.
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_RUNTIME_DIR

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

pass() { printf 'ok - %s\n' "$1"; }
skip() { printf 'ok - %s # SKIP %s\n' "$1" "${2:-}"; }
todo() { printf 'not ok - %s # TODO %s\n' "$1" "${2:-}"; }

fail() {
  [[ -n ${2:-} ]] && printf '%s\n' "$2" >&2
  printf 'not ok - %s\n' "$1"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null || fail "required command is available: $1"
}
