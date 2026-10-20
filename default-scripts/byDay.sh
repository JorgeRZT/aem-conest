#!/usr/bin/env bash
# usage: ./byDay.sh input.csv
set -u

in="${1:?usage: $0 input.csv}"

awk '{c[substr($0,2,10)]++} END{for(d in c) print d": "c[d]" results"}' "$in" \
  | sort \
  | perl -pe '1 while s/^(\S+: \d+)(\d{3})/$1.$2/'
