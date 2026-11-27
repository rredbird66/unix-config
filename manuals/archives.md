# Архивы: tar, ZIP и ar

В Fedora, если утилиты нет: `sudo dnf install tar zip unzip binutils zstd`.
Распаковывайте скачанные архивы без `sudo` в отдельный каталог.

## tar — архивы `.tar.gz` и `.tar.zst`

```bash
tar -czf project.tar.gz project/             # создать с gzip-сжатием
tar -caf project.tar.zst project/            # сжатие по суффиксу имени архива
tar -tzf project.tar.gz                      # посмотреть содержимое
tar -xOf project.tar.gz project/README.md | less   # прочитать файл без распаковки
mkdir -p out-tar
tar -xzf project.tar.gz -C out-tar          # распаковать в out-tar/
tar -xzf project.tar.gz -C out-tar --strip-components=1   # без верхнего каталога
```

При создании архива `-a` выбирает программу сжатия по суффиксу (`.gz`, `.zst`,
`.bz2`). При распаковке tar определяет сжатие сам, отдельный флаг не нужен.
`--strip-components=1` убирает верхний каталог архива — удобно для исходников,
где он лишний.

## ZIP — создать и распаковать

```bash
zip -r project.zip project/                  # добавить весь каталог
unzip -l project.zip                         # посмотреть содержимое
unzip project.zip -d out-zip                 # распаковать в out-zip/
```

## Проверка целостности

```bash
sha256sum project.tar.gz              # сверить с суммой из доверенного источника
unzip -t project.zip                  # проверить архив без распаковки
```

## ar — статические библиотеки `.a`

```bash
ar rcs libdemo.a demo.o                      # создать библиотеку из готового .o
ar t libdemo.a                               # посмотреть содержимое
mkdir -p out-ar
(cd out-ar && ar x ../libdemo.a)             # извлечь содержимое библиотеки
```
