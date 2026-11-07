#!/usr/bin/env bash
# bin/mode against stub hyprctl and notification commands.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_command jq

mkdir -p "$tmpdir/bin" "$tmpdir/home" "$tmpdir/runtime"
export HOME="$tmpdir/home" XDG_STATE_HOME="$tmpdir/state" XDG_RUNTIME_DIR="$tmpdir/runtime"
export CALLS="$tmpdir/calls" PATH="$tmpdir/bin:$PATH"

cat >"$tmpdir/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALLS"
case $1 in
  reload)
    # Whether the switching marker was there while Hyprland reloaded.
    [[ -f $XDG_RUNTIME_DIR/omarchy-classic-workspaces-switching ]] && echo marker >>"$CALLS"
    exit "${RELOAD_FAILURE:-0}" ;;
  getoption)
    [[ $2 == cursor:warp_on_change_workspace ]] && echo '{"int": 2}'
    [[ $2 == cursor:no_warps ]] && echo '{"bool": false}'
    ;;
  cursorpos) echo "120, 340" ;;
  eval)
    # Stands in for compact moving a saved layout.
    if [[ -n ${MOVE_LAYOUT:-} && $2 == *compact* ]]; then
      mkdir -p "$XDG_STATE_HOME/omarchy/workspace-layouts"
      touch "$XDG_STATE_HOME/omarchy/workspace-layouts/3.lua"
    fi ;;
esac
exit 0
SH
cat >"$tmpdir/bin/omarchy-notification-send" <<'SH'
#!/usr/bin/env bash
printf 'notify %s\n' "$*" >>"$CALLS"
SH
chmod +x "$tmpdir/bin/"*

mode="$ROOT/bin/mode"
flag="$XDG_STATE_HOME/omarchy/toggles/no-monitor-workspaces"

[[ $("$mode" status) == 4.5 ]] || fail "status starts at 4.5"
"$mode" classic
[[ -f $flag ]] || fail "classic creates the flag"
[[ $("$mode" status) == classic ]] || fail "status reports classic"
grep -qx reload "$CALLS" || fail "classic reloads Hyprland"
grep -qx marker "$CALLS" || fail "the switching marker is there during the reload"
[[ ! -e $XDG_RUNTIME_DIR/omarchy-classic-workspaces-switching ]] || fail "the marker is gone afterwards"
grep -q "o.workspaces.compact" "$CALLS" || fail "classic compacts workspaces 11+"
grep -q "notify .*Classic" "$CALLS" || fail "classic notifies"
pass "classic sets the flag, reloads without warps, compacts and notifies"

grep -q "warp_on_change_workspace = 2, no_warps = false" "$CALLS" || fail "the user's cursor settings come back"
grep -q "cursor.move({ x = 120, y = 340 })" "$CALLS" || fail "the cursor goes back where it was"
pass "the user's cursor settings and position come back after the switch"

: >"$CALLS"
"$mode" classic
[[ ! -s $CALLS ]] || fail "asking for the current mode does nothing" "$(cat "$CALLS")"
pass "asking for the current mode does nothing"

: >"$CALLS"
"$mode" 4.5
[[ ! -e $flag ]] || fail "4.5 removes the flag"
! grep -q "o.workspaces.compact" "$CALLS" || fail "4.5 doesn't compact"
"$mode" toggle
[[ -f $flag ]] || fail "toggle goes to classic"
"$mode"
[[ ! -e $flag ]] || fail "no argument toggles back"
pass "4.5, toggle and no argument switch as named"

: >"$CALLS"
if "$mode" invalid 2>/dev/null; then fail "an unknown mode is rejected"; fi
[[ ! -s $CALLS && ! -e $flag ]] || fail "an unknown mode changes nothing"
pass "an unknown mode is rejected and changes nothing"

if RELOAD_FAILURE=1 "$mode" classic 2>/dev/null; then fail "a failed reload is reported"; fi
[[ ! -e $flag ]] || fail "a failed reload puts the flag back"
[[ ! -e $XDG_RUNTIME_DIR/omarchy-classic-workspaces-switching ]] || fail "a failed reload leaves no marker"
"$mode" classic
if RELOAD_FAILURE=1 "$mode" 4.5 2>/dev/null; then fail "a failed reload is reported"; fi
[[ -f $flag ]] || fail "a failed reload keeps Classic"
pass "a failed reload rolls the mode back either way"

"$mode" 4.5
XDG_STATE_HOME='' "$mode" classic
[[ -f $HOME/.local/state/omarchy/toggles/no-monitor-workspaces ]] || fail "an empty XDG_STATE_HOME falls back to ~/.local/state"
XDG_STATE_HOME='' "$mode" 4.5
pass "an empty XDG_STATE_HOME uses ~/.local/state, as Omarchy's paths.lua does"

: >"$CALLS"
"$mode" classic
[[ $(grep -cx reload "$CALLS") == 1 ]] || fail "no second reload when no layout moved"
"$mode" 4.5
: >"$CALLS"
MOVE_LAYOUT=1 "$mode" classic
[[ $(grep -cx reload "$CALLS") == 2 ]] || fail "a second reload applies the moved layouts"
"$mode" 4.5
rm -rf "$XDG_STATE_HOME/omarchy/workspace-layouts"
pass "Hyprland reloads again only when compact moved a saved layout"

XDG_RUNTIME_DIR='' "$mode" classic
[[ -f $flag ]] || fail "switching works without XDG_RUNTIME_DIR"
"$mode" 4.5
pass "switching works without XDG_RUNTIME_DIR"
