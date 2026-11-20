#!/usr/bin/env bash
set -u

in="${1:?usage: $0 input.csv [output.csv]}"
out="${2:-${in%.*}_clean.csv}"

PATTERNS='AddSearchBot|AhrefsBot|Applebot|Ask Jeeves Corporate Spider|Bingbot|BingPreview|BLEXBot|BuiltWith|Bytespider|CrawlerKengo|Facebookexternalhit|Google AdsBot|Googlebot|lmspider|LucidWorks|MJ12bot|Pinterest|SemrushBot|SiteImprove|StashBot|StatusCake|YandexBot|ContentKing|Claudebot|ChatGPT|Gmail Image Proxy|Baidu Spider|Outbrain|Yahoo! Mail Proxy|aiHitBot|Mail\.Ru Bot|DomainStatsBot|Rainmeter|MetaInspector|Yahoo Gemini|Perplexity|Gemini Deep Research|Sogou|/etc\.clientlibs/|/api/graphql|/content/experience-fragments/|\.(jpe?g|png|gif|webp|avif|svg|ico|bmp|tiff?|heic|mp4|webm|mov|avi|mkv|wmv|flv|m4v|mpe?g|ogv|3gp|css|m?js)([^[:alnum:]]|$)'

# AEM as a Cloud Service CDN logs are JSON, one object per line. Lines starting with "{" are
# rewritten to the CSV layout the rest of the scripts expect, so the same filters apply to both:
#   "timestamp","cli_ip","url","req_ua",METHOD,STATUS,"res_ctype","cache","host"
# Any other line passes through untouched. Fields are located by key (order does not matter)
# with regular expressions: this is not a full JSON parser.
normalize() {
  perl -ne '
    BEGIN {
      @keys = qw(timestamp cli_ip url req_ua method status res_ctype cache host);
      %re = map { $_ => qr/"\Q$_\E"\s*:\s*(?:"((?:[^"\\]|\\.)*)"|([^,}\s]+))/ } @keys;
    }
    if (!/^\s*\{/) { print; next }
    my %v;
    for my $k (@keys) {
      $v{$k} = $_ =~ $re{$k} ? (defined $1 ? $1 : $2) : "";
      $v{$k} =~ s{\\/}{/}g;
    }
    print qq{"$v{timestamp}","$v{cli_ip}","$v{url}","$v{req_ua}",$v{method},$v{status},},
          qq{"$v{res_ctype}","$v{cache}","$v{host}"\n};
  ' "$1"
}

# -v: inverts the match (keeps what does NOT match)
# -i: ignores case (so it also catches "ClaudeBot"); remove it if you do not want that
normalize "$in" | grep -E -v -i "$PATTERNS" | grep -F "GET,200" | grep -F "html" > "$out"

echo "Input lines: $(wc -l < "$in") | Output Lines: $(wc -l < "$out") -> $out"
