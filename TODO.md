# To do

Next, in this order. Each one has a test marked `# TODO` that turns into a pass when it's done (`test/run`).

## D. Bar and menu follow the mode Hyprland applied

The bar and the menu read the raw flag. If Omarchy ships #16213 reading the flag somewhere else (its `STATE_DIR` moved to `omarchy/monitors/` on `quattro`, [comment](https://github.com/omacom/omarchy/pull/16213#issuecomment-6684250837)), the plugin steps aside, Hyprland stays per monitor, and the bar still says Classic.

- The Lua part writes the mode it applied (e.g. `~/.local/state/omarchy/classic-workspaces/applied`), also when it steps aside, and the bar and menu read that.
- Warn when `o.workspaces.enabled` disagrees with the flag.
- Test: `the applied mode is recorded when Omarchy disagrees with the flag` in `test/classic-workspaces-test.sh`.

## Later

- `bin/mode`: check `hyprctl configerrors` after the reload and roll back on errors (`hyprctl reload` exits 0 anyway).
- `bin/mode`: notifications through `i18n/` instead of fixed English.
- Tests for `bin/install` and `bin/uninstall` against a scratch HOME.
- Going back to 4.5 Workspaces, Omarchy renumbers 3 to 13 and the saved layout stays under 3 (Omarchy's own gap, noted in #16213). `bin/mode 4.5` could record the ids before the reload and move the files after.
