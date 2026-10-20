#!/usr/bin/env bash
# uso: ./dominios.sh entrada.csv
set -u

in="${1:?uso: $0 entrada.csv}"

awk '{
  n = split($0, f, ",")
  h = f[n]; gsub(/["\r]/, "", h)        # dominio = último campo, sin comillas
  c[h]++
}
END {
  for (h in c) printf "%d\t%s\n", c[h], h
}' "$in" \
  | sort -t$'\t' -k1,1nr \
  | awk -F'\t' '{ print $2 ": " $1 " hits" }' \
  | perl -pe '1 while s/^(\S+: \d+)(\d{3})/$1.$2/'
