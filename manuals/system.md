# Системное администрирование Fedora

Имена пакетов, пользователей, устройств и служб в примерах заменяйте на свои.

## dnf и rpm — пакеты

```bash
dnf search ripgrep              # найти пакет
dnf info ripgrep                # описание и версия
rpm -q ripgrep                  # проверить, установлен ли пакет
rpm -qf /usr/bin/rg             # какой пакет владеет файлом
dnf provides '*/rg'             # найти пакет по имени команды
sudo dnf install ripgrep        # установить
sudo dnf remove ripgrep         # удалить
sudo dnf upgrade --refresh      # обновить пакеты системы
dnf history list                # история транзакций
dnf history info 8              # подробности транзакции
```

## /etc/fstab — постоянное монтирование

Узнайте UUID и тип файловой системы через `lsblk -f`, создайте точку
монтирования (`sudo mkdir -p /mnt/data`) и откройте `sudoedit /etc/fstab`.
Пример для дополнительного диска с ext4:

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

## Место на диске и память

```bash
df -h                            # свободное место на смонтированных файловых системах
du -sh ./project                 # суммарный размер каталога
du -h -d1 . | sort -h            # подкаталоги по размеру, от меньшего к большему
findmnt -T "$HOME"               # файловая система для конкретного пути
free -h                          # оперативная память и swap
```

Если `df` показывает занятое место, а `du` его не находит, ищите удалённые
открытые файлы: `sudo lsof +L1`.

## Пользователи

```bash
sudo useradd -m -s /bin/bash demo   # создать пользователя и домашний каталог
sudo passwd demo                    # задать пароль
id demo                             # показать UID и группы
sudo usermod -aG wheel demo         # только если нужен доступ к sudo
```

`-aG` добавляет группу, сохраняя прежние. Новые группы применяются при следующем
входе пользователя в систему.

## systemctl и journalctl — службы и журналы

```bash
systemctl status sshd                  # состояние службы
systemctl --failed                     # службы с ошибкой (состояние failed)
sudo systemctl start sshd              # запустить сейчас
sudo systemctl stop sshd               # остановить сейчас
sudo systemctl restart sshd            # перезапустить
sudo systemctl enable --now sshd       # запустить сейчас и при загрузке
sudo systemctl disable --now sshd      # остановить и убрать из автозапуска
sudo journalctl -u sshd -n 50 --no-pager
journalctl -b -p err                   # ошибки текущей загрузки
journalctl --list-boots                # список загрузок
journalctl -b -1 -p err                # ошибки предыдущей загрузки
journalctl -u sshd -f                  # показывать новые записи службы
journalctl --disk-usage                # сколько места занимает журнал
```

Для службы своего пользователя используйте `systemctl --user …` без `sudo`.

## Питание

```bash
systemctl poweroff               # выключить сейчас
systemctl reboot                 # перезагрузить сейчас
systemctl suspend                # приостановить (сон в памяти)
shutdown -r +10                  # перезагрузка через 10 минут
shutdown -c                      # отменить запланированное выключение / перезагрузку
```

Команды этого раздела в локальной графической сессии работают без `sudo`;
по SSH polkit запросит пароль администратора.

## cron — запуск по расписанию

В Fedora службу `crond` предоставляет пакет `cronie`: `sudo systemctl enable --now crond`.
`crontab -e` редактирует расписание текущего пользователя, `crontab -l` показывает
его. Формат: минута, час, день месяца, месяц, день недели, команда.

```cron
*/15 * * * * /usr/bin/date >> "$HOME/cron-example.log" 2>&1
```

Пример записывает время каждые 15 минут. В заданиях используйте абсолютные
пути к командам и скриптам.

## SELinux и firewalld — почему доступ запрещён

Если права выглядят верно, но доступ запрещён, проверьте контекст SELinux:

```bash
getenforce                         # Enforcing, Permissive или Disabled
ls -Z /path                        # контекст файла или каталога
```

Если служба слушает порт, но извне недоступна, проверьте зону firewalld:

```bash
sudo firewall-cmd --get-active-zones          # активные зоны и интерфейсы
sudo firewall-cmd --zone=FedoraWorkstation --list-all   # правила зоны
```

Зону из первой команды подставьте во вторую.

## Контейнеры

Установка Docker, Podman и основные команды — в [шпаргалке по контейнерам](containers.md).
