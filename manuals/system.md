# Системное администрирование Fedora

Имена пакетов, пользователей, устройств и служб в примерах заменяйте на свои.

## dnf и rpm — пакеты

```bash
dnf search ripgrep              # найти пакет
dnf info ripgrep                # описание и версия
rpm -q ripgrep                  # проверить, установлен ли пакет
sudo dnf install ripgrep        # установить
sudo dnf remove ripgrep         # удалить
sudo dnf upgrade --refresh      # обновить пакеты системы
```

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

## systemctl и journalctl — службы и журналы

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

## cron — запуск по расписанию

В Fedora службу предоставляет пакет `cronie`: `sudo systemctl enable --now crond`.
`crontab -e` редактирует расписание текущего пользователя, `crontab -l` показывает
его. Формат: минута, час, день месяца, месяц, день недели, команда.

```cron
*/15 * * * * /usr/bin/date >> "$HOME/cron-example.log" 2>&1
```

Пример записывает время каждые 15 минут. В заданиях используйте абсолютные
пути к командам и скриптам.

## Docker — установка и контейнеры

Для чистой установки используйте [официальный репозиторий Docker Engine для Fedora](https://docs.docker.com/engine/install/fedora/).
Если Docker уже установлен из другого источника, сначала проверьте
конфликтующие пакеты по этой инструкции. Если `config-manager` недоступен:
`sudo dnf install dnf5-plugins`.

```bash
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Если DNF запрашивает подтверждение ключа репозитория, сверяйте отпечаток:
`060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35`.

```bash
sudo systemctl enable --now docker      # запустить сейчас и при загрузке
sudo docker run --rm hello-world         # проверить установку
```

Основные команды. Если у вашей учётной записи уже есть доступ к демону,
`sudo` не требуется.

```bash
sudo docker run -d --name demo nginx:alpine   # запустить контейнер в фоне
sudo docker ps -a                            # список, включая остановленные
sudo docker logs --tail 50 demo              # последние строки журнала
sudo docker exec -it demo sh                 # открыть shell внутри контейнера
sudo docker stop demo
sudo docker rm demo                          # удалить остановленный контейнер
```
