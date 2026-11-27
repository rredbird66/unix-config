SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help all setup packages extras shell shell-check vim vim-check status apply undo battery doctor settings-check check test

help:
	@printf '%s\n' \
		'linux-settings — настройки Fedora 45 / GNOME Wayland / Ptyxis' \
		'' \
		'  make help          показать эту справку (цель по умолчанию)' \
		'  make setup         интерактивное меню по категориям (нужен dialog и TTY)' \
		'  make packages      проверить vim-enhanced, mc, htop и поставить недостающие через dnf' \
		'  make extras        поставить ripgrep, fd-find, fzf, zoxide, btop, tmux и Docker' \
		'  make shell         установить Starship и управляемый блок в ~/.bashrc' \
		'  make shell-check   проверить установку Starship без изменений' \
		'  make vim           установить ~/.vimrc, если его ещё нет' \
		'  make vim-check     проверить ~/.vimrc без изменений' \
		'  make status        ./settings.sh status (только чтение)' \
		'  make apply         ./settings.sh apply (GNOME, без sudo)' \
		'  make undo          ./settings.sh undo' \
		'  make battery       показать текущие данные батареи из UPower' \
		'  make doctor        проверить пакеты, Bash, Vim и GNOME, показать резервные копии' \
		'  make check         проверить синтаксис скриптов' \
		'  make test          проверить настройки GNOME в изолированном профиле' \
		'' \
		'Подробности и ручная проверка — в README.md.'

all: shell vim

setup:
	@./scripts/setup.sh

packages:
	@./scripts/packages.sh

extras:
	@./scripts/packages.sh --extras

shell:
	@./shell/setup.sh

shell-check:
	@./shell/setup.sh --check

vim:
	@./vim/setup.sh

vim-check:
	@./vim/setup.sh --check

status:
	@./settings.sh status

apply:
	@./settings.sh apply

undo:
	@./settings.sh undo

battery:
	@./scripts/battery.sh

doctor:
	@./scripts/doctor.sh

settings-check:
	@for script in settings.sh shell/setup.sh vim/setup.sh scripts/*.sh tests/*.sh; do \
		bash -n "$$script" || exit; \
	done

check: settings-check
	@printf '%s\n' 'Синтаксис скриптов в порядке.'

test: check
	@./tests/gnome.sh
