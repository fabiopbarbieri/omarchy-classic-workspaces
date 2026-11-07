-- Classic Workspaces: reverts omacom/omarchy#15655 ("Give each monitor its own workspaces") from
-- the user config: one global set of workspaces, with the bindings exactly as
-- they were in Omarchy 4.0.6.
--
-- Loaded at the end of ~/.config/hypr/hyprland.lua, after Omarchy's defaults,
-- and switched with bin/mode. If Omarchy ships its own switch
-- (omacom/omarchy#16213, o.workspaces.enabled), this file steps aside.

-- While bin/mode switches modes, keep the cursor still: the reload makes
-- Omarchy move workspaces between monitors and refocus a window, and both
-- would warp the cursor. bin/mode puts the user's settings back afterwards.
local runtime = os.getenv("XDG_RUNTIME_DIR")
local switching = runtime and io.open(runtime .. "/omarchy-classic-workspaces-switching", "r")
if switching then
  switching:close()
  hl.config({ cursor = { warp_on_change_workspace = 0, no_warps = true } })
end

local M = o.workspaces
if not M then
  return
end

local paths = require("default.hypr.paths")

-- The mode this config load applied, for the bar, the menu and bin/mode,
-- which would otherwise have only the flag to go by: a load that fails, or an
-- Omarchy switch that reads the flag elsewhere, leaves Hyprland in the other
-- mode. Written last, so a load that errors before the end doesn't claim it.
local function record(mode)
  local dir = paths.state_home .. "/omarchy/classic-workspaces"
  local file = io.open(dir .. "/applied", "w")
  if not file then
    os.execute("mkdir -p '" .. dir .. "'")
    file = io.open(dir .. "/applied", "w")
  end
  if file then
    file:write(mode .. "\n")
    file:close()
  end
end

-- Saved layouts (Super + L) are files named by workspace id, so a renumbered
-- workspace takes its file along, and the new number's old file, left by a
-- workspace that no longer exists, is set aside where Omarchy doesn't load it.
-- compact uses it going to Classic, and bin/mode going to 4.5, after Omarchy
-- renumbered; the reload bin/mode runs when the files change applies them.
local layouts = paths.state_home .. "/omarchy/workspace-layouts"

local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("a")
  file:close()
  return content
end

-- Without overwriting what an earlier switch set aside.
local function set_aside(path, id)
  local aside = layouts .. "/classic-workspaces-set-aside"
  os.execute("mkdir -p '" .. aside .. "'")
  local name, n = aside .. "/" .. id .. ".lua", 1
  while read_file(name) do
    name = aside .. "/" .. id .. "." .. n .. ".lua"
    n = n + 1
  end
  os.rename(path, name)
end

-- moves: old id -> new id. Each file is written under a name Omarchy doesn't
-- load before any source goes, so a failed write loses nothing, and sources
-- go before targets are checked, so two workspaces can trade numbers.
local function move_layouts(moves)
  local jobs, stale = {}, {}
  for key, value in pairs(moves) do
    local from, to = tonumber(key), tonumber(value)
    local content = from and to and from ~= to and read_file(layouts .. "/" .. from .. ".lua")
    local renamed, count
    if content then
      renamed, count = content:gsub('workspace = "' .. from .. '"', 'workspace = "' .. to .. '"')
    end
    -- A workspace without a layout of its own shouldn't pick up the one left
    -- under its new number. A file that doesn't name its workspace as Omarchy
    -- writes it stays put.
    if from and to and from ~= to and not content then
      stale[#stale + 1] = to
    elseif content and count > 0 then
      local moving = layouts .. "/." .. to .. ".lua.moving"
      local file = io.open(moving, "w")
      if file then
        file:write(renamed)
        file:close()
        jobs[#jobs + 1] = { from = from, to = to, moving = moving }
      end
    end
  end
  for _, job in ipairs(jobs) do
    os.remove(layouts .. "/" .. job.from .. ".lua")
  end
  for _, id in ipairs(stale) do
    local target = layouts .. "/" .. id .. ".lua"
    if read_file(target) then set_aside(target, id) end
  end
  for _, job in ipairs(jobs) do
    local target = layouts .. "/" .. job.to .. ".lua"
    if read_file(target) then set_aside(target, job.to) end
    os.rename(job.moving, target)
  end
end

o.classic_workspaces = { move_layouts = move_layouts }

-- Omarchy's own switch (omacom/omarchy#16213) is in charge when it exists.
if M.enabled ~= nil then
  record(M.enabled and "4.5" or "classic")
  return
end

-- Toggleable: only with the flag (the same one #16213 reads) is anything
-- reverted. Without it, Omarchy's per-monitor workspaces run untouched.
local flag = io.open(paths.state_home .. "/omarchy/toggles/no-monitor-workspaces", "r")
M.enabled = flag == nil
if flag then
  flag:close()
else
  record("4.5")
  return
end

-- Unplug origins would point at workspaces that reuse the same global ids.
-- Omarchy 4.5 keeps them in omarchy/; later releases in omarchy/monitors/.
os.remove(paths.state_home .. "/omarchy/monitor-workspaces-merged")
os.remove(paths.state_home .. "/omarchy/monitors/workspaces-merged")

local function action(fn, expression)
  o.bind_expressions[fn] = expression
  return fn
end

-- No more renumbering or moving workspaces on reload or hotplug.
function M.reconcile() end

-- Anything that still calls o.workspaces (the keybindings menu, scripts,
-- `hyprctl dispatch 'o.workspaces.focus(3)'`) gets the global meaning.
function M.workspace_id(_, slot)
  return slot
end

function M.focus(id)
  return action(function()
    hl.dispatch(hl.dsp.focus({ workspace = tostring(id) }))
  end, "o.workspaces.focus(" .. id .. ")")
end

function M.move_window(id, follow)
  return action(function()
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(id), follow = follow ~= false }))
  end, "o.workspaces.move_window(" .. id .. (follow == false and ", false" or "") .. ")")
end

function M.move_to_monitor(direction)
  return action(function()
    hl.dispatch(hl.dsp.workspace.move({ monitor = direction }))
  end, "o.workspaces.move_to_monitor(" .. string.format("%q", direction) .. ")")
end

-- Workspaces the per-monitor mode numbered 11+ are out of reach of the number
-- keys. Renumber them into 1-10, keeping their position (13 -> 3) when free.
-- Run by bin/mode when switching to Classic.
function M.compact()
  -- Hyprland's workspace objects are live: after change_id, .id is already
  -- the new number. So take the numbers first.
  local numbers = {}
  for _, workspace in ipairs(hl.get_workspaces() or {}) do
    if not workspace.special and workspace.id > 10 then numbers[#numbers + 1] = workspace.id end
  end
  table.sort(numbers)
  local moves = {}
  for _, from in ipairs(numbers) do
    local candidates = { (from - 1) % 10 + 1 }
    for id = 1, 10 do
      candidates[#candidates + 1] = id
    end
    for _, id in ipairs(candidates) do
      if not hl.get_workspace(id) then
        hl.dispatch(hl.dsp.workspace.change_id({ workspace = tostring(from), id = id }))
        if hl.get_workspace(id) then moves[from] = id end
        break
      end
    end
  end
  move_layouts(moves)
end

-- The bindings from before #15655 (default/hypr/bindings/tiling.lua at dd07b62).
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  o.rebind("SUPER + " .. key, "Switch to workspace " .. workspace, hl.dsp.focus({ workspace = tostring(workspace) }))
  o.rebind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
  o.rebind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace), follow = false }))
end

o.rebind("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
o.rebind("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
o.rebind("SUPER + CTRL + TAB", "Former workspace", hl.dsp.focus({ workspace = "previous" }))

o.rebind("SUPER + SHIFT + ALT + LEFT", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
o.rebind("SUPER + SHIFT + ALT + RIGHT", "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))
o.rebind("SUPER + SHIFT + ALT + UP", "Move workspace to up monitor", hl.dsp.workspace.move({ monitor = "u" }))
o.rebind("SUPER + SHIFT + ALT + DOWN", "Move workspace to down monitor", hl.dsp.workspace.move({ monitor = "d" }))

o.rebind("SUPER + mouse_down", "Scroll active workspace forward", hl.dsp.focus({ workspace = "e+1" }))
o.rebind("SUPER + mouse_up", "Scroll active workspace backward", hl.dsp.focus({ workspace = "e-1" }))

-- SUPER + SHIFT + CTRL + arrows (move window to monitor) arrived with #15655
-- but doesn't depend on per-monitor numbering, so it stays.

record("classic")
