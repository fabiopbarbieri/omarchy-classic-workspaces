-- A small model of Hyprland for hypr/classic-workspaces.lua: monitors,
-- workspaces and windows, with what the plugin leans on. A workspace that
-- doesn't exist is created on the focused monitor, and an empty one nobody
-- shows goes away. Dispatchers are plain tables, so bindings can be inspected
-- and run.
--
-- Modelled on the fake in omacom/omarchy's
-- test/shell.d/hyprland-monitor-workspaces-test.sh.

package.path = os.getenv("ROOT") .. "/test/?.lua;" .. package.path

world = { monitors = {}, workspaces = {}, windows = {}, neighbours = {}, handlers = {}, config = {}, calls = {} }

local function monitor_named(name)
  for _, monitor in ipairs(world.monitors) do
    if monitor.name == name then return monitor end
  end
end

local function workspace_numbered(id)
  for _, workspace in ipairs(world.workspaces) do
    if workspace.id == id then return workspace end
  end
end

local function create(id, monitor)
  local workspace = { id = id, monitor = monitor, special = id < 0 }
  world.workspaces[#world.workspaces + 1] = workspace
  return workspace
end

local function windows_on(id)
  local count = 0
  for _, window in pairs(world.windows) do
    if window.workspace == id then count = count + 1 end
  end
  return count
end

local function cleanup()
  local kept = {}
  for _, workspace in ipairs(world.workspaces) do
    local monitor = monitor_named(workspace.monitor)
    if workspace.special or windows_on(workspace.id) > 0 or (monitor and monitor.active == workspace.id) then
      kept[#kept + 1] = workspace
    end
  end
  world.workspaces = kept
end

local function resolve(id)
  return workspace_numbered(id) or create(id, world.focused)
end

-- Live, as Hyprland's are: a workspace object reads its current state, so
-- after change_id its id is the new one.
local function workspace_object(workspace)
  if not workspace then return nil end
  return setmetatable({}, { __index = function(_, key)
    if key == "id" then return workspace.id end
    if key == "name" then return tostring(workspace.id) end
    if key == "special" then return workspace.special end
    if key == "windows" then return windows_on(workspace.id) end
    if key == "monitor" then return { name = workspace.monitor } end
  end })
end

local run = {}

function run.focus(spec)
  if spec.monitor then
    world.focused = spec.monitor
    return
  end
  local workspace = resolve(tonumber(spec.workspace))
  monitor_named(workspace.monitor).active = workspace.id
  world.focused = workspace.monitor
  cleanup()
end

function run.window_move(spec)
  local workspace = resolve(tonumber(spec.workspace))
  world.windows[world.active_window].workspace = workspace.id
  if spec.follow ~= false then
    monitor_named(workspace.monitor).active = workspace.id
    world.focused = workspace.monitor
  end
  cleanup()
end

function run.workspace_move(spec)
  local name = (world.neighbours[world.focused] or {})[spec.monitor] or spec.monitor
  local target = monitor_named(name)
  if not target then error("Monitor not found") end
  local from = monitor_named(world.focused)
  local workspace = workspace_numbered(from.active)
  workspace.monitor = target.name
  target.active = workspace.id
  from.active = nil
  for _, other in ipairs(world.workspaces) do
    if other.monitor == from.name then from.active = other.id break end
  end
  if not from.active then from.active = create(1000 + #world.workspaces, from.name).id end
  world.focused = target.name
  cleanup()
end

function run.change_id(spec)
  if workspace_numbered(spec.id) then error("workspace " .. spec.id .. " already exists") end
  local workspace = workspace_numbered(tonumber(spec.workspace))
  local old = workspace.id
  workspace.id = spec.id
  for _, monitor in ipairs(world.monitors) do
    if monitor.active == old then monitor.active = spec.id end
  end
  for _, window in pairs(world.windows) do
    if window.workspace == old then window.workspace = spec.id end
  end
end

local function dispatcher(kind)
  return function(spec) return { kind = kind, spec = spec } end
end

hl = {
  on = function(name, handler) world.handlers[name] = handler end,
  config = function(values)
    for section, options in pairs(values) do
      world.config[section] = world.config[section] or {}
      for key, value in pairs(options) do world.config[section][key] = value end
    end
  end,
  dispatch = function(d)
    world.calls[#world.calls + 1] = d.kind
    run[d.kind](d.spec)
  end,
  get_workspace = function(id) return workspace_object(workspace_numbered(tonumber(id))) end,
  get_workspaces = function()
    local list = {}
    for _, workspace in ipairs(world.workspaces) do list[#list + 1] = workspace_object(workspace) end
    return list
  end,
  get_active_monitor = function() return { name = world.focused } end,
  dsp = {
    focus = dispatcher("focus"),
    window = { move = dispatcher("window_move") },
    workspace = { move = dispatcher("workspace_move"), change_id = dispatcher("change_id") },
  },
}

-- What Omarchy provides before the plugin loads. The real paths module when
-- OMARCHY_PATH is given, so its XDG handling is the one tested.
o = { bind_expressions = {}, bindings = {} }
function o.rebind(keys, description, d)
  o.bindings[keys] = { description = description, dispatcher = d }
end
function o.shell_quote(value) return "'" .. value .. "'" end

local omarchy = os.getenv("OMARCHY_PATH")
if omarchy and io.open(omarchy .. "/default/hypr/paths.lua", "r") then
  package.path = omarchy .. "/?.lua;" .. package.path
else
  package.preload["default.hypr.paths"] = function()
    local state = os.getenv("XDG_STATE_HOME")
    return { home = os.getenv("HOME"), state_home = (state and state ~= "") and state or os.getenv("HOME") .. "/.local/state" }
  end
end

-- --- Helpers for the tests --------------------------------------------------

function plug(name, active)
  world.monitors[#world.monitors + 1] = { name = name, active = active }
  if not workspace_numbered(active) then create(active, name) end
  world.focused = world.focused or name
end

function window(address, id, monitor)
  if not workspace_numbered(id) then create(id, monitor or world.focused) end
  world.windows[address] = { workspace = id }
end

function on(id)
  local workspace = workspace_numbered(id)
  return workspace and workspace.monitor
end

function shows(name) return monitor_named(name).active end

function ids()
  local list = {}
  for _, workspace in ipairs(world.workspaces) do
    if not workspace.special then list[#list + 1] = workspace.id end
  end
  table.sort(list)
  return table.concat(list, ",")
end

function state(path) return os.getenv("XDG_STATE_HOME") .. "/" .. path end

function touch(path)
  os.execute("mkdir -p '" .. path:match("^(.*)/") .. "'")
  local file = assert(io.open(path, "w"))
  file:close()
end

function exists(path)
  local file = io.open(path, "r")
  if file then file:close() end
  return file ~= nil
end

function write(path, content)
  os.execute("mkdir -p '" .. path:match("^(.*)/") .. "'")
  local file = assert(io.open(path, "w"))
  file:write(content)
  file:close()
end

function read(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("a")
  file:close()
  return content
end

-- Load the plugin as hyprland.lua does, on top of `workspaces` as Omarchy's
-- o.workspaces (a bare table unless given).
function load_plugin(workspaces)
  o.workspaces = workspaces or {}
  dofile(os.getenv("ROOT") .. "/hypr/classic-workspaces.lua")
  return o.workspaces
end

function classic(on_)
  local flag = state("omarchy/toggles/no-monitor-workspaces")
  if on_ == false then os.remove(flag) else touch(flag) end
end

-- Run a binding the way Hyprland would.
function press(keys)
  local binding = assert(o.bindings[keys], "no binding for " .. keys)
  hl.dispatch(binding.dispatcher)
end

function check(condition, message)
  if not condition then error(message, 2) end
end
