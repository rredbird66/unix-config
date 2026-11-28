# OpenCode: statusline в TUI

Конфигурация TUI-плагина строки состояния для
[OpenCode](https://opencode.ai): остатки лимитов OpenAI, Kimi и OpenCode Go
прямо над полем ввода и на домашнем экране.

## Состав

| Путь | Назначение |
|---|---|
| `cli.json` | подключает плагин `./plugins/statusline` |
| `plugins/statusline/tui.tsx` | плагин statusline: опрос лимитов, отрисовка, команда `/limits` |

`service.json` и другие файлы с учётными данными в репозиторий не входят.

## Установка

Каталог конфигурации OpenCode: `${XDG_CONFIG_HOME:-~/.config}/opencode`.

1. Скопировать плагин:

   ```bash
   mkdir -p ~/.config/opencode/plugins
   cp -r ai/opencode/plugins/statusline ~/.config/opencode/plugins/
   ```

2. Подключить его в `~/.config/opencode/cli.json`. Если файла нет, можно
   просто скопировать пример:

   ```bash
   cp ai/opencode/cli.json ~/.config/opencode/cli.json
   ```

   Если `cli.json` уже существует, добавьте путь в массив `plugins`, не
   заменяя остальные настройки:

   ```json
   {
     "$schema": "https://opencode.ai/v2/cli.json",
     "plugins": ["./plugins/statusline"]
   }
   ```

3. Перезапустить OpenCode.

## Что показывает

- **OPENAI** — окна лимитов из `chatgpt.com/backend-api/wham/usage`
  (план и процент использования).
- **KIMI** — лимиты `kimi-code-plan` из `/usages` (5 часов и 30 дней).
- **GO** — лимиты OpenCode Go: 5 часов, 7 дней, 30 дней.

Используется активная учётная запись из локального сервера OpenCode.
Данные кэшируются на 60 секунд и обновляются раз в 30 секунд и после
успешного выполнения команды. Ширина строки подбирается под терминал:
сначала показываются все провайдеры с барами и временем сброса, затем
детали постепенно сокращаются. Для 30-дневных окон Kimi и OpenCode Go на
широком терминале в скобках выводится дата сброса (например, «29 дек.»).

Команда `/limits` (или палитра команд → «Usage limits») открывает подробную
таблицу по всем окнам с оставшимся временем до сброса.
