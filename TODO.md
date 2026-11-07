# To do

Next, in this order. Each one has a test marked `# TODO` that turns into a pass when it's done (`test/run`).

## C. Saved layouts follow compact

`~/.local/state/omarchy/workspace-layouts/<id>.lua` is keyed by workspace id. When `compact` renumbers 13 to 3, workspace 3 picks up 3's saved layout instead of 13's, and going back to 4.5 Workspaces renumbers again without the layout. Reported on [omacom/omarchy#16213](https://github.com/omacom/omarchy/pull/16213#issuecomment-6621493715).

- In `compact`, after `change_id` X -> Y, move `X.lua` to `Y.lua` when `Y.lua` doesn't exist, with the id inside rewritten.
- Decide what to do when `Y.lua` exists (keep it, most likely).
- Test: `compact takes the saved layout along (13.lua -> 3.lua)` in `test/classic-workspaces-test.sh`.

## D. Bar and menu follow the mode Hyprland applied

The bar and the menu read the raw flag. If Omarchy ships #16213 reading the flag somewhere else (its `STATE_DIR` moved to `omarchy/monitors/` on `quattro`, [comment](https://github.com/omacom/omarchy/pull/16213#issuecomment-6684250837)), the plugin steps aside, Hyprland stays per monitor, and the bar still says Classic.

- The Lua part writes the mode it applied (e.g. `~/.local/state/omarchy/classic-workspaces/applied`), also when it steps aside, and the bar and menu read that.
- Warn when `o.workspaces.enabled` disagrees with the flag.
- Test: `the applied mode is recorded when Omarchy disagrees with the flag` in `test/classic-workspaces-test.sh`.

## Later

- `bin/mode`: check `hyprctl configerrors` after the reload and roll back on errors (`hyprctl reload` exits 0 anyway).
- `bin/mode`: notifications through `i18n/` instead of fixed English.
- Tests for `bin/install` and `bin/uninstall` against a scratch HOME.
