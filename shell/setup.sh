#!/usr/bin/env bash
#
# shell/setup.sh — установка Starship без sudo и управляемый блок в ~/.bashrc.
#
# Запуск: make shell  (или ./shell/setup.sh)
set -euo pipefail
umask 022

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SELF_DIR/.." && pwd)
readonly SELF_DIR REPO_DIR

readonly SHELL_DIR="$REPO_DIR/shell"
readonly STARSHIP_CONFIG_SRC="$SHELL_DIR/starship.toml"
readonly LEGACY_BASHRC="$SHELL_DIR/bashrc.example"

readonly STARSHIP_VERSION='1.27.0'
readonly STARSHIP_ASSET_X86_64='starship-x86_64-unknown-linux-gnu.tar.gz'
readonly STARSHIP_SHA256_X86_64='3b94758850901717eb36aa1b53f8492c1322506ec6d41273bc6151e79ed8e4a1'
readonly STARSHIP_ASSET_AARCH64='starship-aarch64-unknown-linux-musl.tar.gz'
readonly STARSHIP_SHA256_AARCH64='341f5cbf24699fa0b27ec88965ad25f862ea09e15d35a543fd6ffdff1d2aa00d'
readonly STARSHIP_RELEASE_URL="https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}"

readonly BLOCK_BEGIN='# >>> linux-settings starship >>>'
readonly BLOCK_END='# <<< linux-settings starship <<<'

[[ -n ${HOME:-} ]] || {
   printf 'Ошибка: не задан HOME.\n' >&2
   exit 1
}

readonly BIN_DIR="$HOME/.local/bin"
readonly STARSHIP_BIN="$BIN_DIR/starship"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly STARSHIP_CONFIG="$CONFIG_DIR/starship.toml"
readonly BASHRC="$HOME/.bashrc"
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/linux-settings"

FORCE_CONFIG=0
CHECK_ONLY=0
WORK_DIR=''

usage() {
   cat <<'EOF'
Использование: ./shell/setup.sh [--check] [--force-config]

  --check         только проверить Starship, конфиг и блок в ~/.bashrc
  --force-config  заменить существующий чужой ~/.config/starship.toml
                  (перед заменой делается резервная копия)

Без sudo. Бинарник ставится в ~/.local/bin, конфиг — в
${XDG_CONFIG_HOME:-~/.config}/starship.toml, в ~/.bashrc добавляется
управляемый блок. Повторный запуск ничего не меняет.
EOF
}

die() {
   printf 'Ошибка: %s\n' "$*" >&2
   exit 1
}

say() {
   printf '%s\n' "$*"
}

warn() {
   printf 'Внимание: %s\n' "$*" >&2
}

cleanup() {
   if [[ -n $WORK_DIR && -d $WORK_DIR ]]; then
      rm -rf -- "$WORK_DIR"
   fi
}
trap cleanup EXIT

make_work_dir() {
   if [[ -n $WORK_DIR && -d $WORK_DIR ]]; then
      return 0
   fi
   WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/linux-settings-starship.XXXXXX") ||
      die "не удалось создать временный каталог"
}

resolve_path() {
   local path=$1
   if [[ -L $path ]]; then
      local resolved
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

# Заменяет содержимое dest, сохраняя симлинк dest (пишет в его цель).
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

# ---------------------------------------------------------------------------
# Starship binary
# ---------------------------------------------------------------------------

starship_ok() {
   [[ -x $STARSHIP_BIN ]] || return 1
   local out
   out=$("$STARSHIP_BIN" --version 2>/dev/null) || return 1
   [[ $out == "starship $STARSHIP_VERSION"* ]]
}

verify_sha256() {
   local file=$1 expected=$2 actual
   actual=$(sha256sum -- "$file" | awk '{print $1}')
   if [[ $actual != "$expected" ]]; then
      warn "неверная SHA-256 для $file: ожидалась $expected, получена $actual"
      return 1
   fi
}

install_starship() {
   if starship_ok; then
      say "Starship $STARSHIP_VERSION уже установлен: $STARSHIP_BIN"
      return 0
   fi

   local machine asset expected
   machine=$(uname -m)
   case $machine in
      x86_64 | amd64)
         asset=$STARSHIP_ASSET_X86_64
         expected=$STARSHIP_SHA256_X86_64
         ;;
      aarch64 | arm64)
         asset=$STARSHIP_ASSET_AARCH64
         expected=$STARSHIP_SHA256_AARCH64
         ;;
      *)
         die "нет проверенного архива Starship $STARSHIP_VERSION для архитектуры $machine. Установите Starship вручную и повторите запуск."
         ;;
   esac

   if [[ -L $STARSHIP_BIN ]]; then
      die "$STARSHIP_BIN — симлинк, но версия не $STARSHIP_VERSION. Не перезаписываю симлинк; замените его вручную."
   fi
   if [[ -e $STARSHIP_BIN && ! -f $STARSHIP_BIN ]]; then
      die "$STARSHIP_BIN существует и не является обычным файлом. Ничего не изменено."
   fi

   local tool
   for tool in curl tar sha256sum install; do
      command -v "$tool" >/dev/null 2>&1 ||
         die "не найдена команда $tool (нужны curl, tar, sha256sum и install)."
   done

   mkdir -p -- "$BIN_DIR" || die "не удалось создать $BIN_DIR"
   mkdir -p -- "$CACHE_DIR" || die "не удалось создать $CACHE_DIR"
   make_work_dir

   local archive="$CACHE_DIR/$asset"
   if [[ -f $archive ]] && verify_sha256 "$archive" "$expected"; then
      say "Использую ранее скачанный и проверенный архив: $archive"
   else
      rm -f -- "$archive.part"
      say "Скачиваю Starship $STARSHIP_VERSION для $machine…"
      if ! curl -fL --retry 2 --proto '=https' --tlsv1.2 \
         -o "$archive.part" "$STARSHIP_RELEASE_URL/$asset"; then
         rm -f -- "$archive.part"
         die "не удалось скачать $STARSHIP_RELEASE_URL/$asset. Существующий бинарник не изменён."
      fi
      if ! verify_sha256 "$archive.part" "$expected"; then
         rm -f -- "$archive.part"
         die "архив Starship не прошёл проверку SHA-256. Установка отменена, существующий бинарник не изменён."
      fi
      mv -f -- "$archive.part" "$archive" ||
         die "не удалось сохранить архив в $archive"
   fi

   local extract="$WORK_DIR/extract"
   mkdir -p -- "$extract" || die "не удалось создать $extract"
   tar -xzf "$archive" -C "$extract" ||
      die "не удалось распаковать $archive"

   local binary="$extract/starship"
   if [[ ! -f $binary ]]; then
      binary=$(find "$extract" -type f -name starship -print -quit)
   fi
   [[ -n $binary && -f $binary ]] ||
      die "в архиве Starship не найден бинарник starship"

   local version
   version=$("$binary" --version 2>/dev/null) ||
      die "скачанный бинарник Starship не запускается"
   [[ $version == "starship $STARSHIP_VERSION"* ]] ||
      die "скачанный бинарник сообщает «$version», ожидалась версия $STARSHIP_VERSION"

   local tmp
   tmp=$(mktemp "$BIN_DIR/.starship.XXXXXX") ||
      die "не удалось создать временный файл в $BIN_DIR"
   if ! install -m 0755 -- "$binary" "$tmp"; then
      rm -f -- "$tmp"
      die "не удалось подготовить $STARSHIP_BIN"
   fi
   if ! mv -f -- "$tmp" "$STARSHIP_BIN"; then
      rm -f -- "$tmp"
      die "не удалось заменить $STARSHIP_BIN"
   fi
   say "Starship $STARSHIP_VERSION установлен: $STARSHIP_BIN"
}

# ---------------------------------------------------------------------------
# Starship config
# ---------------------------------------------------------------------------

config_conflict() {
   [[ -e $STARSHIP_CONFIG || -L $STARSHIP_CONFIG ]] || return 0
   [[ -d $STARSHIP_CONFIG ]] && return 1
   cmp -s -- "$STARSHIP_CONFIG_SRC" "$STARSHIP_CONFIG"
}

check_config() {
   if config_conflict; then
      return 0
   fi
   if ((FORCE_CONFIG)); then
      return 0
   fi
   die "Файл $STARSHIP_CONFIG уже существует и отличается от конфига linux-settings. Не перезаписываю его молча. Сравните файлы вручную или запустите с --force-config (будет сделана резервная копия)."
}

install_config() {
   if [[ -e $STARSHIP_CONFIG || -L $STARSHIP_CONFIG ]]; then
      if config_conflict; then
         say "Конфиг Starship уже совпадает: $STARSHIP_CONFIG"
         return 0
      fi
      if [[ -d $STARSHIP_CONFIG ]]; then
         die "$STARSHIP_CONFIG — каталог, ожидался файл"
      fi
      local real backup
      real=$(resolve_path "$STARSHIP_CONFIG")
      if [[ -e $real ]]; then
         backup=$(backup_file "$real")
         say "Резервная копия конфига: $backup"
      fi
   fi

   replace_file "$STARSHIP_CONFIG_SRC" "$STARSHIP_CONFIG" 0644
   say "Конфиг Starship записан: $STARSHIP_CONFIG"
}

# ---------------------------------------------------------------------------
# ~/.bashrc
# ---------------------------------------------------------------------------

make_block() {
   local block=$1
   cat >"$block" <<'EOF'
# >>> linux-settings starship >>>
# Управляется linux-settings (make shell); не редактируйте блок вручную.
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
# <<< linux-settings starship <<<
EOF
}

legacy_init_lines() {
   local out=$1
   : >"$out"
   if [[ -f $LEGACY_BASHRC ]]; then
      grep -F -- 'oh-my-posh --init' "$LEGACY_BASHRC" >"$out" || true
   else
      printf '%s\n' \
         'eval "$(~/.oh_my_posh/oh-my-posh --init --shell bash --config ~/.poshthemes/paradox.omp.json)"' \
         >>"$out"
   fi
}

# Формирует ожидаемый .bashrc в $2, не изменяя настоящий файл.
build_bashrc() {
   local output=$1
   local source_file=$2
   local block="$WORK_DIR/block"
   local legacy="$WORK_DIR/legacy"
   local stripped="$WORK_DIR/stripped"

   make_block "$block"
   legacy_init_lines "$legacy"

   if [[ -f $source_file ]]; then
      if [[ -s $legacy ]]; then
         grep -F -x -v -f "$legacy" -- "$source_file" >"$stripped" || true
      else
         cat -- "$source_file" >"$stripped"
      fi
   else
      : >"$stripped"
   fi

   local begins ends
   begins=$(grep -F -x -c -- "$BLOCK_BEGIN" "$stripped" || true)
   ends=$(grep -F -x -c -- "$BLOCK_END" "$stripped" || true)
   [[ -n $begins ]] || begins=0
   [[ -n $ends ]] || ends=0
   if ((begins != ends)); then
      die "в $source_file повреждён управляемый блок linux-settings (начало: $begins, конец: $ends). Файл не изменён."
   fi

   awk -v begin="$BLOCK_BEGIN" -v end="$BLOCK_END" -v blockfile="$block" '
      BEGIN {
         while ((getline line < blockfile) > 0) {
            block = block line ORS
         }
         close(blockfile)
         inserted = 0
         inside = 0
      }
      $0 == begin && !inside {
         if (!inserted) {
            printf "%s", block
            inserted = 1
         }
         inside = 1
         next
      }
      inside {
         if ($0 == end) {
            inside = 0
         }
         next
      }
      { print }
      END {
         if (!inserted) {
            printf "%s", block
         }
      }
   ' "$stripped" >"$output"
}

warn_other_posh() {
   local file=$1
   local line number
   while IFS= read -r line; do
      number=${line%%:*}
      warn "в $file осталась другая инициализация Oh My Posh (строка $number): ${line#*:}. Она не изменялась; при необходимости удалите её вручную."
   done < <(grep -nE '^[[:space:]]*(eval|source)[[:space:]].*oh-my-posh.*--init' "$file" || true)
}

update_bashrc() {
   make_work_dir
   local candidate="$WORK_DIR/bashrc.new"
   local current_real=''

   if [[ -L $BASHRC ]]; then
      current_real=$(resolve_path "$BASHRC")
   elif [[ -e $BASHRC ]]; then
      current_real=$BASHRC
   fi

   build_bashrc "$candidate" "$current_real"

   if [[ -n $current_real ]] && cmp -s -- "$candidate" "$current_real"; then
      say "Блок Starship в ~/.bashrc уже актуален."
   else
      if [[ -n $current_real && -e $current_real ]]; then
         local backup
         backup=$(backup_file "$current_real")
         say "Резервная копия ~/.bashrc: $backup"
         replace_file "$candidate" "$BASHRC" "$(file_mode "$current_real")"
         say "Блок Starship обновлён в ~/.bashrc."
      elif [[ -n $current_real ]]; then
         # ~/.bashrc — висячий симлинк: создаём его цель, сам симлинк сохраняем.
         replace_file "$candidate" "$BASHRC" 0644
         say "Создан целевой файл для ~/.bashrc (симлинк сохранён)."
      else
         replace_file "$candidate" "$BASHRC" 0644
         say "Создан ~/.bashrc с блоком Starship."
      fi
   fi

   warn_other_posh "$BASHRC"
}

# ---------------------------------------------------------------------------
# --check
# ---------------------------------------------------------------------------

check_all() {
   local failed=0
   if starship_ok; then
      say "OK  бинарник: $STARSHIP_BIN ($STARSHIP_VERSION)"
   else
      warn "бинарник Starship $STARSHIP_VERSION не найден или не запускается: $STARSHIP_BIN"
      failed=1
   fi

   if [[ -e $STARSHIP_CONFIG || -L $STARSHIP_CONFIG ]] && config_conflict; then
      say "OK  конфиг: $STARSHIP_CONFIG"
   else
      warn "конфиг отсутствует или отличается: $STARSHIP_CONFIG"
      failed=1
   fi

   make_work_dir
   local candidate="$WORK_DIR/bashrc.check"
   local real=''
   [[ -L $BASHRC ]] && real=$(resolve_path "$BASHRC")
   [[ -z $real && -e $BASHRC ]] && real=$BASHRC
   build_bashrc "$candidate" "$real"
   if [[ -n $real ]] && cmp -s -- "$candidate" "$real"; then
      say "OK  ~/.bashrc: управляемый блок актуален"
   else
      warn "~/.bashrc: управляемый блок отсутствует или устарел"
      failed=1
   fi
   return "$failed"
}

main() {
   while (($# > 0)); do
      case $1 in
         --check) CHECK_ONLY=1 ;;
         --force-config) FORCE_CONFIG=1 ;;
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

   if ((CHECK_ONLY)); then
      check_all
      return
   fi

   check_config
   install_starship
   install_config
   update_bashrc

   say ""
   say "Готово. Откройте новый интерактивный Bash или выполните: source ~/.bashrc"
   say "Проверка: make shell-check (или ./shell/setup.sh --check)"
}

main "$@"
