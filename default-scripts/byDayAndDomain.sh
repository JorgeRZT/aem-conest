#!/usr/bin/env bash
# usage: ./byDayAndDomain.sh input.csv
set -u

in="${1:?usage: $0 input.csv}"

awk '{
  d = substr($0, 2, 10)                 # day: 2026-09-22
  n = split($0, f, ",")
  h = f[n]; gsub(/["\r]/, "", h)        # domain = last field, without quotes
  c[d SUBSEP h]++
}
END {
  for (k in c) { split(k, p, SUBSEP); printf "%s\t%s\t%d\n", p[1], p[2], c[k] }
}' "$in" \
  | sort -t$'\t' -k1,1 -k3,3nr \
  | awk -F'\t' '
      $1 != prev { if (NR > 1) print ""; print $1; prev = $1 }
      { print "  " $2 ": " $3 " results" }' \
  | perl -pe '1 while s/^(\s+\S+: \d+)(\d{3})/$1.$2/'
