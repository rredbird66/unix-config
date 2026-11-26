#!/usr/bin/env bash
set -euo pipefail

if ! command -v upower >/dev/null 2>&1; then
   printf '%s\n' 'Ошибка: не найдена команда upower (пакет upower в Fedora).' >&2
   exit 1
fi

if ! report=$(LC_ALL=C upower --battery); then
   printf '%s\n' 'Ошибка: не удалось получить показания батареи через UPower.' >&2
   exit 1
fi

# UPower также видит батареи мышей и других периферийных устройств.
awk '
   BEGIN {
      count = split("model state energy-full energy-full-design energy-rate charge-cycles percentage capacity", keys)
   }
   function show_battery(    i, key) {
      if (fields["power supply"] != "yes" || fields["present"] != "yes")
         return
      if (shown++)
         print ""
      for (i = 1; i <= count; i++) {
         key = keys[i]
         printf "%-22s %s\n", key ":", fields[key] != "" ? fields[key] : "N/A"
      }
   }
   /^Device:/ {
      show_battery()
      delete fields
      next
   }
   /^[[:space:]]+[a-z][a-z -]*:/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      separator = index(line, ":")
      key = substr(line, 1, separator - 1)
      value = substr(line, separator + 1)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      fields[key] = value
   }
   END {
      show_battery()
      if (!shown)
         print "Системные батареи не найдены."
   }
' <<<"$report"
