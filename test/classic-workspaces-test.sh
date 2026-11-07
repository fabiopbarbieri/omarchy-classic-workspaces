#!/usr/bin/env bash
# Runs hypr/classic-workspaces.lua against test/fake-hyprland.lua.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_command lua

# Each case gets a fresh state home and a fresh Lua process.
run_lua() {
  local name=$1 code=$2 state="$tmpdir/state-$1"
  mkdir -p "$state" "$tmpdir/runtime-$name"
  HOME="$tmpdir/home" XDG_STATE_HOME="$state" XDG_RUNTIME_DIR="$tmpdir/runtime-$name" \
    lua -e "dofile(os.getenv('ROOT') .. '/test/fake-hyprland.lua')" -e "$code"
}

# --- Mode -------------------------------------------------------------------

run_lua flag-absent '
plug("DP-1", 1)
local m = load_plugin()
check(m.enabled == true, "no flag means per-monitor")
check(next(o.bindings) == nil, "no bindings are changed")
check(m.reconcile == nil and m.focus == nil, "o.workspaces is left alone")
' || fail "without the flag, Omarchy's per-monitor workspaces run untouched"
pass "without the flag, Omarchy's per-monitor workspaces run untouched"

run_lua step-aside '
plug("DP-1", 1)
classic()
local omarchy = { enabled = false }
local m = load_plugin(omarchy)
check(next(o.bindings) == nil and m.focus == nil, "nothing is rebound")
' || fail "when Omarchy has its own switch (o.workspaces.enabled), the plugin steps aside"
pass "when Omarchy has its own switch (o.workspaces.enabled), the plugin steps aside"

# The bar, menu and bin/mode read what the config load applied, which can
# differ from the flag: Omarchy's own switch may read it elsewhere (see the
# comment on omacom/omarchy#16213 about STATE_DIR on quattro).
run_lua applied-mismatch '
classic()
load_plugin({ enabled = true })
check(read(state("omarchy/classic-workspaces/applied")) == "4.5\n", "Omarchy kept per-monitor: 4.5 is recorded")
' || fail "the applied mode is recorded when Omarchy disagrees with the flag"
pass "the applied mode is recorded when Omarchy disagrees with the flag"

run_lua applied-omarchy-classic '
load_plugin({ enabled = false })
check(read(state("omarchy/classic-workspaces/applied")) == "classic\n", "Omarchy went global: classic is recorded")
' || fail "Omarchy's own global mode is recorded as classic"
pass "Omarchy's own global mode is recorded as classic"

run_lua applied-plugin '
load_plugin()
check(read(state("omarchy/classic-workspaces/applied")) == "4.5\n", "no flag: 4.5")
classic()
load_plugin()
check(read(state("omarchy/classic-workspaces/applied")) == "classic\n", "flag: classic")
' || fail "the plugin records the mode it applied"
pass "the plugin records the mode it applied"

run_lua applied-last '
classic()
o.rebind = function() error("a binding failed") end
pcall(load_plugin)
check(not exists(state("omarchy/classic-workspaces/applied")), "nothing is recorded")
' || fail "a load that errors before the end doesn't record classic"
pass "a load that errors before the end doesn't record classic"

run_lua classic '
plug("DP-1", 1)
classic()
local m = load_plugin()
check(m.enabled == false, "the flag means Classic")
check(type(m.reconcile) == "function", "reconcile is replaced")
check(m.workspace_id({ name = "DP-2" }, 6) == 6, "slot 6 is workspace 6 on any monitor")
' || fail "the flag turns Classic on"
pass "the flag turns Classic on"

run_lua real-paths '
classic()
load_plugin()
check(o.bindings["SUPER + code:10"], "the flag under XDG_STATE_HOME is found")
' || fail "the flag is read under XDG_STATE_HOME"
pass "the flag is read under XDG_STATE_HOME"

run_lua merged-origins '
touch(state("omarchy/monitor-workspaces-merged"))
touch(state("omarchy/monitors/workspaces-merged"))
touch(state("omarchy/monitor-workspaces"))
classic()
load_plugin()
check(not exists(state("omarchy/monitor-workspaces-merged")), "4.5 unplug origins are dropped")
check(not exists(state("omarchy/monitors/workspaces-merged")), "later unplug origins are dropped")
check(exists(state("omarchy/monitor-workspaces")), "monitor blocks are kept for going back")
' || fail "Classic drops unplug origins and keeps monitor blocks"
pass "Classic drops unplug origins and keeps monitor blocks"

run_lua switching-marker '
touch(os.getenv("XDG_RUNTIME_DIR") .. "/omarchy-classic-workspaces-switching")
load_plugin()
check(world.config.cursor and world.config.cursor.no_warps == true, "warps are off while switching")
check(world.config.cursor.warp_on_change_workspace == 0, "workspace-change warp is off while switching")
' || fail "while bin/mode switches, the cursor doesn't warp"
pass "while bin/mode switches, the cursor doesn't warp"

run_lua no-marker '
load_plugin()
check(world.config.cursor == nil, "the cursor settings are untouched")
' || fail "outside a switch, the cursor settings are the user's"
pass "outside a switch, the cursor settings are the user's"

# --- Bindings and actions ---------------------------------------------------

run_lua bindings '
plug("DP-1", 1)
plug("DP-2", 6)
world.focused = "DP-1"
window("0xa", 1)
world.active_window = "0xa"
classic()
load_plugin()
press("SUPER + code:15")
check(world.focused == "DP-2" and shows("DP-2") == 6, "Super + 6 crosses to the monitor holding 6")
press("SUPER + code:19")
check(on(10) == "DP-2", "Super + 0 opens workspace 10 on the focused monitor")
world.focused = "DP-1"
press("SUPER + SHIFT + ALT + code:12")
check(world.windows["0xa"].workspace == 3 and world.focused == "DP-1", "Super + Shift + Alt + 3 moves silently")
press("SUPER + SHIFT + code:13")
check(world.windows["0xa"].workspace == 4 and shows("DP-1") == 4, "Super + Shift + 4 moves and follows")
local tab = o.bindings["SUPER + TAB"].dispatcher.spec.workspace
local former = o.bindings["SUPER + CTRL + TAB"].dispatcher.spec.workspace
check(tab == "e+1" and former == "previous", "Tab cycles every monitor and Ctrl + Tab is global, as in 4.0.6")
' || fail "Classic bindings use global ids, as in Omarchy 4.0.6"
pass "Classic bindings use global ids, as in Omarchy 4.0.6"

run_lua actions '
plug("DP-1", 1)
plug("DP-2", 6)
world.neighbours["DP-1"] = { r = "DP-2" }
world.focused = "DP-1"
window("0xa", 1)
world.active_window = "0xa"
classic()
local m = load_plugin()
m.focus(6)()
check(world.focused == "DP-2", "o.workspaces.focus(6) crosses monitors")
check(o.bind_expressions[m.focus(6)] == "o.workspaces.focus(6)", "the keybindings menu can replay it")
world.focused = "DP-1"
m.move_window(6, false)()
check(world.windows["0xa"].workspace == 6 and world.focused == "DP-1", "move_window(6, false) stays put")
check(o.bind_expressions[m.move_window(6, false)] == "o.workspaces.move_window(6, false)", "silent moves replay")
m.focus(1)()
m.move_to_monitor("r")()
check(on(1) == "DP-2", "move_to_monitor keeps the global number")
' || fail "o.workspaces actions take global ids for scripts and the menu"
pass "o.workspaces actions take global ids for scripts and the menu"

# The real module's reload and hotplug handlers call M.reconcile through the
# table, so the no-op has to win. Only when Omarchy is installed here.
omarchy=${OMARCHY_PATH:-/usr/share/omarchy}
if [[ -f $omarchy/default/hypr/monitor-workspaces.lua ]]; then
  OMARCHY_PATH=$omarchy run_lua real-module '
  plug("DP-1", 1)
  plug("DP-2", 16)
  window("0xa", 16, "DP-2")
  classic()
  package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path
  local real = require("default.hypr.monitor-workspaces")
  load_plugin(real)
  check(world.handlers["config.reloaded"] and world.handlers["monitor.added"], "the real module registered its handlers")
  world.calls = {}
  world.handlers["config.reloaded"]()
  world.handlers["monitor.added"]({ name = "DP-2" })
  check(#world.calls == 0, "reload and hotplug dispatch nothing")
  check(ids() == "1,16", "no workspace is renumbered")
  ' || fail "with Omarchy's real module, reload and hotplug don't renumber in Classic"
  pass "with Omarchy's real module, reload and hotplug don't renumber in Classic"
else
  skip "with Omarchy's real module, reload and hotplug don't renumber in Classic" "Omarchy not installed"
fi

# --- compact ----------------------------------------------------------------

# 13 keeps its position as 3; 21 wants 1, which is taken, so it takes the
# lowest free number.
run_lua compact-position '
plug("DP-1", 1)
plug("DP-2", 13)
window("0xa", 13, "DP-2")
window("0xb", 21, "DP-2")
classic()
local m = load_plugin()
m.compact()
check(ids() == "1,2,3", "got " .. ids())
check(world.windows["0xa"].workspace == 3 and world.windows["0xb"].workspace == 2, "windows follow their workspace")
check(shows("DP-2") == 3, "the monitor still shows the same workspace")
' || fail "compact keeps the position (13 -> 3) and takes the lowest free number otherwise"
pass "compact keeps the position (13 -> 3) and takes the lowest free number otherwise"

run_lua compact-collision '
plug("DP-1", 1)
plug("DP-2", 11)
window("0xa", 11, "DP-2")
classic()
local m = load_plugin()
m.compact()
check(ids() == "1,2" and on(2) == "DP-2", "both first slots want 1; the second monitor gets 2, got " .. ids())
' || fail "compact resolves two monitors' first workspaces wanting 1"
pass "compact resolves two monitors' first workspaces wanting 1"

run_lua compact-full '
plug("DP-1", 1)
for id = 2, 10 do window("0x" .. id, id) end
window("0xb", 15)
classic()
local m = load_plugin()
m.compact()
check(on(15) and world.windows["0xb"].workspace == 15, "with 1-10 taken, 15 stays where it is")
' || fail "compact leaves a workspace above 10 when 1-10 are all taken"
pass "compact leaves a workspace above 10 when 1-10 are all taken"

run_lua compact-special '
plug("DP-1", 1)
window("0xs", -98)
window("0xa", 12)
classic()
local m = load_plugin()
m.compact()
check(world.windows["0xs"].workspace == -98, "special workspaces are left alone")
check(world.windows["0xa"].workspace == 2, "12 becomes 2")
' || fail "compact skips special workspaces"
pass "compact skips special workspaces"

run_lua compact-idempotent '
plug("DP-1", 1)
window("0xa", 13)
classic()
local m = load_plugin()
m.compact()
world.calls = {}
m.compact()
check(#world.calls == 0, "a second compact changes nothing")
' || fail "compact is idempotent"
pass "compact is idempotent"

# --- compact and saved layouts (Super + L) ----------------------------------

run_lua layouts-follow '
plug("DP-1", 1)
window("0xa", 13)
write(state("omarchy/workspace-layouts/13.lua"), "o.workspace_mode({ workspace = \"13\", mode = \"scrolling\" })\n")
write(state("omarchy/workspace-layouts/1.lua"), "o.workspace_mode({ workspace = \"1\", mode = \"dwindle\" })\n")
classic()
local m = load_plugin()
m.compact()
check(read(state("omarchy/workspace-layouts/3.lua")) == "o.workspace_mode({ workspace = \"3\", mode = \"scrolling\" })\n", "3.lua carries 13\x27s layout")
check(not exists(state("omarchy/workspace-layouts/13.lua")), "13.lua is gone")
check(read(state("omarchy/workspace-layouts/1.lua")):match("dwindle"), "a workspace that stays keeps its layout")
' || fail "compact takes the saved layout along (13.lua -> 3.lua)"
pass "compact takes the saved layout along (13.lua -> 3.lua)"

# The reported case on omacom/omarchy#16213: a stale layout for the new
# number would float tiled windows.
run_lua layouts-stale '
plug("DP-1", 1)
window("0xa", 13)
write(state("omarchy/workspace-layouts/3.lua"), "o.workspace_mode({ workspace = \"3\", mode = \"floating\" })\n")
classic()
local m = load_plugin()
m.compact()
check(not exists(state("omarchy/workspace-layouts/3.lua")), "the stale 3.lua no longer applies")
check(read(state("omarchy/workspace-layouts/classic-workspaces-set-aside/3.lua")):match("floating"), "it is set aside, not deleted")
' || fail "a stale layout under the new number is set aside, so 13 keeps the default"
pass "a stale layout under the new number is set aside, so 13 keeps the default"

run_lua layouts-both '
plug("DP-1", 1)
window("0xa", 13)
write(state("omarchy/workspace-layouts/13.lua"), "o.workspace_mode({ workspace = \"13\", mode = \"scrolling\" })\n")
write(state("omarchy/workspace-layouts/3.lua"), "o.workspace_mode({ workspace = \"3\", mode = \"floating\" })\n")
classic()
local m = load_plugin()
m.compact()
check(read(state("omarchy/workspace-layouts/3.lua")):match("scrolling"), "the moving workspace\x27s layout wins")
check(read(state("omarchy/workspace-layouts/classic-workspaces-set-aside/3.lua")):match("floating"), "the old one is set aside")
' || fail "with layouts under both numbers, the workspace that moves keeps its own"
pass "with layouts under both numbers, the workspace that moves keeps its own"

run_lua layouts-unknown '
plug("DP-1", 1)
window("0xa", 13)
write(state("omarchy/workspace-layouts/13.lua"), "-- hand-written\n")
classic()
local m = load_plugin()
m.compact()
check(read(state("omarchy/workspace-layouts/13.lua")) == "-- hand-written\n", "a file not in Omarchy\x27s format stays put")
check(not exists(state("omarchy/workspace-layouts/3.lua")), "nothing is made up for 3")
' || fail "a layout file not written by Omarchy is left alone"
pass "a layout file not written by Omarchy is left alone"

run_lua layouts-full '
plug("DP-1", 1)
for id = 2, 10 do window("0x" .. id, id) end
window("0xb", 15)
write(state("omarchy/workspace-layouts/15.lua"), "o.workspace_mode({ workspace = \"15\", mode = \"scrolling\" })\n")
classic()
local m = load_plugin()
m.compact()
check(exists(state("omarchy/workspace-layouts/15.lua")), "a workspace that keeps its number keeps its layout")
' || fail "a workspace compact can't renumber keeps its layout"
pass "a workspace compact can't renumber keeps its layout"

# Found on a real desktop: three monitors back from 4.5 Workspaces, with
# layouts saved under old and new numbers. Hyprland's workspace objects are
# live, so compact has to take the numbers before renumbering.
run_lua layouts-desktop '
plug("DP-1", 3)
plug("DP-2", 17)
plug("HDMI-A-1", 21)
for id, address in pairs({ [3] = "a", [4] = "b", [11] = "c", [12] = "d", [17] = "e" }) do window(address, id, id < 10 and "DP-1" or "DP-2") end
for id, mode in pairs({ [1] = "dwindle", [5] = "scrolling", [7] = "floating", [17] = "scrolling" }) do
  write(state("omarchy/workspace-layouts/" .. id .. ".lua"), "o.workspace_mode({ workspace = \"" .. id .. "\", mode = \"" .. mode .. "\" })\n")
end
classic()
local m = load_plugin()
m.compact()
check(ids() == "1,2,3,4,5,7", "got " .. ids())
check(read(state("omarchy/workspace-layouts/7.lua")):match("scrolling"), "7 has 17\x27s layout")
check(not exists(state("omarchy/workspace-layouts/17.lua")), "17.lua is gone")
check(read(state("omarchy/workspace-layouts/classic-workspaces-set-aside/7.lua")):match("floating"), "the old 7.lua is set aside")
check(not exists(state("omarchy/workspace-layouts/1.lua")) and not exists(state("omarchy/workspace-layouts/5.lua")), "1 and 5 now hold other workspaces, so their old layouts are set aside")
' || fail "compact on a real desktop's state moves every layout (live workspace objects)"
pass "compact on a real desktop's state moves every layout (live workspace objects)"

run_lua layouts-trade '
classic()
load_plugin()
write(state("omarchy/workspace-layouts/3.lua"), "o.workspace_mode({ workspace = \"3\", mode = \"floating\" })\n")
write(state("omarchy/workspace-layouts/13.lua"), "o.workspace_mode({ workspace = \"13\", mode = \"scrolling\" })\n")
o.classic_workspaces.move_layouts({ [3] = 13, [13] = 3 })
check(read(state("omarchy/workspace-layouts/3.lua")) == "o.workspace_mode({ workspace = \"3\", mode = \"scrolling\" })\n", "3 has 13\x27s layout")
check(read(state("omarchy/workspace-layouts/13.lua")) == "o.workspace_mode({ workspace = \"13\", mode = \"floating\" })\n", "13 has 3\x27s layout")
check(not exists(state("omarchy/workspace-layouts/classic-workspaces-set-aside/3.lua")), "nothing is set aside")
' || fail "two workspaces that trade numbers trade layouts"
pass "two workspaces that trade numbers trade layouts"

run_lua layouts-aside-kept '
plug("DP-1", 1)
window("0xa", 13)
write(state("omarchy/workspace-layouts/classic-workspaces-set-aside/3.lua"), "earlier\n")
write(state("omarchy/workspace-layouts/3.lua"), "o.workspace_mode({ workspace = \"3\", mode = \"floating\" })\n")
classic()
load_plugin().compact()
check(read(state("omarchy/workspace-layouts/classic-workspaces-set-aside/3.lua")) == "earlier\n", "the earlier one is kept")
check(read(state("omarchy/workspace-layouts/classic-workspaces-set-aside/3.1.lua")):match("floating"), "the new one goes beside it")
' || fail "setting a layout aside keeps what was set aside before"
pass "setting a layout aside keeps what was set aside before"

# Classic -> 4.5 -> Classic, with the moves bin/mode reads from where Omarchy
# put the windows: 5 on the third monitor became 25, and comes back as 5.
run_lua layouts-round-trip '
write(state("omarchy/workspace-layouts/5.lua"), "o.workspace_mode({ workspace = \"5\", mode = \"scrolling\" })\n")
plug("DP-1", 1)
plug("HDMI-A-1", 25)
window("0xa", 25, "HDMI-A-1")
load_plugin()
check(o.classic_workspaces, "the layout mover is there in 4.5 mode too")
o.classic_workspaces.move_layouts({ [5] = 25 })
check(read(state("omarchy/workspace-layouts/25.lua")):match("workspace = \"25\""), "in 4.5 the layout is under 25")
check(not exists(state("omarchy/workspace-layouts/5.lua")), "and no longer under 5")
classic()
load_plugin().compact()
check(read(state("omarchy/workspace-layouts/5.lua")) == "o.workspace_mode({ workspace = \"5\", mode = \"scrolling\" })\n", "back in Classic, 5 has it again")
check(not exists(state("omarchy/workspace-layouts/classic-workspaces-set-aside")), "nothing is set aside")
' || fail "a layout survives Classic -> 4.5 -> Classic"
pass "a layout survives Classic -> 4.5 -> Classic"
