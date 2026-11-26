SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help all packages shell shell-check vim vim-check status apply undo battery settings-check check

help:
	@printf '%s\n' \
		'linux-settings — настройки Fedora 45 / GNOME Wayland / Ptyxis' \
		'' \
		'  make help          показать эту справку (цель по умолчанию)' \
		'  make packages      проверить vim-enhanced, mc, htop и поставить недостающие через dnf' \
		'  make shell         установить Starship и управляемый блок в ~/.bashrc' \
		'  make shell-check   проверить установку Starship без изменений' \
		'  make vim           установить ~/.vimrc, если его ещё нет' \
		'  make vim-check     проверить ~/.vimrc без изменений' \
		'  make status        ./settings.sh status (только чтение)' \
		'  make apply         ./settings.sh apply (GNOME, без sudo)' \
		'  make undo          ./settings.sh undo' \
		'  make battery       показать текущие данные батареи из UPower' \
		'  make check         проверить синтаксис скриптов' \
		'' \
		'Подробности и ручная проверка — в README.md.'

all: shell vim

packages:
	@./scripts/packages.sh

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

settings-check:
	@for script in settings.sh shell/setup.sh vim/setup.sh scripts/*.sh; do \
		bash -n "$$script" || exit; \
	done

check: settings-check
	@printf '%s\n' 'Синтаксис скриптов в порядке.'
