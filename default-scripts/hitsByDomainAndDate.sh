#!/usr/bin/env bash
# usage: ./hitsByDomainAndDate.sh input.csv START_DATE END_DATE
# example: ./hitsByDomainAndDate.sh filtered.csv 2026-09-22 2026-09-25
set -u

in="${1:?usage: $0 input.csv START_DATE END_DATE (YYYY-MM-DD)}"
ini="${2:?missing start date (YYYY-MM-DD)}"
fin="${3:?missing end date (YYYY-MM-DD)}"

re='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
[[ $ini =~ $re && $fin =~ $re ]] || { echo "Invalid date format, use YYYY-MM-DD" >&2; exit 1; }

awk -v ini="$ini" -v fin="$fin" '{
  d = substr($0, 2, 10)
  if (d < ini || d > fin) next          # both days included
  n = split($0, f, ",")
  h = f[n]; gsub(/["\r]/, "", h)
  c[h]++
}
END {
  for (h in c) printf "%d\t%s\n", c[h], h
}' "$in" \
  | sort -t$'\t' -k1,1nr \
  | awk -F'\t' '{ print $2 ": " $1 " hits"; total += $1 }
                END { print ""; print "TOTAL: " total " hits" }' \
  | perl -pe '1 while s/^(\S+: \d+)(\d{3})/$1.$2/'