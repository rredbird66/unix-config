#!/usr/bin/env bash
#
# vim/setup.sh — разворачивает vim/vimrc в ~/.vimrc с резервной копией.
#
# Запуск: make vim  (или ./vim/setup.sh)
set -euo pipefail
umask 022

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SELF_DIR/.." && pwd)
readonly SELF_DIR REPO_DIR
readonly SOURCE="$REPO_DIR/vim/vimrc"

[[ -n ${HOME:-} ]] || {
   printf 'Ошибка: не задан HOME.\n' >&2
   exit 1
}
readonly TARGET="$HOME/.vimrc"

CHECK_ONLY=0

usage() {
   cat <<'EOF'
Использование: ./vim/setup.sh [--check]

  --check  только сравнить ~/.vimrc с vim/vimrc, ничего не записывая

Без sudo. Если ~/.vimrc уже совпадает, файл и резервные копии не трогаются.
Перед изменением существующего ~/.vimrc создаётся копия
~/.vimrc.linux-settings-backup.<дата-время>.
EOF
}

die() {
   printf 'Ошибка: %s\n' "$*" >&2
   exit 1
}

say() {
   printf '%s\n' "$*"
}

resolve_path() {
   local path=$1 resolved
   if [[ -L $path ]]; then
      resolved=$(readlink -f -- "$path" 2>/dev/null) || resolved=''
      [[ -n $resolved ]] || die "не удалось разрешить симлинк $path"
      printf '%s' "$resolved"
   else
      printf '%s' "$path"
   fi
}

backup_file() {
   local path=$1 stamp target n=1
   stamp=$(date +%Y%m%d-%H%M%S)
   target="$path.linux-settings-backup.$stamp"
   while [[ -e $target || -L $target ]]; do
      target="$path.linux-settings-backup.$stamp.$n"
      n=$((n + 1))
   done
   cp -p -- "$path" "$target" || die "не удалось создать резервную копию $path"
   printf '%s' "$target"
}

replace_file() {
   local src=$1 dest=$2 mode=$3
   local real dir tmp
   real=$(resolve_path "$dest")
   [[ -d $real ]] && die "$dest — каталог, ожидался файл"
   dir=$(dirname -- "$real")
   mkdir -p -- "$dir" || die "не удалось создать каталог $dir"
   tmp=$(mktemp "$dir/.linux-settings.XXXXXX") ||
      die "не удалось создать временный файл в $dir"
   if ! cp -- "$src" "$tmp"; then
      rm -f -- "$tmp"
      die "не удалось записать временный файл $tmp"
   fi
   if ! chmod "$mode" "$tmp"; then
      rm -f -- "$tmp"
      die "не удалось выставить права на $tmp"
   fi
   if ! mv -f -- "$tmp" "$real"; then
      rm -f -- "$tmp"
      die "не удалось заменить $dest"
   fi
}

file_mode() {
   local path=$1
   stat -c '%a' -- "$path" 2>/dev/null || printf '644'
}

main() {
   while (($# > 0)); do
      case $1 in
         --check) CHECK_ONLY=1 ;;
         -h | --help | help)
            usage
            return 0
            ;;
         *)
            printf 'Неизвестный аргумент: %s\n\n' "$1" >&2
            usage >&2
            return 2
            ;;
      esac
      shift
   done

   [[ -f $SOURCE ]] || die "не найден $SOURCE"

   local real=''
   if [[ -L $TARGET ]]; then
      real=$(resolve_path "$TARGET")
   elif [[ -e $TARGET ]]; then
      real=$TARGET
   fi
   if [[ -n $real && -d $real ]]; then
      die "$TARGET — каталог, ожидался файл"
   fi

   if [[ -n $real && -f $real ]] && cmp -s -- "$SOURCE" "$real"; then
      say "~/.vimrc уже совпадает с vim/vimrc, изменений нет."
      return 0
   fi

   if ((CHECK_ONLY)); then
      if [[ -n $real && -f $real ]]; then
         say "~/.vimrc отличается от vim/vimrc."
      else
         say "~/.vimrc отсутствует."
      fi
      return 1
   fi

   local mode=0644
   if [[ -n $real && -f $real ]]; then
      local backup
      backup=$(backup_file "$real")
      say "Резервная копия ~/.vimrc: $backup"
      mode=$(file_mode "$real")
   fi

   replace_file "$SOURCE" "$TARGET" "$mode"
   say "Конфигурация Vim записана: $TARGET"
   say "Проверка: vim -Nu ~/.vimrc -n +q  (или make vim-check)"
}

main "$@"
