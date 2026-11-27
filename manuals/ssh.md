# SSH и scp: вход и копирование

Возьмите нужный блок `Host` из [ssh/config.example](../ssh/config.example) в
`~/.ssh/config` и замените адрес, пользователя и порт на свои.

## Вход и копирование

```bash
ssh -G targaryen                     # показать итоговые настройки хоста
ssh targaryen                        # подключиться
scp ./README.md targaryen:~/         # отправить файл
scp targaryen:~/README.md ./README.remote.md    # скачать файл
```

## Ключи

```bash
mkdir -p -m 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/demo-targaryen.key
ssh-copy-id -i ~/.ssh/demo-targaryen.key.pub targaryen
ssh-keygen -lf ~/.ssh/demo-targaryen.key.pub   # отпечаток публичного ключа
ssh-add -l                           # ключи, которые видит агент
```

Для `ssh-copy-id` нужен действующий способ входа на сервер, например пароль.
Права: `700` на `~/.ssh`, `600` на приватные ключи и `~/.ssh/config`.

## Если не пускает

```bash
ssh -v targaryen                     # подробный лог подключения
ssh-add -l                           # есть ли ключ в агенте
ls -l ~/.ssh                         # проверить права и имена файлов
```

При первом входе сверьте отпечаток ключа сервера с тем, что сообщил
администратор по независимому каналу. В выводе `ssh -v` ищите строки
`Offending ... key` и `Permission denied`.
