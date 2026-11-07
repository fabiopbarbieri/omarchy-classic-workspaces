#!/usr/bin/env bash
# bin/install and bin/uninstall against a scratch HOME and stub commands.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_command jq

export HOME="$tmpdir/home" CALLS="$tmpdir/calls" PATH="$tmpdir/bin:$PATH"
# English unless a test picks a language, whatever the machine's own is.
export OMARCHY_LANGUAGE_FILE="$tmpdir/language"
mkdir -p "$tmpdir/bin" "$HOME/.config/hypr"
for command in hyprctl omarchy omarchy-shell omarchy-notification-send; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$(basename "$0") $*" >>"$CALLS"\n' >"$tmpdir/bin/$command"
done
chmod +x "$tmpdir/bin/"*

# The plugin as Omarchy installs it, so the menu's paths are the real ones.
id="$(jq -r .id "$ROOT/manifest.json")"
plugin="$HOME/.config/omarchy/plugins/$id"
mkdir -p "$(dirname "$plugin")"
cp -r "$ROOT" "$plugin"
conf="$HOME/.config/hypr/hyprland.lua"
menu="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
printf -- '-- the user config\n' >"$conf"

if "$plugin/bin/install" </dev/null 2>/dev/null; then fail "install without a terminal or --yes refuses"; fi
[[ $(cat "$conf") == "-- the user config" && ! -e $menu ]] || fail "a refused install changes nothing"
pass "install asks first, and refuses without a terminal or --yes"

"$plugin/bin/install" --yes >/dev/null
grep -q "^-- BEGIN $id$" "$conf" || fail "the Lua block is added"
head -1 "$conf" | grep -q "the user config" || fail "the user's config is kept"
ls "$conf".bak.* >/dev/null || fail "hyprland.lua is backed up"
grep -q '"setup.workspaces.classic"' "$menu" || fail "the menu entries are added"
grep -q 'bin/mode status) == classic' "$menu" || fail "the checkmarks follow bin/mode status"
pass "install adds the Lua block and the menu entries, with backups"

checked="$(grep -o '"checked":"[^"]*"' "$menu" | head -1 | sed 's/"checked":"//; s/"$//')"
HOME=$HOME bash -c "$checked" && fail "Classic is unchecked in 4.5 mode"
"$plugin/bin/mode" status >/dev/null
mkdir -p "$HOME/.local/state/omarchy/classic-workspaces"
echo classic >"$HOME/.local/state/omarchy/classic-workspaces/applied"
HOME=$HOME bash -c "$checked" || fail "Classic is checked once Classic is applied"
rm -rf "$HOME/.local/state/omarchy/classic-workspaces"
pass "the menu checkmark runs and follows the applied mode"

rm -f "$conf".bak.* "$menu".bak.*
"$plugin/bin/install" --yes >/dev/null
[[ $(grep -c "BEGIN $id" "$conf") == 1 && $(grep -c "BEGIN $id" "$menu") == 1 ]] || fail "a second install adds nothing"
! ls "$conf".bak.* "$menu".bak.* >/dev/null 2>&1 || fail "a second install makes no backups"
pass "install is idempotent"

# An install from before the checkmarks followed bin/mode status.
sed -i 's/\$(\([^)]*\) status) == classic/-f old-flag/' "$menu"
"$plugin/bin/install" --yes >/dev/null
! grep -q 'old-flag' "$menu" && [[ $(grep -c "BEGIN $id" "$menu") == 1 ]] || fail "older entries are replaced, once"
ls "$menu".bak.* >/dev/null || fail "the menu is backed up before replacing"
pass "install replaces an older install's menu entries"

labels() { sed -n "/BEGIN $id/,/END $id/p" "$menu" | grep -o '"\(label\|description\)":"[^"]*"'; }
grep -qF '"label":"Workspaces","when"' "$menu" || fail "the labels are English by default" "$(labels)"
echo fr >"$OMARCHY_LANGUAGE_FILE"
"$plugin/bin/install" --yes >/dev/null
grep -qF '"label":"Espaces de travail","searchTerms":["Workspaces"]' "$menu" || fail "a reinstall writes the labels in the picked language" "$(labels)"
grep -qF "\"description\":\"Un seul ensemble global d'espaces de travail 1-10\"" "$menu" || fail "descriptions are translated too" "$(labels)"
[[ $(grep -c "BEGIN $id" "$menu") == 1 ]] || fail "the translated entries replace the English ones"
{ echo '{'; sed -n "/BEGIN $id/,/END $id/p" "$menu" | sed '1d;$d' | sed '$ s/,$//'; echo '}'; } | jq -e . >/dev/null || fail "the translated entries are valid JSON"
echo es-MX >"$OMARCHY_LANGUAGE_FILE"
"$plugin/bin/install" --yes >/dev/null
grep -qF '"label":"Espacios de trabajo"' "$menu" || fail "a regional language falls back to its base" "$(labels)"
rm -f "$OMARCHY_LANGUAGE_FILE"
"$plugin/bin/install" --yes >/dev/null
grep -qF '"label":"Workspaces","when"' "$menu" || fail "back in English, the search term goes too" "$(labels)"
pass "the menu entries follow the language picked when install runs"

printf '  "user.entry": {"label":"Mine"},\n' >"$tmpdir/user"
sed -i "1r $tmpdir/user" "$menu"
"$plugin/bin/uninstall" --yes >/dev/null
! grep -q "$id" "$conf" || fail "the Lua block is removed"
! grep -q "BEGIN $id" "$menu" || fail "the menu entries are removed"
grep -q '"user.entry"' "$menu" || fail "the user's own menu entries stay"
grep -q "the user config" "$conf" || fail "the user's config stays"
grep -q "omarchy plugin enable omarchy.workspaces" "$CALLS" || fail "Omarchy's widget comes back"
pass "uninstall removes only its own blocks and brings back Omarchy's widget"
