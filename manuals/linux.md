# Linux: основные команды

Примеры рассчитаны на Fedora и Bash. Имена файлов, пользователей, устройств и
служб заменяйте на свои.

## alias — сокращения в Bash

```bash
alias ll='ls -lhA'   # создать для текущего Bash
alias ll             # посмотреть определение
unalias ll           # убрать из текущего Bash
```

Чтобы сохранить сокращение, добавьте строку `alias …` в `~/.bashrc`.

## ln — ссылки

```bash
ln README.md readme-hard.md       # ещё одно имя того же файла
ln -s README.md readme-link.md    # символическая ссылка на путь
```

Жёсткая ссылка работает в пределах одной файловой системы. Символическая
может указывать на каталог; её относительный путь считается от каталога
самой ссылки.

## ar — архивы, обычно статические библиотеки `.a`

```bash
ar rcs libdemo.a demo.o    # создать библиотеку из готового объектного файла
ar t libdemo.a             # показать содержимое
ar x libdemo.a             # извлечь в текущий каталог
```

Извлекайте в пустой каталог, если рядом есть одноимённые файлы.

## dd — поблочное копирование

```bash
image=$(mktemp) && dd if=/dev/zero of="$image" bs=1M count=16 status=progress
```

Пример записывает 16 МиБ нулей во временный файл. `if` — источник, `of` —
назначение. `dd` перезаписывает `of` без подтверждения: проверяйте путь перед
записью, особенно если это устройство в `/dev`. После примера файл можно
удалить командой `rm -- "$image"`.

## /etc/fstab — постоянное монтирование

Узнайте UUID и тип файловой системы через `lsblk -f`, создайте точку
монтирования (`sudo mkdir -p /mnt/data`) и откройте `sudoedit /etc/fstab`.
Пример для дополнительного диска с ext4:

```fstab
# устройство           точка      тип   опции            dump  fsck
UUID=<UUID_раздела>    /mnt/data  ext4  defaults,nofail  0     2
```

Подставьте реальный UUID без угловых скобок. `nofail` позволяет системе
загрузиться, даже если этот диск недоступен. Перед перезагрузкой проверьте запись:

```bash
findmnt --verify --verbose
sudo systemctl daemon-reload
sudo mount /mnt/data
```

## Пользователи

```bash
sudo useradd -m -s /bin/bash demo   # создать пользователя и домашний каталог
sudo passwd demo                    # задать пароль
id demo                             # показать UID и группы
sudo usermod -aG wheel demo         # только если нужен доступ к sudo
```

`-aG` добавляет группу, сохраняя прежние. Новые группы применяются при новом
входе пользователя в систему.

## systemctl — службы

```bash
systemctl status sshd                 # состояние службы
sudo systemctl start sshd              # запустить сейчас
sudo systemctl stop sshd               # остановить сейчас
sudo systemctl restart sshd            # перезапустить
sudo systemctl enable --now sshd       # запустить сейчас и при загрузке
sudo systemctl disable --now sshd      # остановить и убрать из автозапуска
sudo journalctl -u sshd -n 50 --no-pager
```

Для службы своего пользователя используйте `systemctl --user …` без `sudo`.

## Docker — контейнеры

Нужен установленный Docker и доступ к его демону.

```bash
docker run -d --name demo nginx:alpine   # запустить контейнер в фоне
docker ps -a                            # список, включая остановленные
docker logs --tail 50 demo              # последние строки журнала
docker exec -it demo sh                 # открыть shell внутри контейнера
docker stop demo
docker rm demo                          # удалить остановленный контейнер
```

## cron — запуск по расписанию

В Fedora службу предоставляет пакет `cronie`: `sudo systemctl enable --now crond`.
`crontab -e` редактирует расписание текущего пользователя, `crontab -l` показывает
его. Формат: минута, час, день месяца, месяц, день недели, команда.

```cron
*/15 * * * * /usr/bin/date >> "$HOME/cron-example.log" 2>&1
```

Пример записывает время каждые 15 минут. В заданиях используйте абсолютные
пути к командам и скриптам.
