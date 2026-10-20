#!/usr/bin/env bash
# uso: ./dias_dominios.sh entrada.csv
set -u

in="${1:?uso: $0 entrada.csv}"

awk '{
  d = substr($0, 2, 10)                 # día: 2026-09-22
  n = split($0, f, ",")
  h = f[n]; gsub(/["\r]/, "", h)        # dominio = último campo, sin comillas
  c[d SUBSEP h]++
}
END {
  for (k in c) { split(k, p, SUBSEP); printf "%s\t%s\t%d\n", p[1], p[2], c[k] }
}' "$in" \
  | sort -t$'\t' -k1,1 -k3,3nr \
  | awk -F'\t' '
      $1 != prev { if (NR > 1) print ""; print $1; prev = $1 }
      { print "  " $2 ": " $3 " resultados" }' \
  | perl -pe '1 while s/^(\s+\S+: \d+)(\d{3})/$1.$2/'
