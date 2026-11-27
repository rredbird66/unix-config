# Контейнеры: Podman и Docker

В Fedora Podman обычно уже установлен и работает без демона. Docker ставят отдельно из
официального репозитория. Команды почти совпадают: в примерах ниже заменяйте
`podman` на `docker`; для Docker обычно нужен `sudo`.

## Проверка

```bash
podman info                          # версия и хранилище
podman run --rm hello-world          # проверить запуск
```

## Локальный сервис

```bash
podman run -d --name web -p 127.0.0.1:8080:80 nginx:alpine
curl -I http://127.0.0.1:8080        # проверить ответ
podman port web                      # какой порт опубликован
podman logs --tail 50 web            # журнал контейнера
podman stop web && podman rm web     # остановить и удалить
```

Порт опубликован только на `127.0.0.1`: сервис не будет доступен из сети.

## Docker

Установка из [официального репозитория Docker Engine для Fedora](https://docs.docker.com/engine/install/fedora/).
Если Docker уже установлен из другого источника, сначала проверьте
конфликтующие пакеты по официальной инструкции.
Если `config-manager` недоступен: `sudo dnf install dnf5-plugins`.

```bash
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
```

Если DNF запрашивает подтверждение ключа репозитория, сверяйте отпечаток:
`060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35`.

Docker Engine можно выбрать в `make setup`; он также входит в `make extras`.
Установщик подключает репозиторий только при необходимости, ставит пакеты
и включает службу `docker`.

Для Docker без `sudo` пользователя добавляют в группу `docker`, но это даёт
права root. Rootless Podman безопаснее и не требует такой настройки.
