#!/usr/bin/env bash
# uso: ./dias.sh entrada.csv
set -u

in="${1:?uso: $0 entrada.csv}"

awk '{c[substr($0,2,10)]++} END{for(d in c) print d": "c[d]" resultados"}' "$in" \
  | sort \
  | perl -pe '1 while s/^(\S+: \d+)(\d{3})/$1.$2/'
