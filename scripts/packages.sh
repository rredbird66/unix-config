#!/usr/bin/env bash
#
# scripts/packages.sh — проверяет и при необходимости устанавливает RPM.
# Это единственное место репозитория, где используется sudo.
set -euo pipefail

readonly BASE_PACKAGES=(vim-enhanced mc htop)
readonly EXTRA_PACKAGES=(ripgrep fd-find fzf zoxide btop tmux)

die() {
   printf 'Ошибка: %s\n' "$*" >&2
   exit 1
}

say() {
   printf '%s\n' "$*"
}

if (($# > 1)); then
   die "использование: $0 [--extras | --check]"
fi

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

case ${1:-} in
   '')
      scan_packages "${BASE_PACKAGES[@]}"
      ;;
   --extras)
      scan_packages "${EXTRA_PACKAGES[@]}"
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
   *)
      die "использование: $0 [--extras | --check]"
      ;;
esac

if ((${#missing[@]} == 0)); then
   say "Все пакеты выбранного набора уже установлены; sudo не требуется."
   exit 0
fi

command -v sudo >/dev/null 2>&1 ||
   die "не найдена команда sudo. Установите пакеты вручную: dnf install ${missing[*]}"
command -v dnf >/dev/null 2>&1 ||
   die "не найдена команда dnf. Установите пакеты вручную."

say ""
say "Запуск: sudo dnf install ${missing[*]}"
sudo dnf install "${missing[@]}"
