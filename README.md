# Classic Workspaces

A switch for Omarchy 4.5 between two workspace modes:

- **Classic**: one global set of workspaces 1-10, as before [omacom/omarchy#15655](https://github.com/omacom/omarchy/pull/15655) (Omarchy 4.0.6). `Super + N` goes to workspace N on whichever monitor holds it, and focus and the mouse follow.
- **4.5 Workspaces**: Omarchy 4.5's per-monitor workspaces, untouched.

Pick one from the mode icon at the end of the workspace numbers in the bar (it opens a small card with a Classic toggle), from **Setup > Workspaces** in the Omarchy menu, or run `bin/mode classic`, `bin/mode 4.5`, `bin/mode toggle` or `bin/mode status`. Switching reloads Hyprland; nothing else restarts.

## What Classic changes

- Omarchy's per-monitor workspace manager stops renumbering and moving workspaces (`o.workspaces.reconcile` becomes a no-op).
- The bindings go back to 4.0.6: `Super + 1-0`, `Super + Shift + 1-0`, `Super + Shift + Alt + 1-0`, `Super + Tab` / `Super + Shift + Tab` across all monitors, `Super + Ctrl + Tab` to the previous workspace, `Super + scroll`, and `Super + Shift + Alt + arrows` to move a workspace to another monitor.
- `o.workspaces.focus(N)` and friends take global ids, for scripts and the keybindings menu.
- The bar shows the same global ids on every monitor: 1-5 plus any other existing workspace. In 4.5 Workspaces mode it behaves as Omarchy's own widget.
- Switching to Classic renumbers workspaces numbered 11+ into 1-10 so the number keys reach them. Switching back lets Omarchy renumber them into per-monitor blocks again.

`Super + Shift + Ctrl + arrows` (move window to monitor) came with #15655 but does not depend on per-monitor numbering, so it stays. `Ctrl + Alt + Delete` (close all) still lands on the focused monitor's first workspace, since that script ships with Omarchy.

A workspace that doesn't exist yet opens on the focused monitor, as in 4.0.6. To pin workspaces to monitors, add Hyprland workspace rules to `~/.config/hypr/monitors.lua`.

## Install

```sh
omarchy plugin add https://github.com/fabiopbarbieri/omarchy-classic-workspaces
~/.config/omarchy/plugins/io.github.fabiopbarbieri.classic-workspaces/bin/install
```

The install script appends a marked block to the end of `~/.config/hypr/hyprland.lua` and adds Setup > Workspaces to `~/.config/omarchy/extensions/omarchy-menu.jsonc` (backing both up first), and replaces the bar's workspace widget. It doesn't change the mode.

The mode is a flag file, `~/.local/state/omarchy/toggles/no-monitor-workspaces`: present means Classic. It is the flag proposed in [omacom/omarchy#16213](https://github.com/omacom/omarchy/pull/16213), so the choice carries over if Omarchy ships that switch, and the Lua part then steps aside.

## Remove

```sh
~/.config/omarchy/plugins/io.github.fabiopbarbieri.classic-workspaces/bin/uninstall
omarchy plugin remove io.github.fabiopbarbieri.classic-workspaces
```

Run `uninstall` first: it switches to 4.5 Workspaces, removes the block from `hyprland.lua` and the menu entries, and brings back `omarchy.workspaces`.

## Requirements

Omarchy 4.5 or later (Lua Hyprland config, `o.rebind`, `o.workspaces`), `jq`. No network access, no sudo. The bar reads Omarchy's monitor block file from both its 4.5 location (`~/.local/state/omarchy/monitor-workspaces`) and its later one (`~/.local/state/omarchy/monitors/workspaces`).

Strings are in `i18n/` (English and Brazilian Portuguese).

MIT licensed. `Workspaces.qml` is Omarchy 4.5's widget with the global-mode change from #16213; Omarchy's copyright notice is kept in `LICENSE`.
