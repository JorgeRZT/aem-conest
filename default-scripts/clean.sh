#!/usr/bin/env bash
set -u

in="${1:?uso: $0 entrada.csv [salida.csv]}"
out="${2:-${in%.csv}_clean.csv}"

PATTERNS='AddSearchBot|AhrefsBot|Applebot|Ask Jeeves Corporate Spider|Bingbot|BingPreview|BLEXBot|BuiltWith|Bytespider|CrawlerKengo|Facebookexternalhit|Google AdsBot|Googlebot|lmspider|LucidWorks|MJ12bot|Pinterest|SemrushBot|SiteImprove|StashBot|StatusCake|YandexBot|ContentKing|Claudebot|ChatGPT|Gmail Image Proxy|Baidu Spider|Outbrain|Yahoo! Mail Proxy|aiHitBot|Mail\.Ru Bot|DomainStatsBot|Rainmeter|MetaInspector|Yahoo Gemini|Perplexity|Gemini Deep Research|Sogou|/etc\.clientlibs/|/api/graphql|/content/experience-fragments/|\.(jpe?g|png|gif|webp|avif|svg|ico|bmp|tiff?|heic|mp4|webm|mov|avi|mkv|wmv|flv|m4v|mpe?g|ogv|3gp|css|m?js)([^[:alnum:]]|$)'
# -v: invierte la coincidencia (se queda con lo que NO coincide)
# -i: ignora mayúsculas (así también pilla "ClaudeBot"); quítalo si no lo quieres
grep -E -v -i "$PATTERNS" "$in" | grep -F "GET,200" | grep -F "html" > "$out"

echo "Input lines: $(wc -l < "$in") | Output Lines: $(wc -l < "$out") -> $out"
