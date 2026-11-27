#!/usr/bin/env bash
#
# scripts/setup.sh — интерактивное меню linux-settings.
#
# Выбор хранится только в памяти до выхода. Категории можно открывать
# повторно; «Назад»/Esc отменяет только правки текущего захода. Ничего не
# устанавливается и не изменяется до итогового подтверждения.
set -euo pipefail

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SELF_DIR/.." && pwd)
readonly SELF_DIR REPO_DIR

readonly PACKAGES="$REPO_DIR/scripts/packages.sh"
readonly SHELL_SETUP="$REPO_DIR/shell/setup.sh"
readonly VIM_SETUP="$REPO_DIR/vim/setup.sh"
readonly GNOME_SETUP="$REPO_DIR/settings.sh"
readonly BACKTITLE='linux-settings — выборочная установка'

usage() {
   cat <<'EOF'
Использование: ./scripts/setup.sh

Интерактивное меню с тремя категориями:
  базовые пакеты, дополнительные утилиты и настройки.

Нужны dialog (штатный Fedora RPM, вручную: sudo dnf install dialog) и
настоящий терминал. Без меню доступны отдельные цели make packages,
make extras, make shell, make vim и make apply.

Коды выхода:
  0  выбранное применено либо пользователь штатно отменил меню
  1  ошибка (нет dialog/TTY, сбой dnf, настройки или dialog)
  2  неизвестный аргумент
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

refuse() {
   {
      printf 'make setup: %s\n\n' "$1"
      printf 'Отдельные цели без меню:\n'
      printf '  make packages  — vim-enhanced, mc, htop\n'
      printf '  make extras    — ripgrep, fd-find, fzf, zoxide, btop, tmux и Docker\n'
      printf '  make shell     — Starship и блок Bash\n'
      printf '  make vim       — ~/.vimrc, если своего файла нет\n'
      printf '  make apply     — GNOME Alt+Shift и Alt+T\n'
      printf '\nНичего не изменено.\n'
   } >&2
   exit 1
}

# ---------------------------------------------------------------------------
# Состояние меню (только в памяти текущего запуска)
# ---------------------------------------------------------------------------

declare -A SELECTED=()
declare -A TAG_CATEGORY=()
declare -A TAG_LABEL=()
declare -A TAG_SHORT=()
declare -A TAG_STATUS=()
declare -A TAG_KIND=()
RPM_TAGS=()
CONFIG_TAGS=()
ALL_TAGS=()

readonly CATEGORY_TITLE_BASE='Базовые пакеты'
readonly CATEGORY_TITLE_EXTRAS='Дополнительные утилиты'
readonly CATEGORY_TITLE_CONFIG='Настройки'

rpm_label() {
   local name=$1 state=$2 status label
   case $state in
      installed) status='уже установлен' ;;
      missing) status='не установлен' ;;
      *) die "packages.sh вернул неизвестное состояние пакета $name: $state" ;;
   esac
   label=$name
   if [[ $name == 'docker-ce' ]]; then
      label='Docker Engine (docker-ce)'
   fi
   printf '%s — %s' "$label" "$status"
   if [[ $name == 'vim-enhanced' ]]; then
      printf '; ~/.vimrc не трогает'
   elif [[ $name == 'docker-ce' ]]; then
      printf '; официальный репозиторий Docker'
   fi
}

load_rpm_items() {
   local output group name state tag category
   output=$("$PACKAGES" --list-rpm) ||
      die "не удалось проверить RPM через $PACKAGES"
   while IFS=$'\t' read -r group name state; do
      [[ -n $group ]] || continue
      [[ $name =~ ^[a-z0-9][a-z0-9+._-]*$ ]] ||
         die "packages.sh вернул недопустимое имя пакета: $name"
      case $group in
         base) category=base ;;
         extra) category=extras ;;
         *) die "packages.sh вернул неизвестную группу: $group" ;;
      esac

      tag="rpm:$name"
      TAG_CATEGORY[$tag]=$category
      TAG_KIND[$tag]=rpm
      TAG_STATUS[$tag]=$state
      TAG_LABEL[$tag]=$(rpm_label "$name" "$state")
      if [[ $name == 'docker-ce' ]]; then
         TAG_SHORT[$tag]='Docker Engine'
      else
         TAG_SHORT[$tag]=$name
      fi
      RPM_TAGS+=("$tag")

      # По умолчанию отмечены только отсутствующие базовые пакеты.
      # Дополнительные RPM и действия с конфигами — только явно.
      if [[ $category == base && $state == missing ]]; then
         SELECTED[$tag]=1
      fi
   done <<<"$output"
   ((${#RPM_TAGS[@]} > 0)) || die "packages.sh не вернул список RPM"
}

load_config_items() {
   local shell_state vim_state tag

   if "$SHELL_SETUP" --check >/dev/null 2>&1; then
      shell_state='настроено'
   else
      shell_state='не настроено'
   fi
   if "$VIM_SETUP" --check >/dev/null 2>&1; then
      vim_state='установлен и совпадает'
   elif [[ -e $HOME/.vimrc || -L $HOME/.vimrc ]]; then
      vim_state='есть другой файл, не заменяется'
   else
      vim_state='не установлен'
   fi

   tag=shell
   TAG_CATEGORY[$tag]=config
   TAG_KIND[$tag]=action
   TAG_LABEL[$tag]="Starship и Bash (без sudo) — $shell_state"
   TAG_SHORT[$tag]='Starship и Bash'
   CONFIG_TAGS+=("$tag")

   tag=vim
   TAG_CATEGORY[$tag]=config
   TAG_KIND[$tag]=action
   TAG_LABEL[$tag]="конфиг Vim (~/.vimrc) — $vim_state"
   TAG_SHORT[$tag]='конфиг Vim (~/.vimrc)'
   CONFIG_TAGS+=("$tag")

   tag=gnome
   TAG_CATEGORY[$tag]=config
   TAG_KIND[$tag]=action
   TAG_LABEL[$tag]='GNOME: Alt+Shift и Alt+T (без sudo)'
   TAG_SHORT[$tag]='GNOME Alt+Shift и Alt+T'
   CONFIG_TAGS+=("$tag")

   ALL_TAGS=("${RPM_TAGS[@]}" "${CONFIG_TAGS[@]}")
}

count_category() {
   local category=$1 tag count=0
   for tag in "${ALL_TAGS[@]}"; do
      [[ ${TAG_CATEGORY[$tag]} == "$category" ]] || continue
      [[ -n ${SELECTED[$tag]+x} ]] && count=$((count + 1))
   done
   printf '%d' "$count"
}

category_size() {
   local category=$1 tag count=0
   for tag in "${ALL_TAGS[@]}"; do
      [[ ${TAG_CATEGORY[$tag]} == "$category" ]] && count=$((count + 1))
   done
   printf '%d' "$count"
}

count_selected() {
   local tag count=0
   for tag in "${ALL_TAGS[@]}"; do
      [[ -n ${SELECTED[$tag]+x} ]] && count=$((count + 1))
   done
   printf '%d' "$count"
}

# ---------------------------------------------------------------------------
# dialog
# ---------------------------------------------------------------------------

check_prerequisites() {
   command -v dialog >/dev/null 2>&1 ||
      refuse 'не найден dialog. Установите штатный Fedora RPM: sudo dnf install dialog. Автоматически он не ставится.'
   if ! { exec 9<>/dev/tty; } 2>/dev/null; then
      refuse 'нужен настоящий интерактивный терминал (не удалось открыть /dev/tty).'
   fi
   exec 9>&-
}

# У dialog ошибки и Esc по умолчанию имеют один код. Ввод и экран идут
# через терминал, выбранные теги — отдельно через fd 3.
run_dialog() {
   DIALOG_OK=0 DIALOG_CANCEL=1 DIALOG_ESC=255 DIALOG_ERROR=2 \
      dialog --clear --backtitle "$BACKTITLE" "$@" </dev/tty >/dev/tty 2>/dev/tty
}

# Возвращает 0 — выбран пункт (MAIN_CHOICE), 1 — отмена/Esc, 2 — ошибка.
run_main_menu() {
   local total rc
   total=$(count_selected)
   if MAIN_CHOICE=$(run_dialog --title 'linux-settings' \
      --cancel-label 'Выход' --ok-label 'Открыть' --no-tags --output-fd 3 \
      --menu 'Выберите раздел. Отметки хранятся до выхода; изменения применяются только после итогового подтверждения.' \
      17 76 6 \
      base "Базовые пакеты — выбрано $(count_category base) из $(category_size base)" \
      extras "Дополнительные утилиты — выбрано $(count_category extras) из $(category_size extras)" \
      config "Настройки — выбрано $(count_category config) из $(category_size config)" \
      apply "Применить выбранное ($total)" \
      quit 'Выход без изменений' 3>&1); then
      rc=0
   else
      rc=$?
   fi
   case $rc in
      0) ;;
      1 | 255) return 1 ;;
      *)
         warn "dialog завершился с кодом $rc"
         return 2
         ;;
   esac

   case $MAIN_CHOICE in
      base | extras | config | apply | quit) return 0 ;;
      *)
         warn "dialog вернул неизвестный пункт главного меню: $MAIN_CHOICE"
         return 2
         ;;
   esac
}

# ---------------------------------------------------------------------------
# Категории
# ---------------------------------------------------------------------------

build_items() {
   local category=$1 tag state
   CHECKLIST_ITEMS=()
   for tag in "${ALL_TAGS[@]}"; do
      [[ ${TAG_CATEGORY[$tag]} == "$category" ]] || continue
      state=off
      [[ -n ${SELECTED[$tag]+x} ]] && state=on
      CHECKLIST_ITEMS+=("$tag" "${TAG_LABEL[$tag]}" "$state")
   done
}

update_category() {
   local category=$1 choices=$2 tag
   local -A chosen=()

   while IFS= read -r tag; do
      [[ -n $tag ]] || continue
      [[ -n ${TAG_CATEGORY[$tag]+x} ]] ||
         die "dialog вернул неизвестный пункт: $tag. Ничего не изменено."
      [[ ${TAG_CATEGORY[$tag]} == "$category" ]] ||
         die "dialog вернул пункт из другой категории: $tag. Ничего не изменено."
      chosen[$tag]=1
   done <<<"$choices"

   # Обновляем только текущую категорию: остальные отметки не трогаем.
   for tag in "${ALL_TAGS[@]}"; do
      [[ ${TAG_CATEGORY[$tag]} == "$category" ]] || continue
      if [[ -n ${chosen[$tag]+x} ]]; then
         SELECTED[$tag]=1
      else
         unset "SELECTED[$tag]"
      fi
   done
}

edit_category() {
   local category=$1 title=$2 prompt=$3
   local choices rc

   build_items "$category"
   if choices=$(run_dialog --title "$title" \
      --ok-label 'Сохранить' --cancel-label 'Назад' --no-tags \
      --separate-output --output-fd 3 \
      --checklist "$prompt" 20 78 10 "${CHECKLIST_ITEMS[@]}" 3>&1); then
      rc=0
   else
      rc=$?
   fi
   case $rc in
      0)
         update_category "$category" "$choices"
         ;;
      1 | 255)
         # «Назад»/Esc: отметки этой категории остаются такими, какими были
         # до входа. Текущие переключения отбрасываются.
         ;;
      *)
         die "не удалось получить выбор из dialog (код $rc). Ничего не применено."
         ;;
   esac
}

# ---------------------------------------------------------------------------
# Итоговая сводка и применение
# ---------------------------------------------------------------------------

summary_item() {
   local tag=$1 name=${TAG_SHORT[$1]}
   if [[ ${TAG_KIND[$tag]} == rpm ]]; then
      if [[ ${TAG_STATUS[$tag]} == installed ]]; then
         printf '%s (уже установлен)' "$name"
      else
         printf '%s' "$name"
      fi
   else
      printf '%s' "$name"
   fi
}

build_summary() {
   local category title tag items rpm_selected=0
   local -a lines=('Сводка выбранного:' '')
   for category in base extras config; do
      case $category in
         base) title=$CATEGORY_TITLE_BASE ;;
         extras) title=$CATEGORY_TITLE_EXTRAS ;;
         config) title=$CATEGORY_TITLE_CONFIG ;;
      esac
      items=''
      for tag in "${ALL_TAGS[@]}"; do
         [[ ${TAG_CATEGORY[$tag]} == "$category" ]] || continue
         [[ -n ${SELECTED[$tag]+x} ]] || continue
         if [[ ${TAG_KIND[$tag]} == rpm && ${TAG_STATUS[$tag]} == missing ]]; then
            rpm_selected=1
         fi
         items+="${items:+, }$(summary_item "$tag")"
      done
      [[ -z $items ]] || lines+=("$title:" "$items" '')
   done
   if [[ -n ${SELECTED[rpm:docker-ce]+x} && ${TAG_STATUS[rpm:docker-ce]} == missing ]]; then
      lines+=('Docker Engine: подключение репозитория при необходимости и запуск службы.' '')
   fi
   if ((rpm_selected)); then
      lines+=('Продолжить? DNF отдельно покажет транзакцию и спросит подтверждение.')
   else
      lines+=('Продолжить?')
   fi
   printf '%s\n' "${lines[@]}"
}

apply_selection() {
   local -a rpms=()
   local tag

   for tag in "${RPM_TAGS[@]}"; do
      [[ -n ${SELECTED[$tag]+x} ]] || continue
      rpms+=("${tag#rpm:}")
   done

   # Сначала одна транзакция dnf только для выбранных отсутствующих RPM.
   if ((${#rpms[@]})); then
      "$PACKAGES" --install-selected "${rpms[@]}" ||
         return $?
   fi

   # Действия с конфигами — только после успешной установки пакетов,
   # обычным пользователем и только выбранные.
   if [[ -n ${SELECTED[shell]+x} ]]; then
      "$SHELL_SETUP" || return $?
   fi
   if [[ -n ${SELECTED[vim]+x} ]]; then
      "$VIM_SETUP" || return $?
   fi
   if [[ -n ${SELECTED[gnome]+x} ]]; then
      "$GNOME_SETUP" apply || return $?
   fi
}

confirm_and_apply() {
   local total rc
   total=$(count_selected)
   if ((total == 0)); then
      run_dialog --title 'Ничего не выбрано' \
         --msgbox 'Отметьте хотя бы один пункт в разделах меню.' 8 56 || true
      return 1
   fi

   local summary
   summary=$(build_summary)
   if run_dialog --title 'Подтверждение' --defaultno \
      --yes-label 'Применить' --no-label 'Вернуться' \
      --yesno "$summary" 22 78; then
      rc=0
   else
      rc=$?
   fi
   case $rc in
      0) ;;
      1 | 255) return 1 ;;
      *)
         die "dialog завершился с кодом $rc при подтверждении. Ничего не применено."
         ;;
   esac

   printf '\n%s\n\n' "$summary"
   if apply_selection; then
      say 'Готово. Выбранные действия выполнены.'
      say 'Проверка: make doctor'
      return 0
   else
      rc=$?
      printf 'Ошибка: выполнение остановлено (код %d). Следующие выбранные действия не запускались.\n' "$rc" >&2
       exit 1
   fi
}

# ---------------------------------------------------------------------------
# Главное меню
# ---------------------------------------------------------------------------

main() {
   if (($# > 1)); then
      usage >&2
      return 2
   fi
   case ${1:-} in
      '') ;;
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

   [[ -n ${HOME:-} ]] || die "не задан HOME"
   check_prerequisites

   load_rpm_items
   load_config_items

   local rc
   while true; do
      if run_main_menu; then
         rc=0
      else
         rc=$?
      fi
      case $rc in
         0) ;;
         1)
            say 'Выход. Изменения не применялись.'
            return 0
            ;;
         *)
            die "не удалось получить выбор из главного меню. Ничего не применено."
            ;;
      esac

      case $MAIN_CHOICE in
         base)
            edit_category base "$CATEGORY_TITLE_BASE" \
               'Пробел — отметить, Enter — сохранить и вернуться. Уже установленные пакеты отмечены в описании; повторно они не ставятся.'
            ;;
         extras)
            edit_category extras "$CATEGORY_TITLE_EXTRAS" \
               'Пробел — отметить, Enter — сохранить и вернуться. Это необязательные утилиты; по умолчанию не выбраны.'
            ;;
         config)
            edit_category config "$CATEGORY_TITLE_CONFIG" \
               'Пробел — отметить, Enter — сохранить и вернуться. Действия с конфигами по умолчанию не выбраны; пакет vim-enhanced сам ~/.vimrc не меняет.'
            ;;
         apply)
            confirm_and_apply && return 0
            ;;
         quit)
            say 'Выход. Изменения не применялись.'
            return 0
            ;;
      esac
   done
}

main "$@"
