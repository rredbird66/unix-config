#!/usr/bin/env bash
#
# scripts/packages.sh — проверяет и при необходимости устанавливает RPM.
# Это единственное место репозитория, где используется sudo.
set -euo pipefail

readonly BASE_PACKAGES=(vim-enhanced mc htop)
readonly EXTRA_PACKAGES=(ripgrep fd-find fzf zoxide btop tmux)

usage() {
   printf 'Использование: %s [--extras | --check | --list-rpm | --install-selected PACKAGE...]\n' "$0"
}

die() {
   printf 'Ошибка: %s\n' "$*" >&2
   exit 1
}

say() {
   printf '%s\n' "$*"
}

command -v rpm >/dev/null 2>&1 ||
   die "не найдена команда rpm. Этот шаг рассчитан на Fedora."

missing=()
scan_packages() {
   local package
   missing=()
   for package in "$@"; do
      if rpm -q --quiet "$package"; then
         say "  установлен: $package"
      else
         say "  отсутствует: $package"
         missing+=("$package")
      fi
   done
}

# Машиночитаемый список для scripts/setup.sh: группа, имя, состояние.
list_rpm() {
   local package state
   for package in "${BASE_PACKAGES[@]}"; do
      state=missing
      if rpm -q --quiet "$package"; then
         state=installed
      fi
      printf 'base\t%s\t%s\n' "$package" "$state"
   done
   for package in "${EXTRA_PACKAGES[@]}"; do
      state=missing
      if rpm -q --quiet "$package"; then
         state=installed
      fi
      printf 'extra\t%s\t%s\n' "$package" "$state"
   done
}

known_package() {
   local candidate=$1 package
   for package in "${BASE_PACKAGES[@]}" "${EXTRA_PACKAGES[@]}"; do
      if [[ $candidate == "$package" ]]; then
         return 0
      fi
   done
   return 1
}

install_missing() {
   if ((${#missing[@]} == 0)); then
      say "Все пакеты выбранного набора уже установлены; sudo не требуется."
      return 0
   fi

   command -v sudo >/dev/null 2>&1 ||
      die "не найдена команда sudo. Установите пакеты вручную: dnf install ${missing[*]}"
   command -v dnf >/dev/null 2>&1 ||
      die "не найдена команда dnf. Установите пакеты вручную."

   say ""
   say "Запуск: sudo dnf install ${missing[*]}"
   sudo dnf install "${missing[@]}"
}

install_selected() {
   (($# > 0)) || die "для --install-selected укажите хотя бы один пакет"
   local -a selected=()
   local candidate package duplicate
   for candidate in "$@"; do
      known_package "$candidate" ||
         die "неизвестный пакет: $candidate. Разрешены только пакеты из базового и дополнительного наборов."
      duplicate=0
      for package in "${selected[@]}"; do
         if [[ $package == "$candidate" ]]; then
            duplicate=1
            break
         fi
      done
      ((duplicate)) || selected+=("$candidate")
   done

   scan_packages "${selected[@]}"
   install_missing
}

if (($# > 0)); then
   case $1 in
      --extras | --check | --list-rpm)
         (($# == 1)) || {
            usage >&2
            exit 2
         }
         ;;
      --install-selected)
         shift
         install_selected "$@"
         exit
         ;;
      -h | --help | help)
         usage
         exit 0
         ;;
      *)
         usage >&2
         exit 2
         ;;
   esac
fi

case ${1:-} in
   '')
      scan_packages "${BASE_PACKAGES[@]}"
      ;;
   --extras)
      scan_packages "${EXTRA_PACKAGES[@]}"
      ;;
   --list-rpm)
      list_rpm
      exit 0
      ;;
   --check)
      say 'Базовые пакеты:'
      scan_packages "${BASE_PACKAGES[@]}"
      result=0
      ((${#missing[@]} == 0)) || result=1
      say 'Дополнительные пакеты:'
      scan_packages "${EXTRA_PACKAGES[@]}"
      exit "$result"
      ;;
esac

install_missing
