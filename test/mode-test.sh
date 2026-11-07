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
    (( ${RELOAD_FAILURE:-0} )) && exit 1
    # What hypr/classic-workspaces.lua records: the flag's mode, or 4.5 when
    # Omarchy's own switch ignores the flag, or nothing when the config errors.
    (( ${CONFIG_ERROR:-0} )) && exit 0
    state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
    mode=4.5
    [[ -f $state/toggles/no-monitor-workspaces && -z ${IGNORES_FLAG:-} ]] && mode=classic
    mkdir -p "$state/classic-workspaces"
    echo "$mode" >"$state/classic-workspaces/applied"
    exit 0 ;;
  getoption)
    [[ $2 == cursor:warp_on_change_workspace ]] && echo '{"int": 2}'
    [[ $2 == cursor:no_warps ]] && echo '{"bool": false}'
    ;;
  cursorpos) echo "120, 340" ;;
  clients)
    # With RENUMBER, Omarchy's 4.5 renumbers as it reloads: 5 -> 25, and one
    # of 3's two windows goes to 13, so 3 isn't one workspace renumbered.
    state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
    if [[ -n ${RENUMBER:-} && $(cat "$state/classic-workspaces/applied" 2>/dev/null) == 4.5 ]]; then
      echo '[{"address":"0xa","workspace":{"id":25}},{"address":"0xb","workspace":{"id":13}},{"address":"0xc","workspace":{"id":3}},{"address":"0xd","workspace":{"id":1}},{"address":"0xe","workspace":{"id":-98}}]'
    else
      echo '[{"address":"0xa","workspace":{"id":5}},{"address":"0xb","workspace":{"id":3}},{"address":"0xc","workspace":{"id":3}},{"address":"0xd","workspace":{"id":1}},{"address":"0xe","workspace":{"id":-98}}]'
    fi ;;
  eval)
    # Stands in for compact moving a saved layout.
    if [[ -n ${MOVE_LAYOUT:-} && $2 == *compact* ]]; then
      mkdir -p "$XDG_STATE_HOME/omarchy/workspace-layouts"
      touch "$XDG_STATE_HOME/omarchy/workspace-layouts/3.lua"
    fi
    if [[ -n ${MOVE_LAYOUT:-} && $2 == *move_layouts* ]]; then
      mkdir -p "$XDG_STATE_HOME/omarchy/workspace-layouts"
      touch "$XDG_STATE_HOME/omarchy/workspace-layouts/25.lua"
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
: >"$CALLS"
if CONFIG_ERROR=1 "$mode" classic 2>/dev/null; then fail "a config load that doesn't finish is reported"; fi
[[ ! -e $flag ]] || fail "a config load that doesn't finish puts the flag back"
grep -q "notify .*didn't switch" "$CALLS" || fail "the failure is notified, for a click on the bar"
pass "a config load that doesn't finish rolls the mode back (reload exits 0 anyway)"

: >"$CALLS"
if IGNORES_FLAG=1 "$mode" classic 2>/dev/null; then fail "Hyprland staying per monitor is reported"; fi
[[ ! -e $flag ]] || fail "the flag goes back when Hyprland stays per monitor"
[[ $("$mode" status) == 4.5 ]] || fail "status reports what Hyprland applied"
pass "when Omarchy's own switch ignores the flag, the mode is rolled back"

# Hyprland applied Classic though the flag is gone (it was removed by hand):
# status and toggle go by what is applied.
"$mode" classic
rm -f "$flag"
[[ $("$mode" status) == classic ]] || fail "status follows the applied mode, not the flag"
"$mode" toggle
[[ $("$mode" status) == 4.5 && ! -e $flag ]] || fail "toggle leaves the applied mode"
rm -rf "$XDG_STATE_HOME/omarchy/classic-workspaces"
"$mode" classic
rm -rf "$XDG_STATE_HOME/omarchy/classic-workspaces"
[[ $("$mode" status) == classic ]] || fail "without a record yet, status falls back to the flag"
"$mode" 4.5
pass "status and toggle go by the applied mode, and by the flag before any is recorded"

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

"$mode" classic
: >"$CALLS"
"$mode" 4.5
! grep -q move_layouts "$CALLS" || fail "nothing to move when Omarchy renumbered nothing"
"$mode" classic
: >"$CALLS"
RENUMBER=1 "$mode" 4.5
grep -qF 'o.classic_workspaces.move_layouts({ [5] = 25, })' "$CALLS" || fail "going to 4.5, the layouts follow the windows" "$(grep eval "$CALLS")"
[[ $(grep -cx reload "$CALLS") == 1 ]] || fail "no second reload when no file changed"
"$mode" classic
: >"$CALLS"
RENUMBER=1 MOVE_LAYOUT=1 "$mode" 4.5
[[ $(grep -cx reload "$CALLS") == 2 ]] || fail "a second reload applies the moved layouts"
"$mode" classic
"$mode" 4.5
rm -rf "$XDG_STATE_HOME/omarchy/workspace-layouts"
pass "going to 4.5, saved layouts follow the workspaces Omarchy renumbered"

language="$tmpdir/language"
echo pt-BR >"$language"
: >"$CALLS"
OMARCHY_LANGUAGE_FILE=$language "$mode" classic
grep -qF "notify -g 󱂬 Modo de workspaces: Classic" "$CALLS" || fail "the notification follows the picked language" "$(grep notify "$CALLS")"
"$mode" 4.5
: >"$CALLS"
if OMARCHY_LANGUAGE_FILE=$language CONFIG_ERROR=1 "$mode" classic 2>"$tmpdir/stderr"; then fail "a config load that doesn't finish is reported"; fi
grep -qF "O Hyprland não mudou para Classic" "$CALLS" || fail "the failure is notified in the picked language" "$(grep notify "$CALLS")"
grep -q "didn't switch to classic" "$tmpdir/stderr" || fail "the log stays in English"
echo es-MX >"$language"
: >"$CALLS"
OMARCHY_LANGUAGE_FILE=$language "$mode" classic
grep -qF "Espacios de trabajo: Classic" "$CALLS" || fail "es-MX falls back to es" "$(grep notify "$CALLS")"
"$mode" 4.5
for code in de '../en' ''; do
  printf '%s\n' "$code" >"$language"
  : >"$CALLS"
  OMARCHY_LANGUAGE_FILE=$language "$mode" classic
  grep -qF "notify -g 󱂬 Workspaces: Classic" "$CALLS" || fail "'$code' falls back to English" "$(grep notify "$CALLS")"
  "$mode" 4.5
done
pass "notifications follow the picked language, with the base language and English as fallbacks"

keys() { jq -r 'keys[]' "$1" | sort; }
for catalog in "$ROOT"/i18n/*.json; do
  [[ $(keys "$catalog") == "$(keys "$ROOT/i18n/en.json")" ]] || fail "$(basename "$catalog") has the same strings as en.json" "$(diff <(keys "$ROOT/i18n/en.json") <(keys "$catalog"))"
  [[ $(jq -r '."notify.notSwitched"' "$catalog") == *%1* ]] || fail "$(basename "$catalog") keeps %1 in notify.notSwitched"
done
pass "every catalog carries every string, placeholders included"

XDG_RUNTIME_DIR='' "$mode" classic
[[ -f $flag ]] || fail "switching works without XDG_RUNTIME_DIR"
"$mode" 4.5
pass "switching works without XDG_RUNTIME_DIR"
