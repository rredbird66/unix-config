#!/usr/bin/env bash
#
# scripts/packages.sh — проверяет и устанавливает RPM; для Docker подключает
# официальный репозиторий. Это единственное место репозитория, где используется sudo.
set -euo pipefail

readonly BASE_PACKAGES=(vim-enhanced mc htop)
readonly EXTRA_PACKAGES=(ripgrep fd-find fzf zoxide btop tmux docker-ce)
readonly DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
readonly DOCKER_REPO_ID='docker-ce-stable'
readonly DOCKER_REPO_URL='https://download.docker.com/linux/fedora/docker-ce.repo'

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

docker_installed() {
   local package
   for package in "${DOCKER_PACKAGES[@]}"; do
      rpm -q --quiet "$package" || return 1
   done
}

package_installed() {
   if [[ $1 == 'docker-ce' ]]; then
      docker_installed
   else
      rpm -q --quiet "$1"
   fi
}

package_display() {
   case $1 in
      docker-ce) printf 'Docker Engine (docker-ce)' ;;
      *) printf '%s' "$1" ;;
   esac
}

package_state() {
   if package_installed "$1"; then
      printf 'installed'
   else
      printf 'missing'
   fi
}

scan_packages() {
   local package
   missing=()
   for package in "$@"; do
      if package_installed "$package"; then
         say "  установлен: $(package_display "$package")"
      else
         say "  отсутствует: $(package_display "$package")"
         missing+=("$package")
      fi
   done
}

# Машиночитаемый список для scripts/setup.sh: группа, имя, состояние.
list_rpm() {
   local package state
   for package in "${BASE_PACKAGES[@]}"; do
      state=$(package_state "$package")
      printf 'base\t%s\t%s\n' "$package" "$state"
   done
   for package in "${EXTRA_PACKAGES[@]}"; do
      state=$(package_state "$package")
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

install_docker() {
   if docker_installed; then
      say "Docker уже установлен; изменений нет."
      return 0
   fi

   say ""
   local repos
   repos=$(dnf --quiet repo list --all --json "$DOCKER_REPO_ID") ||
      die "не удалось проверить наличие репозитория $DOCKER_REPO_ID"
   if [[ $repos == *"\"$DOCKER_REPO_ID\""* ]]; then
      say "Docker: использую уже настроенный репозиторий $DOCKER_REPO_ID."
   else
      dnf config-manager --help >/dev/null 2>&1 ||
         die "не найден dnf config-manager. Установите dnf5-plugins: sudo dnf install dnf5-plugins"
      say "Docker: добавляю официальный репозиторий Docker."
      sudo dnf config-manager addrepo --from-repofile "$DOCKER_REPO_URL"
   fi
   say "Запуск: sudo dnf install ${DOCKER_PACKAGES[*]}"
   sudo dnf install "${DOCKER_PACKAGES[@]}"

   if command -v systemctl >/dev/null 2>&1; then
      say "Включаю службу docker."
      sudo systemctl enable --now docker
   fi
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

   local -a rpms=() docker=()
   local package
   for package in "${missing[@]}"; do
      if [[ $package == 'docker-ce' ]]; then
         docker+=("$package")
      else
         rpms+=("$package")
      fi
   done

   if ((${#rpms[@]})); then
      say ""
      say "Запуск: sudo dnf install ${rpms[*]}"
      sudo dnf install "${rpms[@]}"
   fi
   if ((${#docker[@]})); then
      install_docker
   fi
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
