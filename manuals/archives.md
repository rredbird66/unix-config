# Архивы: tar, ZIP и ar

В Fedora при необходимости: `sudo dnf install tar zip unzip binutils`.
Распаковывайте скачанные архивы без `sudo` в отдельный каталог.

## tar — архив `.tar.gz`

```bash
tar -czf project.tar.gz project/             # создать с gzip-сжатием
tar -tzf project.tar.gz                      # посмотреть содержимое
mkdir -p out-tar
tar -xzf project.tar.gz -C out-tar          # распаковать в out-tar/
```

## ZIP — создать и распаковать

```bash
zip -r project.zip project/                  # добавить весь каталог
unzip -l project.zip                         # посмотреть содержимое
unzip project.zip -d out-zip                 # распаковать в out-zip/
```

## ar — статические библиотеки `.a`

```bash
ar rcs libdemo.a demo.o                      # создать библиотеку из готового .o
ar t libdemo.a                               # посмотреть содержимое
mkdir -p out-ar
(cd out-ar && ar x ../libdemo.a)             # извлечь объектный файл
```
