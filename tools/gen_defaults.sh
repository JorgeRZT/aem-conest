#!/usr/bin/env bash
# Regenera Sources/CDNFiltering/DefaultScripts.swift a partir de default-scripts/*.sh
set -eu
cd "$(dirname "$0")/.."
out="Sources/CDNFiltering/DefaultScripts.swift"
{
  echo "// Generado por tools/gen_defaults.sh desde default-scripts/. No editar a mano."
  echo "enum DefaultScripts {"
  echo "    static let all: [(name: String, content: String)] = ["
  for f in clean.sh byDay.sh hitsByDomain.sh byDayAndDomain.sh hitsByDomainAndDate.sh; do
    echo "        (\"$f\", #\"\"\""
    cat "default-scripts/$f"; [ -n "$(tail -c1 "default-scripts/$f")" ] && echo || true
    echo "\"\"\"#),"
  done
  echo "    ]"
  echo "}"
} > "$out"
echo "Generado $out"
