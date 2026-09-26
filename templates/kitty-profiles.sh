#!/usr/bin/env bash
# Managed by setup-ubuntu-workstation: kitty's profile menu (Ctrl+Shift+Space),
# like the new-tab dropdown of Windows Terminal. Arguments: the profiles as
# "Label|command|shortcut"; the hosts in ~/.ssh/config are added. The choice
# opens in a new tab.
set -euo pipefail
entries=("$@")
while read -r host; do
  entries+=("ssh $host|kitten ssh $host|")
done < <(awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/) print $i }' \
  "$HOME/.ssh/config" 2>/dev/null | sort -u)
labels=()
for entry in "${entries[@]}"; do
  IFS='|' read -r label _ keys <<<"$entry"
  labels+=("$(printf '%-30s %s' "$label" "$keys")")
done
pick=""
if command -v fzf >/dev/null; then
  pick="$(printf '%s\n' "${labels[@]}" | fzf --prompt='New tab > ' --layout=reverse --no-info --no-sort)" || exit 0
else
  PS3='New tab: '
  select pick in "${labels[@]}"; do [[ -n "$pick" ]] && break; done
fi
for i in "${!labels[@]}"; do
  [[ "${labels[$i]}" == "$pick" ]] || continue
  IFS='|' read -r _ cmd _ <<<"${entries[$i]}"
  read -ra argv <<<"$cmd"
  exec kitten @ launch --type=tab --cwd="$HOME" "${argv[@]}"
done
