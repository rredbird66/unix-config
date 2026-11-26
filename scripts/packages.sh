#!/usr/bin/env bash
#
# scripts/packages.sh — проверяет и при необходимости ставит обязательные RPM.
# Это единственное место репозитория, где используется sudo.
set -euo pipefail

readonly PACKAGES=(vim-enhanced mc htop)

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
for package in "${PACKAGES[@]}"; do
   if rpm -q --quiet "$package"; then
      say "установлен: $package"
   else
      say "отсутствует: $package"
      missing+=("$package")
   fi
done

if ((${#missing[@]} == 0)); then
   say "Все обязательные пакеты уже установлены; sudo не требуется."
   exit 0
fi

command -v sudo >/dev/null 2>&1 ||
   die "не найдена команда sudo. Установите пакеты вручную: dnf install ${missing[*]}"
command -v dnf >/dev/null 2>&1 ||
   die "не найдена команда dnf. Установите пакеты вручную."

say ""
say "Запуск: sudo dnf install ${missing[*]}"
sudo dnf install "${missing[@]}"
