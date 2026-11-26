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

   if ! raw=$(gsettings get "${KB_SCHEMA}:${path}" "$key" 2>/dev/null); then
      return 1
   fi
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
OWNED_MODIFIED=0
OWNED_MODIFIED_PATH=''
OWNED_MODIFIED_NAME=''
OWNED_MODIFIED_COMMAND=''

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
   OWNED_MODIFIED=0
   OWNED_MODIFIED_PATH=''
   OWNED_MODIFIED_NAME=''
   OWNED_MODIFIED_COMMAND=''

   for path in "${CUSTOM_PATHS[@]}"; do
      binding=$(get_entry_value "$path" binding || true)
      if ! binding_eq "$binding" "$TARGET_BINDING"; then
         continue
      fi

      command=$(get_entry_value "$path" command || true)
      name=$(get_entry_value "$path" name || true)

      if command_eq "$command"; then
         if [[ -z $SUITABLE_PATH ]]; then
            SUITABLE_PATH=$path
            SUITABLE_NAME=$name
            SUITABLE_COMMAND=$command
         fi
      elif [[ $KB_MODE == 'created' && $path == "$KB_PATH" ]]; then
         OWNED_MODIFIED=1
         OWNED_MODIFIED_PATH=$path
         OWNED_MODIFIED_NAME=$name
         OWNED_MODIFIED_COMMAND=$command
      elif [[ -z $CONFLICT_PATH ]]; then
         CONFLICT_PATH=$path
         CONFLICT_NAME=$name
         CONFLICT_COMMAND=$command
      fi
   done
}

# Ищет свободный слот customN, начиная с custom1. Путь считается занятым,
# если он есть в списке или если в нём уже лежат непустые значения.
find_free_custom_path() {
   local list=$1
   local skip_path=${2:-}
   local i path name command binding

   for ((i = MIN_CUSTOM_INDEX; i <= MAX_CUSTOM_INDEX; i++)); do
      path="${KB_ROOT}custom${i}/"
      if [[ -n $skip_path && $path == "$skip_path" ]]; then
         continue
      fi
      if custom_list_has_path "$list" "$path"; then
         continue
      fi

      name=$(get_entry_value "$path" name || true)
      command=$(get_entry_value "$path" command || true)
      binding=$(get_entry_value "$path" binding || true)
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
      binding=$(get_entry_value "$KB_PATH" binding || true)
      command=$(get_entry_value "$KB_PATH" command || true)
      if binding_eq "$binding" "$TARGET_BINDING" && command_eq "$command"; then
         OWNED_MATCHES=1
      fi
   fi
}

# ---------------------------------------------------------------------------
# Сведения о сделанных изменениях (вне репозитория)
# ---------------------------------------------------------------------------

STATE_VERSION=0
XKB_ADDED=0
KB_MODE='none'
KB_PATH=''
KB_NAME=''
KB_COMMAND=''
KB_BINDING=''

load_state() {
   STATE_VERSION=0
   XKB_ADDED=0
   KB_MODE='none'
   KB_PATH=''
   KB_NAME=''
   KB_COMMAND=''
   KB_BINDING=''

   if [[ -f $STATE_FILE ]]; then
      # shellcheck disable=SC1090
      source "$STATE_FILE"
      if [[ ${STATE_VERSION:-0} != 1 ]]; then
         die "неизвестный формат файла состояния: $STATE_FILE"
      fi
      [[ -n ${KB_MODE:-} ]] || KB_MODE='none'
      [[ -n ${XKB_ADDED:-} ]] || XKB_ADDED=0
   fi
}

save_state() {
   local tmp

   mkdir -p "$STATE_DIR" || die "не удалось создать каталог состояния $STATE_DIR"
   chmod 700 "$STATE_DIR" || die "не удалось выставить права на $STATE_DIR"
   tmp=$(mktemp "$STATE_DIR/state.XXXXXX") ||
      die "не удалось создать временный файл состояния в $STATE_DIR"

   {
      printf 'STATE_VERSION=1\n'
      printf 'XKB_ADDED=%q\n' "$XKB_ADDED"
      printf 'KB_MODE=%q\n' "$KB_MODE"
      printf 'KB_PATH=%q\n' "$KB_PATH"
      printf 'KB_NAME=%q\n' "$KB_NAME"
      printf 'KB_COMMAND=%q\n' "$KB_COMMAND"
      printf 'KB_BINDING=%q\n' "$KB_BINDING"
   } >"$tmp" || die "не удалось записать файл состояния $tmp"

   chmod 600 "$tmp" || die "не удалось выставить права на $tmp"
   mv -f "$tmp" "$STATE_FILE" || die "не удалось сохранить файл состояния $STATE_FILE"
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

cmd_apply() {
   require_gsettings
   require_ptyxis
   require_custom_schema

   local state_present=0
   if [[ -f $STATE_FILE ]]; then
      state_present=1
   fi
   load_state

   local xkb_before
   local custom_list
   if ! xkb_before=$(get_xkb_options); then
      die "не удалось прочитать $XKB_SCHEMA $XKB_KEY. Ничего не изменено."
   fi
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

   local need_xkb=0
   if ! xkb_has_token "$xkb_before"; then
      need_xkb=1
   fi

   local create_kb=0
   local new_path=''
   if ((!skip_keybinding)); then
      if [[ -z $SUITABLE_PATH ]]; then
         local skip_path=''
         if [[ $KB_MODE == 'created' && -n $KB_PATH ]]; then
            skip_path=$KB_PATH
         fi
         if ! new_path=$(find_free_custom_path "$custom_list" "$skip_path"); then
            die "не удалось найти свободный пользовательский ярлык (проверены custom${MIN_CUSTOM_INDEX}…custom${MAX_CUSTOM_INDEX}). Ничего не изменено."
         fi
         create_kb=1
      fi
   fi

   local state_dirty=0
   local changes=0

   if ((need_xkb)); then
      local xkb_after
      xkb_after=$(xkb_add_token "$xkb_before")
      if ! gsettings set "$XKB_SCHEMA" "$XKB_KEY" "$xkb_after"; then
         die "не удалось записать $XKB_KEY. Ничего не изменено."
      fi
      XKB_ADDED=1
      state_dirty=1
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
         KB_NAME=$SUITABLE_NAME
         KB_COMMAND=$SUITABLE_COMMAND
         KB_BINDING=$TARGET_BINDING
         state_dirty=1
      fi
   elif ((create_kb)); then
      if ! gsettings set "${KB_SCHEMA}:${new_path}" name "$(gvariant_string "$TARGET_NAME")"; then
         die "не удалось записать имя ярлыка ${new_path}. Ничего не изменено."
      fi
      if ! gsettings set "${KB_SCHEMA}:${new_path}" command "$(gvariant_string "$TARGET_COMMAND")"; then
         gsettings reset "${KB_SCHEMA}:${new_path}" name >/dev/null 2>&1 || true
         die "не удалось записать команду ярлыка ${new_path}. Изменения отменены."
      fi
      if ! gsettings set "${KB_SCHEMA}:${new_path}" binding "$(gvariant_string "$TARGET_BINDING")"; then
         gsettings reset "${KB_SCHEMA}:${new_path}" name >/dev/null 2>&1 || true
         gsettings reset "${KB_SCHEMA}:${new_path}" command >/dev/null 2>&1 || true
         die "не удалось записать сочетание ярлыка ${new_path}. Изменения отменены."
      fi

      local new_list
      new_list=$(custom_list_add_path "$custom_list" "$new_path")
      if ! gsettings set "$MEDIA_SCHEMA" "$MEDIA_KEY" "$new_list"; then
         gsettings reset "${KB_SCHEMA}:${new_path}" name >/dev/null 2>&1 || true
         gsettings reset "${KB_SCHEMA}:${new_path}" command >/dev/null 2>&1 || true
         gsettings reset "${KB_SCHEMA}:${new_path}" binding >/dev/null 2>&1 || true
         die "не удалось добавить ${new_path} в ${MEDIA_KEY}. Ярлык не активирован."
      fi

      KB_MODE='created'
      KB_PATH=$new_path
      KB_NAME=$TARGET_NAME
      KB_COMMAND=$TARGET_COMMAND
      KB_BINDING=$TARGET_BINDING
      state_dirty=1
      changes=1
      say "Терминал: создан ярлык ${new_path} (Alt+T → ${TARGET_COMMAND})."
   fi

   if ((!state_present || state_dirty)); then
      save_state
      say "Сведения об изменениях сохранены: $STATE_FILE"
   fi

   if ((changes == 0)); then
      say "Готово: обе настройки уже были в нужном состоянии."
   else
      say "Готово."
   fi
}

# ---------------------------------------------------------------------------
# undo
# ---------------------------------------------------------------------------

cmd_undo() {
   if [[ ! -f $STATE_FILE ]]; then
      say "Нечего откатывать: сведений о изменениях нет ($STATE_FILE)."
      return 0
   fi

   require_gsettings
   load_state

   if [[ $KB_MODE == 'created' && -n $KB_PATH ]]; then
      require_custom_schema
   fi

   local custom_list
   if ! custom_list=$(get_custom_list); then
      die "не удалось прочитать $MEDIA_SCHEMA $MEDIA_KEY"
   fi

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
   else
      say "Раскладка: настройка была до запуска скрипта — оставляю как есть."
   fi

   if [[ $KB_MODE == 'created' && -n $KB_PATH ]]; then
      if custom_list_has_path "$custom_list" "$KB_PATH"; then
         local binding command name
         binding=$(get_entry_value "$KB_PATH" binding || true)
         command=$(get_entry_value "$KB_PATH" command || true)
         name=$(get_entry_value "$KB_PATH" name || true)

         if [[ $binding == "$KB_BINDING" && $command == "$KB_COMMAND" && $name == "$KB_NAME" ]]; then
            local new_list
            new_list=$(custom_list_remove_path "$custom_list" "$KB_PATH")
            if ! gsettings set "$MEDIA_SCHEMA" "$MEDIA_KEY" "$new_list"; then
               die "не удалось убрать ${KB_PATH} из ${MEDIA_KEY}"
            fi
            gsettings reset "${KB_SCHEMA}:${KB_PATH}" name ||
               die "не удалось сбросить name ярлыка ${KB_PATH}"
            gsettings reset "${KB_SCHEMA}:${KB_PATH}" command ||
               die "не удалось сбросить command ярлыка ${KB_PATH}"
            gsettings reset "${KB_SCHEMA}:${KB_PATH}" binding ||
               die "не удалось сбросить binding ярлыка ${KB_PATH}"
            say "Терминал: удалён созданный скриптом ярлык ${KB_PATH}."
         else
            say "Терминал: созданный скриптом ярлык изменён вручную — оставляю как есть."
         fi
      else
         say "Терминал: созданного скриптом ярлыка уже нет — оставляю список как есть."
      fi
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
