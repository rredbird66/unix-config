# linux-settings

Локальные настройки для **Fedora Workstation 45**, **GNOME Wayland** и терминала
**Ptyxis**. Репозиторий объединяет прежнюю историю `unix-config` (Bash, Vim,
SSH-пример, Oh My Posh) с настройками GNOME. Всё разворачивается обычным
пользователем; `sudo` нужен только для установки обязательных RPM.

Репозиторий локальный: remote не настраивается, ничего не публикуется.

## Состав

| Путь | Назначение |
|---|---|
| `settings.sh` | GNOME: переключение раскладки `Alt+Shift` и ярлык `Alt+T` для Ptyxis |
| `shell/` | Starship и управляемый блок для интерактивного Bash |
| `shell/bashrc.example` | исторический `.bashrc` из `unix-config` (для поиска старых строк Oh My Posh) |
| `shell/legacy/` | старая тема Oh My Posh, сохранена для восстановления prompt |
| `vim/` | конфигурация Vim и её установка в `~/.vimrc` |
| `ssh/config.example` | безопасный пример `~/.ssh/config`, автоматически не устанавливается |
| `Makefile` | команды `make help/packages/shell/vim/...` |
| `scripts/packages.sh` | проверка и установка `vim-enhanced`, `mc`, `htop` |

## Зависимости

Обязательные RPM: `vim-enhanced`, `mc`, `htop`. Их проверяет и при необходимости
ставит `make packages`.

Для работы скриптов нужны обычные утилиты Fedora: `bash`, `coreutils`, `curl`,
`tar`, `flock` (`util-linux`), `gsettings` (`glib2`) и `ptyxis`. Для проверки
SSH-примера нужен пакет `openssh-clients`.

Необязательные программы (ставятся отдельно, скриптами не устанавливаются):

```bash
sudo dnf install btop ripgrep fd-find fzf
```

Yazi не требует COPR: скачайте официальный архив из GitHub Releases
<https://github.com/sxyazi/yazi/releases>, распакуйте и положите `yazi`/`ya` в
`~/.local/bin` или другой каталог из `PATH`. COPR и сторонние репозитории не
используются.

## Быстрый старт

```bash
cd ~/linux-settings
make                 # справка; цель по умолчанию — help
make packages        # проверить/поставить vim-enhanced, mc, htop
make shell           # Starship + блок в ~/.bashrc, без sudo
make vim             # установить ~/.vimrc, если его ещё нет
make status          # ./settings.sh status, только чтение
make apply           # GNOME: Alt+Shift и Alt+T, без sudo
make undo            # откатить только изменения settings.sh
```

`make shell`, `make vim`, `make apply` и `make undo` меняют файлы в `$HOME` или
настройки GNOME. `make status`, `make help`, `make shell-check`, `make vim-check`
и `make check` ничего не меняют.

## RPM-пакеты

`make packages` вызывает `scripts/packages.sh`:

1. проверяет каждый пакет через `rpm -q`;
2. уже установленные пакеты не трогает;
3. если всё есть, завершает работу без `sudo` и без вопросов;
4. если чего-то нет, запускает **один** `sudo dnf install <только отсутствующие>`.
   DNF показывает транзакцию и запрашивает подтверждение.

Другие команды репозитория `sudo` не используют.

## Shell: Starship вместо Oh My Posh

`make shell` (или `./shell/setup.sh`):

- ставит **Starship 1.27.0** из официального GitHub Release в `~/.local/bin`,
  без `sudo`;
- для x86_64 использует `starship-x86_64-unknown-linux-gnu.tar.gz` с SHA-256
  `3b94758850901717eb36aa1b53f8492c1322506ec6d41273bc6151e79ed8e4a1`;
- для aarch64 использует `starship-aarch64-unknown-linux-musl.tar.gz` с SHA-256
  `341f5cbf24699fa0b27ec88965ad25f862ea09e15d35a543fd6ffdff1d2aa00d`;
- для других архитектур выдаёт понятную ошибку;
- скачивает архив только если рабочего бинарника нужной версии нет; проверенный
  архив кешируется в `${XDG_CACHE_HOME:-~/.cache}/linux-settings/`;
- **проверяет SHA-256 до распаковки** и устанавливает бинарник атомарно. При
  ошибке скачивания, хеша или распаковки существующий рабочий бинарник не
  затрагивается;
- записывает конфиг в `${XDG_CONFIG_HOME:-~/.config}/starship.toml`, если файла
  нет или он совпадает. Чужой отличающийся TOML не перезаписывается молча:
  скрипт останавливается до установки бинарника и правки `.bashrc`. Явная замена:
  `./shell/setup.sh --force-config` (с резервной копией);
- добавляет в `~/.bashrc` управляемый блок между
  `# >>> linux-settings starship >>>` и `# <<< linux-settings starship <<<`.
  Блок срабатывает только в интерактивном Bash при наличии бинарника и доступного
  конфига. Он добавляет `~/.local/bin` в `PATH`, если его там ещё нет, и запускает
  установленный бинарник. Явно заданный `STARSHIP_CONFIG` сохраняется;
- сохраняет остальные строки и локальные правки `.bashrc`, перед записью делает
  копию `~/.bashrc.linux-settings-backup.<дата-время>`;
- удаляет только **точные** строки инициализации Oh My Posh из исторического
  `shell/bashrc.example`. Похожие, но изменённые строки не удаляются — скрипт
  предупреждает о них;
- повторный запуск ничего не меняет; `--check` проверяет бинарник, конфиг и блок
  без записи.

### Конфиг Starship

`shell/starship.toml` задаёт подсказку в две строки: каталог, ветка Git, активное
Python venv и индикатор ошибки. Используются обычные символы (`>`, `!`), Nerd Font
не требуется. Цвет ошибки — красный `!`, успешный ввод — зелёный `>`.

### Проверка и восстановление старого prompt

```bash
make shell
make shell-check
exec bash -l          # или открыть новый терминал
starship --version    # starship 1.27.0
```

Проверьте: строка с каталогом и ветвью Git, затем вторая строка с `>`; после
неудачной команды (`false`) символ становится красным `!`; в активированном venv
появляется `venv:...`.

Старые `~/.oh_my_posh/oh-my-posh` и `~/.poshthemes/` скрипт **не удаляет**. Чтобы
вернуть старый prompt:

1. восстановите `.bashrc` из резервной копии или удалите управляемый блок Starship;
2. если после этого строка Oh My Posh отсутствует, верните её из `shell/bashrc.example`:
   `eval "$(~/.oh_my_posh/oh-my-posh --init --shell bash --config ~/.poshthemes/paradox.omp.json)"`;
3. при необходимости снова положите тему из `shell/legacy/paradox.omp.json` в
   `~/.poshthemes/`.

## Vim

`make vim` (или `./vim/setup.sh`):

- записывает `vim/vimrc` в `~/.vimrc`, если пользовательского файла ещё нет;
- если файл уже совпадает, ничего не меняет и не создаёт лишних копий;
- для замены другого `~/.vimrc` требуется `./vim/setup.sh --replace`. Перед
  заменой создаётся резервная копия, путь к ней скрипт выводит в терминале;
- сохраняет симлинк `~/.vimrc`, записывая в его цель;
- не использует Vundle и Syntastic, не требует `solarized8`;
- включает нумерацию строк, отступы четырьмя пробелами, тёмный фон и встроенную
  тему `habamax` с запасным `default`;
- необязательный встроенный пакет `matchit` подключается через `packadd`, если
  он есть в поставке Vim; без него конфигурация тоже запускается.

Проверка:

```bash
make vim
make vim-check
vim -Nu ~/.vimrc -n +q
```

Откат: восстановить `~/.vimrc` из резервной копии.

## SSH-пример

`ssh/config.example` — только пример. Он не копируется в `~/.ssh/config`
автоматически. В нём нет глобального `User root`; используются демонстрационные
адреса из документационных диапазонов и пользователь `demo`.

```bash
ssh -G -F ssh/config.example targaryen | grep -E '^(user|hostname|port) '
```

## GNOME: раскладка и Ptyxis

`./settings.sh status|apply|undo` запускается без `sudo` из графической сессии.

| Команда | Поведение |
|---|---|
| `status` | только читает настройки и файл состояния; ничего не создаёт |
| `apply` | добавляет `grp:alt_shift_toggle` в `xkb-options`, если его нет, и создаёт/находит ярлык `Alt+T` → `ptyxis --new-window --maximize` |
| `undo` | убирает только то, что добавил скрипт |

Свойства:

- чужие XKB-опции и пользовательские ярлыки сохраняются;
- `custom0` не считается свободным;
- если `Alt+T` занят другим ярлыком, `apply` ничего не меняет и объясняет
  конфликт;
- если ярлык или XKB-токен уже настроены вручную, `undo` их не трогает;
- если созданный скриптом ярлык позже изменили вручную, `undo` оставляет его как
  есть;
- состояние хранится в
  `${XDG_STATE_HOME:-$HOME/.local/state}/linux-settings/state.sh` (формат v1);
- состояние читается как данные: разбираются только `KEY=value`, значения
  проверяются, никаких `source`/`eval`;
- `apply`/`undo` используют `flock` на каталоге состояния, поэтому одновременные
  запуски ждут друг друга. Изменения, внесённые через GNOME, учитываются по
  фактическим значениям;
- перед записью изменений сохраняется состояние. Если `apply` прервался,
  можно повторить его или выполнить `undo`. Повторный `undo` продолжит
  очистку, даже если предыдущий запуск прервался после удаления пути ярлыка.

Ручная проверка:

1. `./settings.sh status`.
2. `./settings.sh apply`.
3. Переключить `us`/`ru` через `Alt+Shift` (если оба языка добавлены).
4. Нажать `Alt+T` — должно открыться новое развёрнутое окно Ptyxis.
5. `./settings.sh undo`; убедиться, что остальные XKB-опции и чужие ярлыки целы.
6. Повторный `undo` безопасен.

## Проверки без изменения реальных настроек

Синтаксис всех скриптов:

```bash
make check
```

GNOME на изолированном профиле (нужен `ptyxis` в `PATH`; можно создать заглушку):

```bash
tmp=$(mktemp -d)
mkdir -p "$tmp/bin"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/ptyxis"
chmod +x "$tmp/bin/ptyxis"
HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" \
GSETTINGS_BACKEND=keyfile PATH="$tmp/bin:$PATH" ./settings.sh apply
```

Shell и Vim можно проверить с отдельным `HOME`:

```bash
tmp=$(mktemp -d)
HOME="$tmp" XDG_CACHE_HOME="$tmp/cache" ./shell/setup.sh
HOME="$tmp" ./vim/setup.sh
HOME="$tmp" ./shell/setup.sh --check
HOME="$tmp" ./vim/setup.sh --check
```

## Ограничения

- Настройки GNOME рассчитаны на Fedora/GNOME с `gsettings` и
  `gnome-settings-daemon`; другие окружения не поддерживаются.
- `make shell` требует сеть при первом запуске, если нужного Starship нет в
  кеше. Поддерживаются проверенные x86_64 GNU и aarch64 musl; для остальных
  архитектур будет ошибка.
- `make vim` не устанавливает плагины и не запускает `:PluginInstall`.
- SSH-пример не устанавливается и не меняет `~/.ssh/config`.
- `sudo` используется только в `scripts/packages.sh` для `dnf install`.
- Скрипт не публикует изменения и не настраивает git remote.

## Батарея: снимок состояния

Разовый замер батареи этой машины для сравнения с будущими показаниями:

```text
model:                R15B06W
state:                discharging
energy-full:          60.231 Wh
energy-full-design:   72.012 Wh
energy-rate:          8.716 W
charge-cycles:        N/A
percentage:           78%
capacity:             83.6402%
```
