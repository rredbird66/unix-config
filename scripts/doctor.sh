#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
result=0

run_check() {
   local title=$1
   shift
   printf '\n%s\n' "$title"
   if ! "$@"; then
      result=1
   fi
}

show_backups() {
   local path=$1 resolved
   local -a backups=("$path".linux-settings-backup.*)
   if [[ -L $path ]] && resolved=$(readlink -f -- "$path"); then
      backups+=("$resolved".linux-settings-backup.*)
   fi

   printf '%s:\n' "$path"
   if ((${#backups[@]})); then
      printf '  %s\n' "${backups[@]}"
   else
      printf '  резервных копий нет\n'
   fi
}

run_check 'Пакеты' ./scripts/packages.sh --check
run_check 'Bash и Starship' ./shell/setup.sh --check
run_check 'Vim' ./vim/setup.sh --check
run_check 'GNOME' ./settings.sh status

printf '\nРезервные копии\n'
shopt -s nullglob
show_backups "$HOME/.bashrc"
show_backups "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
show_backups "$HOME/.vimrc"
exit "$result"
