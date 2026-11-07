# shellcheck shell=bash
# Sourced by bin/mode and bin/install. t KEY [ARGS...] prints a string in the
# language picked under Setup > Language, read the way omarchy-i18n reads it,
# from the plugin's own catalogs in i18n/: the language, then its base (es-MX
# to es), then English, then the key. %1, %2... are replaced by ARGS.
i18n="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/i18n"
language=en
language_file=${OMARCHY_LANGUAGE_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/language}
if [[ -f $language_file ]]; then
  read -r language <"$language_file" || true
  language=${language//[[:space:]]/}
  [[ $language =~ ^[a-z]{2,3}(-[A-Za-z]{2})?$ ]] || language=en
fi
t() {
  local key=$1 string="" catalog i
  shift
  for catalog in "$i18n/$language.json" "$i18n/${language%%-*}.json" "$i18n/en.json"; do
    [[ -f $catalog ]] || continue
    string="$(jq -r --arg key "$key" '.[$key] // empty | strings' "$catalog" 2>/dev/null)" || string=""
    [[ -n $string ]] && break
  done
  [[ -n $string ]] || string=$key
  for (( i = 1; i <= $#; i++ )); do
    string=${string//%$i/"${!i}"}
  done
  printf '%s' "$string"
}
