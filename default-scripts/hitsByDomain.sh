#!/usr/bin/env bash
# usage: ./hitsByDomain.sh input.csv
set -u

in="${1:?usage: $0 input.csv}"

awk '{
  n = split($0, f, ",")
  h = f[n]; gsub(/["\r]/, "", h)        # domain = last field, without quotes
  c[h]++
}
END {
  for (h in c) printf "%d\t%s\n", c[h], h
}' "$in" \
  | sort -t$'\t' -k1,1nr \
  | awk -F'\t' '{ print $2 ": " $1 " hits" }' \
  | perl -pe '1 while s/^(\S+: \d+)(\d{3})/$1.$2/'
