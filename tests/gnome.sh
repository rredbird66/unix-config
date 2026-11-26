#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
readonly XKB_SCHEMA='org.gnome.desktop.input-sources'
readonly MEDIA_SCHEMA='org.gnome.settings-daemon.plugins.media-keys'
readonly KEY_ROOT='/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings'
readonly FOREIGN_PATH="$KEY_ROOT/custom0/"
readonly OWN_PATH="$KEY_ROOT/custom1/"
readonly FOREIGN_KEY="$MEDIA_SCHEMA.custom-keybinding:$FOREIGN_PATH"
readonly OWN_KEY="$MEDIA_SCHEMA.custom-keybinding:$OWN_PATH"

fail() {
   printf 'Ошибка теста: %s\n' "$*" >&2
   exit 1
}

REAL_GSETTINGS=$(command -v gsettings) || fail 'нужен gsettings из glib2'
export REAL_GSETTINGS
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -- "$work/bin"

# Не запускаем Ptyxis. Обёртка над реальным gsettings позволяет имитировать
# сбой конкретной операции; остальные команды работают с тестовым keyfile.
cat >"$work/bin/ptyxis" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat >"$work/bin/gsettings" <<'EOF'
#!/usr/bin/env bash
if [[ ${GNOME_TEST_FAILURE:-} == "${1:-}:${3:-}" ]]; then
   printf 'Имитированный сбой gsettings: %s\n' "$GNOME_TEST_FAILURE" >&2
   exit 1
fi
exec "$REAL_GSETTINGS" "$@"
EOF
chmod +x -- "$work/bin/ptyxis" "$work/bin/gsettings"
export PATH="$work/bin:$PATH" GSETTINGS_BACKEND=keyfile LC_ALL=C.UTF-8
unset GNOME_TEST_FAILURE

profile() {
   export HOME="$work/$1" XDG_CONFIG_HOME="$work/$1/config" XDG_STATE_HOME="$work/$1/state"
   mkdir -- "$HOME"
}

expect() {
   local expected=$1
   shift
   local actual
   actual=$("$@") || fail "не удалось прочитать значение: $*"
   if [[ $actual != "$expected" ]]; then
      fail "$*: ожидалось «$expected», получено «$actual»"
   fi
}

expect_failure() {
   if "$@" >"$HOME/failure.log" 2>&1; then
      fail "ожидался сбой: $*"
   fi
}

install_foreign_key() {
   gsettings set "$FOREIGN_KEY" name "'Сторонний ярлык'"
   gsettings set "$FOREIGN_KEY" command "'other-terminal'"
   gsettings set "$FOREIGN_KEY" binding "'$1'"
   gsettings set "$MEDIA_SCHEMA" custom-keybindings "['$FOREIGN_PATH']"
}

expect_empty_own_key() {
   local field
   for field in name command binding; do
      expect "''" gsettings get "$OWN_KEY" "$field"
   done
}

profile repeated
install_foreign_key '<Alt>u'
gsettings set "$XKB_SCHEMA" xkb-options "['caps:escape']"
./settings.sh status >/dev/null
[[ ! -e $XDG_STATE_HOME ]] || fail 'status создал каталог состояния'
./settings.sh apply >/dev/null
./settings.sh apply >/dev/null
expect "['$FOREIGN_PATH', '$OWN_PATH']" gsettings get "$MEDIA_SCHEMA" custom-keybindings
expect "['caps:escape', 'grp:alt_shift_toggle']" gsettings get "$XKB_SCHEMA" xkb-options
expect "'<Alt>t'" gsettings get "$OWN_KEY" binding
./settings.sh undo >/dev/null
./settings.sh undo >/dev/null
expect "['$FOREIGN_PATH']" gsettings get "$MEDIA_SCHEMA" custom-keybindings
expect "['caps:escape']" gsettings get "$XKB_SCHEMA" xkb-options
expect_empty_own_key
printf '%s\n' 'OK: повторные apply/undo и сохранение сторонних настроек'

profile conflict
install_foreign_key '<Alt>t'
expect_failure ./settings.sh apply
grep -q 'Alt+T уже занят' "$HOME/failure.log" || fail 'не обнаружен конфликт Alt+T'
expect "['$FOREIGN_PATH']" gsettings get "$MEDIA_SCHEMA" custom-keybindings
expect "'other-terminal'" gsettings get "$FOREIGN_KEY" command
expect '@as []' gsettings get "$XKB_SCHEMA" xkb-options
printf '%s\n' 'OK: конфликт Alt+T'

profile partial-apply
expect_failure env GNOME_TEST_FAILURE=set:command ./settings.sh apply
grep -q 'Имитированный сбой' "$HOME/failure.log" || fail 'не воспроизведён сбой apply'
expect "'Ptyxis'" gsettings get "$OWN_KEY" name
./settings.sh undo >/dev/null
expect '@as []' gsettings get "$MEDIA_SCHEMA" custom-keybindings
expect '@as []' gsettings get "$XKB_SCHEMA" xkb-options
expect_empty_own_key
printf '%s\n' 'OK: откат после частичного apply'

profile partial-undo
./settings.sh apply >/dev/null
expect_failure env GNOME_TEST_FAILURE=reset:command ./settings.sh undo
grep -q 'Имитированный сбой' "$HOME/failure.log" || fail 'не воспроизведён сбой undo'
expect '@as []' gsettings get "$MEDIA_SCHEMA" custom-keybindings
expect "'ptyxis --new-window --maximize'" gsettings get "$OWN_KEY" command
gsettings set "$XKB_SCHEMA" xkb-options "['grp:alt_shift_toggle']"
./settings.sh undo >/dev/null
expect "['grp:alt_shift_toggle']" gsettings get "$XKB_SCHEMA" xkb-options
expect_empty_own_key
printf '%s\n' 'OK: возобновление undo и сохранение ручной правки'
