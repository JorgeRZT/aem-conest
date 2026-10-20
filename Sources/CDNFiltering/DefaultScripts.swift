// Generado por tools/gen_defaults.sh desde default-scripts/. No editar a mano.
enum DefaultScripts {
    static let all: [(name: String, content: String)] = [
        ("clean.sh", #"""
#!/usr/bin/env bash
set -u

in="${1:?uso: $0 entrada.csv [salida.csv]}"
out="${2:-${in%.csv}_clean.csv}"

PATTERNS='AddSearchBot|AhrefsBot|Applebot|Ask Jeeves Corporate Spider|Bingbot|BingPreview|BLEXBot|BuiltWith|Bytespider|CrawlerKengo|Facebookexternalhit|Google AdsBot|Googlebot|lmspider|LucidWorks|MJ12bot|Pinterest|SemrushBot|SiteImprove|StashBot|StatusCake|YandexBot|ContentKing|Claudebot|ChatGPT|Gmail Image Proxy|Baidu Spider|Outbrain|Yahoo! Mail Proxy|aiHitBot|Mail\.Ru Bot|DomainStatsBot|Rainmeter|MetaInspector|Yahoo Gemini|Perplexity|Gemini Deep Research|Sogou|/etc\.clientlibs/|/api/graphql|/content/experience-fragments/|\.(jpe?g|png|gif|webp|avif|svg|ico|bmp|tiff?|heic|mp4|webm|mov|avi|mkv|wmv|flv|m4v|mpe?g|ogv|3gp|css|m?js)([^[:alnum:]]|$)'
# -v: invierte la coincidencia (se queda con lo que NO coincide)
# -i: ignora mayúsculas (así también pilla "ClaudeBot"); quítalo si no lo quieres
grep -E -v -i "$PATTERNS" "$in" | grep -F "GET,200" | grep -F "html" > "$out"

echo "Input lines: $(wc -l < "$in") | Output Lines: $(wc -l < "$out") -> $out"
"""#),
        ("byDay.sh", #"""
#!/usr/bin/env bash
# uso: ./dias.sh entrada.csv
set -u

in="${1:?uso: $0 entrada.csv}"

awk '{c[substr($0,2,10)]++} END{for(d in c) print d": "c[d]" resultados"}' "$in" \
  | sort \
  | perl -pe '1 while s/^(\S+: \d+)(\d{3})/$1.$2/'
"""#),
        ("hitsByDomain.sh", #"""
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
"""#),
        ("byDayAndDomain.sh", #"""
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
"""#),
        ("hitsByDomainAndDate.sh", #"""
#!/usr/bin/env bash
# uso: ./dominios_rango.sh entrada.csv FECHA_INICIO FECHA_FIN
# ejemplo: ./dominios_rango.sh filtered.csv 2026-09-22 2026-09-25
set -u

in="${1:?uso: $0 entrada.csv FECHA_INICIO FECHA_FIN (YYYY-MM-DD)}"
ini="${2:?falta fecha de inicio (YYYY-MM-DD)}"
fin="${3:?falta fecha de fin (YYYY-MM-DD)}"

re='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
[[ $ini =~ $re && $fin =~ $re ]] || { echo "Formato de fecha inválido, usa YYYY-MM-DD" >&2; exit 1; }

awk -v ini="$ini" -v fin="$fin" '{
  d = substr($0, 2, 10)
  if (d < ini || d > fin) next          # ambos días incluidos
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
"""#),
    ]
}
