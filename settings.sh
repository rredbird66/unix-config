#!/usr/bin/env bash
#
# linux-settings — локальные настройки Fedora Workstation / GNOME Wayland.
#
# Команды:
#   ./settings.sh status  — только чтение
#   ./settings.sh apply   — применить настройки
#   ./settings.sh undo    — убрать только то, что добавил скрипт
#
set -euo pipefail
umask 077

readonly XKB_SCHEMA='org.gnome.desktop.input-sources'
readonly XKB_KEY='xkb-options'
readonly XKB_TOKEN='grp:alt_shift_toggle'

readonly MEDIA_SCHEMA='org.gnome.settings-daemon.plugins.media-keys'
readonly MEDIA_KEY='custom-keybindings'
readonly KB_SCHEMA='org.gnome.settings-daemon.plugins.media-keys.custom-keybinding'
readonly KB_ROOT='/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/'

readonly TARGET_NAME='Ptyxis'
readonly TARGET_COMMAND='ptyxis --new-window --maximize'
readonly TARGET_BINDING='<Alt>t'

# custom0 намеренно не рассматривается как свободный: на Fedora он может быть
# занят ярлыком, которого нет в списке custom-keybindings.
readonly MIN_CUSTOM_INDEX=1
readonly MAX_CUSTOM_INDEX=99

readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/linux-settings"
readonly STATE_FILE="$STATE_DIR/state.sh"

readonly KB_PATH_RE="^${KB_ROOT}custom[1-9][0-9]?/$"

usage() {
   cat <<'EOF'
Использование: ./settings.sh {status|apply|undo}

  status  показать состояние настроек (ничего не меняет)
  apply   применить настройки
  undo    убрать изменения, сделанные скриптом

Скрипт запускается обычным пользователем из графической сессии, без sudo.
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

require_gsettings() {
   command -v gsettings >/dev/null 2>&1 ||
      die "не найден gsettings. Установите glib2 и повторите запуск."
}

require_ptyxis() {
   command -v ptyxis >/dev/null 2>&1 ||
      die "не найден ptyxis. Установите Ptyxis и повторите запуск. Ничего не изменено."
}

require_custom_schema() {
   if ! gsettings get "${KB_SCHEMA}:${KB_ROOT}custom0/" name >/dev/null 2>&1; then
      die "недоступна схема ${KB_SCHEMA} (нужен gnome-settings-daemon). Ничего не изменено."
   fi
}

gvariant_string() {
   printf "'%s'" "$1"
}

# ---------------------------------------------------------------------------
# XKB: список опций org.gnome.desktop.input-sources xkb-options
# ---------------------------------------------------------------------------

get_xkb_options() {
   gsettings get "$XKB_SCHEMA" "$XKB_KEY"
}

xkb_has_token() {
   local options=$1
   case $options in
      *"'$XKB_TOKEN'"*) return 0 ;;
      *) return 1 ;;
   esac
}

xkb_add_token() {
   local options=$1
   if [[ $options == '@as []' || $options == '[]' || $options == '[ ]' ]]; then
      printf "['%s']" "$XKB_TOKEN"
   else
      printf "%s, '%s']" "${options%]}" "$XKB_TOKEN"
   fi
}

xkb_remove_token() {
   local options=$1
   local quoted="'$XKB_TOKEN'"

   options=${options//"$quoted, "/}
   options=${options//", $quoted"/}
   options=${options//"$quoted"/}

   if [[ $options == '[]' || $options == '[ ]' || $options == '@as []' ]]; then
      printf '@as []'
   else
      printf '%s' "$options"
   fi
}

# ---------------------------------------------------------------------------
# Пользовательские ярлыки GNOME
# ---------------------------------------------------------------------------

get_custom_list() {
   gsettings get "$MEDIA_SCHEMA" "$MEDIA_KEY"
}

custom_list_has_path() {
   local list=$1
   local path=$2
   local quoted="'$path'"
   [[ $list == *"$quoted"* ]]
}

custom_list_add_path() {
   local list=$1
   local path=$2

   if [[ $list == '@as []' || $list == '[]' || $list == '[ ]' ]]; then
      printf "['%s']" "$path"
   else
      printf "%s, '%s']" "${list%]}" "$path"
   fi
}

custom_list_remove_path() {
   local list=$1
   local path=$2
   local quoted="'$path'"

   list=${list//"$quoted, "/}
   list=${list//", $quoted"/}
   list=${list//"$quoted"/}

   if [[ $list == '[]' || $list == '[ ]' || $list == '@as []' ]]; then
      printf '@as []'
   else
      printf '%s' "$list"
   fi
}

unquote_gvariant() {
   local value=$1
   if ((${#value} >= 2)) && [[ ${value:0:1} == "'" && ${value: -1} == "'" ]]; then
      value=${value:1:${#value}-2}
   fi
   printf '%s' "$value"
}

get_entry_value() {
   local path=$1
   local key=$2
   local raw

   raw=$(gsettings get "${KB_SCHEMA}:${path}" "$key") || return 1
   unquote_gvariant "$raw"
}

normalize_binding() {
   local binding=${1//[[:space:]]/}
   if [[ $binding == *'>'* ]]; then
      local modifiers=${binding%>*}
      local key=${binding##*>}
      printf '%s>%s' "${modifiers,,}" "$key"
   else
      printf '%s' "$binding"
   fi
}

binding_eq() {
   local left
   local right
   left=$(normalize_binding "$1")
   right=$(normalize_binding "$2")
   [[ $left == "$right" ]]
}

# Считает команду подходящей, если это ptyxis с ровно нужными аргументами.
# Допускается полный путь (/usr/bin/ptyxis), лишние пробелы не важны.
command_eq() {
   local command=$1
   local -a words=()
   local args=''
   local i

   read -r -a words <<<"$command" || true
   if ((${#words[@]} == 0)); then
      return 1
   fi
   if [[ ${words[0]##*/} != 'ptyxis' ]]; then
      return 1
   fi
   for ((i = 1; i < ${#words[@]}; i++)); do
      args="${args:+$args }${words[i]}"
   done
   [[ $args == '--new-window --maximize' ]]
}

CUSTOM_PATHS=()
SUITABLE_PATH=''
SUITABLE_NAME=''
SUITABLE_COMMAND=''
CONFLICT_PATH=''
CONFLICT_NAME=''
CONFLICT_COMMAND=''

load_custom_paths() {
   local list=$1
   CUSTOM_PATHS=()
   mapfile -t CUSTOM_PATHS < <(
      printf '%s\n' "$list" | grep -oE "'[^']+'" | tr -d "'" || true
   )
}

scan_custom_bindings() {
   local path binding command name

   SUITABLE_PATH=''
   SUITABLE_NAME=''
   SUITABLE_COMMAND=''
   CONFLICT_PATH=''
   CONFLICT_NAME=''
   CONFLICT_COMMAND=''

   for path in "${CUSTOM_PATHS[@]}"; do
      if ! binding=$(get_entry_value "$path" binding); then
         die "не удалось прочитать binding ярлыка $path. Ничего не изменено."
      fi
      if ! binding_eq "$binding" "$TARGET_BINDING"; then
         continue
      fi

      if ! command=$(get_entry_value "$path" command); then
         die "не удалось прочитать command ярлыка $path. Ничего не изменено."
      fi
      if ! name=$(get_entry_value "$path" name); then
         die "не удалось прочитать name ярлыка $path. Ничего не изменено."
      fi

      if command_eq "$command"; then
         if [[ -z $SUITABLE_PATH ]]; then
            SUITABLE_PATH=$path
            SUITABLE_NAME=$name
            SUITABLE_COMMAND=$command
         fi
      elif [[ -z $CONFLICT_PATH && ! ( $KB_MODE == 'created' && $path == "$KB_PATH" ) ]]; then
         CONFLICT_PATH=$path
         CONFLICT_NAME=$name
         CONFLICT_COMMAND=$command
      fi
   done
}

# Ищет свободный слот customN, начиная с custom1. Путь считается занятым,
# если он есть в списке или если в нём уже лежат непустые значения.
# Ошибка чтения GSettings не считается пустым слотом.
find_free_custom_path() {
   local list=$1
   local i path name command binding

   for ((i = MIN_CUSTOM_INDEX; i <= MAX_CUSTOM_INDEX; i++)); do
      path="${KB_ROOT}custom${i}/"
      if custom_list_has_path "$list" "$path"; then
         continue
      fi

      if ! name=$(get_entry_value "$path" name); then
         die "не удалось прочитать name ярлыка $path. Ничего не изменено."
      fi
      if ! command=$(get_entry_value "$path" command); then
         die "не удалось прочитать command ярлыка $path. Ничего не изменено."
      fi
      if ! binding=$(get_entry_value "$path" binding); then
         die "не удалось прочитать binding ярлыка $path. Ничего не изменено."
      fi
      if [[ -z $name && -z $command && -z $binding ]]; then
         printf '%s' "$path"
         return 0
      fi
   done
   return 1
}

# Проверяет, активен ли созданный скриптом ярлык и совпадает ли он с тем,
# что записывал скрипт (имя не учитывается: переименование не мешает работе).
OWNED_ACTIVE=0
OWNED_MATCHES=0
check_owned_entry() {
   local list=$1
   local binding command

   OWNED_ACTIVE=0
   OWNED_MATCHES=0
   if [[ $KB_MODE == 'created' && -n $KB_PATH ]] && custom_list_has_path "$list" "$KB_PATH"; then
      OWNED_ACTIVE=1
      if ! binding=$(get_entry_value "$KB_PATH" binding); then
         die "не удалось прочитать binding ярлыка $KB_PATH. Ничего не изменено."
      fi
      if ! command=$(get_entry_value "$KB_PATH" command); then
         die "не удалось прочитать command ярлыка $KB_PATH. Ничего не изменено."
      fi
      if binding_eq "$binding" "$TARGET_BINDING" && command_eq "$command"; then
         OWNED_MATCHES=1
      fi
   fi
}

# Незавершённый apply или undo может оставить часть полей. Если хотя бы
# одно непустое поле изменили, весь слот оставляем как есть.
owned_fields_compatible() {
   local name=$1 command=$2 binding=$3
   [[ ( -z $name || $name == "$KB_NAME" ) &&
      ( -z $command || $command == "$KB_COMMAND" ) &&
      ( -z $binding || $binding == "$KB_BINDING" ) ]]
}

# ---------------------------------------------------------------------------
# Сведения о сделанных изменениях (вне репозитория)
# ---------------------------------------------------------------------------

XKB_ADDED=0
KB_MODE='none'
KB_PATH=''
KB_NAME=''
KB_COMMAND=''
KB_BINDING=''

# Раскодирует значение, записанное printf %q. Это данные, не код: никакой
# shell-код из файла не выполняется. Пустая строка может быть записана как ''.
state_decode() {
   local raw=$1
   local out=''
   local i ch

   if [[ $raw == "''" ]]; then
      printf ''
      return 0
   fi
   if [[ ${raw:0:2} == "\$'" ]]; then
      return 1
   fi

   for ((i = 0; i < ${#raw}; i++)); do
      ch=${raw:i:1}
      if [[ $ch == \\ ]]; then
         i=$((i + 1))
         ((${#raw} > i)) || return 1
         ch=${raw:i:1}
      fi
      out+=$ch
   done
   printf '%s' "$out"
}

load_state() {
   XKB_ADDED=0
   KB_MODE='none'
   KB_PATH=''
   KB_NAME=''
   KB_COMMAND=''
   KB_BINDING=''

   [[ -e $STATE_FILE ]] || return 0
   [[ -f $STATE_FILE && -r $STATE_FILE ]] ||
      die "не удалось прочитать файл состояния: $STATE_FILE"

   local line key raw value version_seen=0
   local raw_name='' raw_command='' raw_binding=''
   while IFS= read -r line || [[ -n $line ]]; do
      [[ -z $line || $line == \#* ]] && continue
      if [[ ! $line =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
         # Неизвестные строки не выполняются и не влияют на настройки.
         continue
      fi
      key=${BASH_REMATCH[1]}
      raw=${BASH_REMATCH[2]}
      case $key in
         KB_NAME) raw_name=$raw; continue ;;
         KB_COMMAND) raw_command=$raw; continue ;;
         KB_BINDING) raw_binding=$raw; continue ;;
         STATE_VERSION | XKB_ADDED | KB_MODE | KB_PATH) ;;
         *) continue ;;
      esac
      if ! value=$(state_decode "$raw"); then
         die "повреждён файл состояния $STATE_FILE: не удалось разобрать $key"
      fi
      ((${#value} <= 4096)) ||
         die "повреждён файл состояния $STATE_FILE: слишком длинное значение $key"

      case $key in
         STATE_VERSION)
            [[ $value == '1' ]] ||
               die "неизвестный формат файла состояния: $STATE_FILE"
            version_seen=1
            ;;
         XKB_ADDED)
            case $value in
               '' | 0) XKB_ADDED=0 ;;
               1) XKB_ADDED=1 ;;
               *) die "повреждён файл состояния $STATE_FILE: XKB_ADDED=$value" ;;
            esac
            ;;
         KB_MODE)
            value=${value:-none}
            case $value in
               none | created | preexisting) KB_MODE=$value ;;
               *) die "повреждён файл состояния $STATE_FILE: KB_MODE=$value" ;;
            esac
            ;;
         KB_PATH) KB_PATH=$value ;;
      esac
   done <"$STATE_FILE"

   ((version_seen)) ||
      die "неизвестный формат файла состояния (нет STATE_VERSION=1): $STATE_FILE"
   if [[ $KB_MODE != 'none' && -z $KB_PATH ]]; then
      die "повреждён файл состояния $STATE_FILE: для KB_MODE=$KB_MODE нет KB_PATH"
   fi
   if [[ $KB_MODE == 'created' ]]; then
      [[ $KB_PATH =~ $KB_PATH_RE ]] ||
         die "повреждён файл состояния $STATE_FILE: недопустимый KB_PATH"
      if ! KB_NAME=$(state_decode "$raw_name") ||
         ! KB_COMMAND=$(state_decode "$raw_command") ||
         ! KB_BINDING=$(state_decode "$raw_binding") ||
         [[ $KB_NAME != "$TARGET_NAME" || $KB_COMMAND != "$TARGET_COMMAND" || $KB_BINDING != "$TARGET_BINDING" ]]; then
         die "повреждён файл состояния $STATE_FILE: неизвестные параметры созданного ярлыка"
      fi
   fi
}

# Возвращает 1 при ошибке, не завершая процесс: вызывающий решает, можно ли
# откатить уже сделанные изменения.
save_state() {
   local tmp

   if ! mkdir -p -- "$STATE_DIR"; then
      warn "не удалось создать каталог состояния $STATE_DIR"
      return 1
   fi
   if ! chmod 700 -- "$STATE_DIR"; then
      warn "не удалось выставить права на $STATE_DIR"
      return 1
   fi
   tmp=$(mktemp "$STATE_DIR/state.XXXXXX") || {
      warn "не удалось создать временный файл состояния в $STATE_DIR"
      return 1
   }

   if ! {
      printf 'STATE_VERSION=1\n'
      printf 'XKB_ADDED=%q\n' "$XKB_ADDED"
      printf 'KB_MODE=%q\n' "$KB_MODE"
      printf 'KB_PATH=%q\n' "$KB_PATH"
      printf 'KB_NAME=%q\n' "$KB_NAME"
      printf 'KB_COMMAND=%q\n' "$KB_COMMAND"
      printf 'KB_BINDING=%q\n' "$KB_BINDING"
   } >"$tmp"; then
      rm -f -- "$tmp"
      warn "не удалось записать файл состояния $tmp"
      return 1
   fi

   if ! chmod 600 -- "$tmp"; then
      rm -f -- "$tmp"
      warn "не удалось выставить права на $tmp"
      return 1
   fi
   if ! mv -fT -- "$tmp" "$STATE_FILE"; then
      rm -f -- "$tmp"
      warn "не удалось сохранить файл состояния $STATE_FILE"
      return 1
   fi
   return 0
}

# ---------------------------------------------------------------------------
# Блокировка от одновременных apply/undo
# ---------------------------------------------------------------------------

acquire_lock() {
   command -v flock >/dev/null 2>&1 ||
      die "не найдена команда flock (нужен util-linux)."
   mkdir -p -- "$STATE_DIR" ||
      die "не удалось создать каталог состояния $STATE_DIR"
   chmod 700 -- "$STATE_DIR" ||
      die "не удалось выставить права на $STATE_DIR"

   # Каталог не заменяется во время сохранения состояния. Блокировка
   # освободится при выходе процесса, в том числе при его прерывании.
   exec {LOCK_FD}<"$STATE_DIR" ||
      die "не удалось открыть каталог для блокировки: $STATE_DIR"
   flock -x -w 10 "$LOCK_FD" ||
      die "не удалось получить блокировку $STATE_DIR; повторите запуск."
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------

cmd_status() {
   require_gsettings
   require_custom_schema
   load_state

   local xkb_options
   local custom_list
   if ! xkb_options=$(get_xkb_options); then
      die "не удалось прочитать $XKB_SCHEMA $XKB_KEY"
   fi
   if ! custom_list=$(get_custom_list); then
      die "не удалось прочитать $MEDIA_SCHEMA $MEDIA_KEY"
   fi
   load_custom_paths "$custom_list"
   scan_custom_bindings
   check_owned_entry "$custom_list"

   say "linux-settings — статус"
   say ""
   say "Раскладка (Alt+Shift):"
   say "  xkb-options: $xkb_options"
   if xkb_has_token "$xkb_options"; then
      if [[ ${XKB_ADDED:-0} == 1 ]]; then
         say "  Состояние: включено (grp:alt_shift_toggle добавлен скриптом)."
      else
         say "  Состояние: включено (было настроено до запуска скрипта)."
      fi
   else
      say "  Состояние: не настроено (нет grp:alt_shift_toggle)."
   fi

   say ""
   say "Терминал (Alt+T):"
   if command -v ptyxis >/dev/null 2>&1; then
      say "  ptyxis: $(command -v ptyxis)"
   else
      say "  ptyxis: не найден в PATH"
   fi

   if [[ -n $CONFLICT_PATH ]]; then
      say "  Состояние: Alt+T занят другим пользовательским ярлыком."
      say "    ярлык: ${CONFLICT_NAME:-без имени} ($CONFLICT_PATH)"
      say "    команда: ${CONFLICT_COMMAND:-пустая}"
   elif [[ -n $SUITABLE_PATH ]]; then
      say "  Состояние: настроено."
      say "    ярлык: ${SUITABLE_NAME:-без имени} ($SUITABLE_PATH)"
      say "    команда: $SUITABLE_COMMAND"
      if [[ $KB_MODE == 'created' && $SUITABLE_PATH == "$KB_PATH" ]]; then
         say "    источник: создан скриптом"
      elif [[ $KB_MODE == 'preexisting' && $SUITABLE_PATH == "$KB_PATH" ]]; then
         say "    источник: был настроен до запуска скрипта"
      else
         say "    источник: найден существующий ярлык"
      fi
   elif ((OWNED_ACTIVE && !OWNED_MATCHES)); then
      say "  Состояние: не настроено; созданный скриптом ярлык изменён вручную."
      say "    ярлык: ${KB_PATH} (оставлен как есть)"
   else
      say "  Состояние: не настроено; Alt+T свободен."
   fi

   say ""
   if [[ -f $STATE_FILE ]]; then
      say "Сведения об изменениях: $STATE_FILE"
   else
      say "Сведения об изменениях: нет (скрипт ещё не применялся)."
   fi
}

# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------

apply_failure() {
   local message=$1
   if [[ -f $STATE_FILE ]]; then
      die "$message. Сведения об уже сделанных изменениях сохранены; выполните ./settings.sh undo."
   fi
   die "$message. Ничего не изменено."
}

check_custom_list_unchanged() {
   local current
   if ! current=$(get_custom_list); then
      apply_failure "не удалось перечитать ${MEDIA_KEY}"
   fi
   if [[ $current != "$1" ]]; then
      apply_failure "список ярлыков изменился во время настройки; повторите apply"
   fi
}

cmd_apply() {
   require_gsettings
   require_ptyxis
   require_custom_schema

   acquire_lock
   load_state

   local custom_list
   if ! custom_list=$(get_custom_list); then
      die "не удалось прочитать $MEDIA_SCHEMA $MEDIA_KEY. Ничего не изменено."
   fi
   load_custom_paths "$custom_list"
   scan_custom_bindings
   check_owned_entry "$custom_list"

   if [[ -n $CONFLICT_PATH ]]; then
      die "Alt+T уже занят другим пользовательским ярлыком «${CONFLICT_NAME:-без имени}» (${CONFLICT_PATH}, команда: ${CONFLICT_COMMAND:-пустая}). Ничего не изменено."
   fi

   local skip_keybinding=0
   if ((OWNED_ACTIVE && !OWNED_MATCHES)); then
      warn "созданный скриптом ярлык ${KB_PATH} изменён вручную; оставляю его как есть и не создаю дубликат."
      skip_keybinding=1
   fi

   local new_path=''
   local resume_key=0
   if ((!skip_keybinding)) && [[ -z $SUITABLE_PATH ]]; then
      if [[ $KB_MODE == 'created' ]] && ((!OWNED_ACTIVE)); then
         local name command binding
         if ! name=$(get_entry_value "$KB_PATH" name) ||
            ! command=$(get_entry_value "$KB_PATH" command) ||
            ! binding=$(get_entry_value "$KB_PATH" binding); then
            die "не удалось прочитать данные прежнего ярлыка $KB_PATH. Ничего не изменено."
         fi
         if owned_fields_compatible "$name" "$command" "$binding"; then
            new_path=$KB_PATH
            resume_key=1
         fi
      fi
      if [[ -z $new_path ]] && ! new_path=$(find_free_custom_path "$custom_list"); then
         die "не удалось найти свободный пользовательский ярлык (проверены custom${MIN_CUSTOM_INDEX}…custom${MAX_CUSTOM_INDEX}). Ничего не изменено."
      fi
   fi

   local changes=0
   local xkb_before
   if ! xkb_before=$(get_xkb_options); then
      die "не удалось прочитать $XKB_SCHEMA $XKB_KEY. Ничего не изменено."
   fi

   if ! xkb_has_token "$xkb_before"; then
      local xkb_after
      xkb_after=$(xkb_add_token "$xkb_before")
      XKB_ADDED=1
      save_state || die "не удалось подготовить состояние для изменения XKB. Ничего не изменено."
      if ! gsettings set "$XKB_SCHEMA" "$XKB_KEY" "$xkb_after"; then
         apply_failure "не удалось записать $XKB_KEY"
      fi
      changes=1
      say "Раскладка: добавлен grp:alt_shift_toggle (Alt+Shift)."
   else
      say "Раскладка: grp:alt_shift_toggle уже присутствует, изменений нет."
   fi

   if ((skip_keybinding)); then
      say "Терминал: ярлык оставлен как есть (изменён вручную)."
   elif [[ -n $SUITABLE_PATH ]]; then
      say "Терминал: Alt+T уже настроен (${SUITABLE_PATH}), изменений нет."
      if [[ $KB_MODE == 'none' ]]; then
         KB_MODE='preexisting'
         KB_PATH=$SUITABLE_PATH
         save_state || apply_failure "не удалось сохранить сведения о найденном ярлыке"
      fi
   elif [[ -n $new_path ]]; then
      check_custom_list_unchanged "$custom_list"
      local current_name current_command current_binding
      if ! current_name=$(get_entry_value "$new_path" name) ||
         ! current_command=$(get_entry_value "$new_path" command) ||
         ! current_binding=$(get_entry_value "$new_path" binding); then
         apply_failure "не удалось перечитать данные ярлыка $new_path"
      fi
      if ((resume_key)); then
         owned_fields_compatible "$current_name" "$current_command" "$current_binding" ||
            apply_failure "поля ярлыка $new_path изменились во время настройки; повторите apply"
      elif [[ -n $current_name || -n $current_command || -n $current_binding ]]; then
         apply_failure "слот ярлыка $new_path заняли во время настройки; повторите apply"
      fi

      # Запись состояния заранее: если запись полей или списка не удастся,
      # undo всё равно будет знать путь и ожидаемые значения.
      KB_MODE='created'
      KB_PATH=$new_path
      KB_NAME=$TARGET_NAME
      KB_COMMAND=$TARGET_COMMAND
      KB_BINDING=$TARGET_BINDING
      save_state || apply_failure "не удалось сохранить сведения о ярлыке ${new_path}; ярлык не активирован"

      if ! gsettings set "${KB_SCHEMA}:${new_path}" name "$(gvariant_string "$TARGET_NAME")"; then
         apply_failure "не удалось записать имя ярлыка ${new_path}; ярлык не активирован"
      fi
      if ! gsettings set "${KB_SCHEMA}:${new_path}" command "$(gvariant_string "$TARGET_COMMAND")"; then
         apply_failure "не удалось записать команду ярлыка ${new_path}; ярлык не активирован"
      fi
      if ! gsettings set "${KB_SCHEMA}:${new_path}" binding "$(gvariant_string "$TARGET_BINDING")"; then
         apply_failure "не удалось записать сочетание ярлыка ${new_path}; ярлык не активирован"
      fi

      local new_list
      new_list=$(custom_list_add_path "$custom_list" "$new_path")
      check_custom_list_unchanged "$custom_list"
      if ! gsettings set "$MEDIA_SCHEMA" "$MEDIA_KEY" "$new_list"; then
         apply_failure "не удалось добавить ${new_path} в ${MEDIA_KEY}"
      fi

      changes=1
      say "Терминал: создан ярлык ${new_path} (Alt+T → ${TARGET_COMMAND})."
   fi

   if ((!changes && !skip_keybinding)); then
      say "Готово: обе настройки уже были в нужном состоянии."
   else
      say "Готово."
   fi
}

# ---------------------------------------------------------------------------
# undo
# ---------------------------------------------------------------------------

undo_owned_key() {
   require_custom_schema

   local name command binding
   if ! name=$(get_entry_value "$KB_PATH" name) ||
      ! command=$(get_entry_value "$KB_PATH" command) ||
      ! binding=$(get_entry_value "$KB_PATH" binding); then
      die "не удалось прочитать данные ярлыка $KB_PATH; состояние сохранено"
   fi

   local custom_list
   if ! custom_list=$(get_custom_list); then
      die "не удалось прочитать $MEDIA_SCHEMA $MEDIA_KEY"
   fi
   if custom_list_has_path "$custom_list" "$KB_PATH"; then
      if [[ $name != "$KB_NAME" || $command != "$KB_COMMAND" || $binding != "$KB_BINDING" ]]; then
         say "Терминал: созданный скриптом ярлык изменён вручную — оставляю как есть."
         return
      fi
      local new_list
      new_list=$(custom_list_remove_path "$custom_list" "$KB_PATH")
      gsettings set "$MEDIA_SCHEMA" "$MEDIA_KEY" "$new_list" ||
         die "не удалось убрать ${KB_PATH} из ${MEDIA_KEY}"
   elif ! owned_fields_compatible "$name" "$command" "$binding"; then
      say "Терминал: поля незарегистрированного ярлыка изменены вручную — оставляю как есть."
      return
   fi

   # Если сброс не удался, следующий undo продолжит без перезаписи списка
   # и без сброса уже пустых полей.
   local field
   for field in name command binding; do
      [[ -n ${!field} ]] || continue
      gsettings reset "${KB_SCHEMA}:${KB_PATH}" "$field" ||
         die "не удалось сбросить $field ярлыка ${KB_PATH}; состояние сохранено"
   done
   say "Терминал: ярлык ${KB_PATH} больше не настроен."
}

cmd_undo() {
   if [[ ! -d $STATE_DIR ]]; then
      say "Нечего откатывать: сведений о изменениях нет ($STATE_FILE)."
      return 0
   fi

   acquire_lock

   if [[ ! -f $STATE_FILE ]]; then
      say "Нечего откатывать: сведения об изменениях уже удалены."
      return 0
   fi
   require_gsettings
   load_state

   if [[ ${XKB_ADDED:-0} == 1 ]]; then
      local current
      if ! current=$(get_xkb_options); then
         die "не удалось прочитать $XKB_SCHEMA $XKB_KEY"
      fi
      if xkb_has_token "$current"; then
         local updated
         updated=$(xkb_remove_token "$current")
         if ! gsettings set "$XKB_SCHEMA" "$XKB_KEY" "$updated"; then
            die "не удалось удалить grp:alt_shift_toggle из $XKB_KEY"
         fi
         say "Раскладка: удалён grp:alt_shift_toggle."
      else
         say "Раскладка: grp:alt_shift_toggle уже отсутствует."
      fi
      XKB_ADDED=0
      save_state || die "откат XKB выполнен, но не удалось обновить состояние $STATE_FILE"
   else
      say "Раскладка: настройка была до запуска скрипта — оставляю как есть."
   fi

   if [[ $KB_MODE == 'created' ]]; then
      undo_owned_key
   elif [[ $KB_MODE == 'preexisting' ]]; then
      say "Терминал: ярлык был настроен до запуска скрипта — оставляю как есть."
   else
      say "Терминал: скрипт не создавал ярлык."
   fi

   rm -f -- "$STATE_FILE" || die "не удалось удалить файл состояния $STATE_FILE"
   say "Сведения об изменениях удалены: $STATE_FILE"
}

# ---------------------------------------------------------------------------

main() {
   if (($# != 1)); then
      usage >&2
      exit 2
   fi

   case $1 in
      status) cmd_status ;;
      apply) cmd_apply ;;
      undo) cmd_undo ;;
      -h | --help | help) usage ;;
      *)
         printf 'Неизвестная команда: %s\n\n' "$1" >&2
         usage >&2
         exit 2
         ;;
   esac
}

main "$@"
