#!/usr/bin/env bash
# Content Request analysis, used by the "Content Requests" section of the app.
# usage: content-requests.sh input [output.tsv]
#
# Unlike clean.sh, which keeps the lines it counts, this script reads the RAW log once and
# classifies every line as counted (with the kind of client that made it) or excluded (with the
# reason), following Adobe's "Content Requests" documentation:
#   https://experienceleague.adobe.com/en/docs/experience-manager-cloud-service/content/implementing/using-cloud-manager/content-requests
# It deliberately duplicates the bot lists of clean.sh, but its rules differ from clean.sh (JSON
# responses and every 1xx/2xx status count; /libs, health probes and the pod warm-up do not), so
# its totals do not match the Dashboard. Edit both scripts if a list changes.
#
# Accepts the legacy CSV layout and AEM as a Cloud Service JSON lines, like clean.sh.
# The output is tab-separated, one aggregate per line, with the table name in the first column:
#   S day host verdict reason type count    every line (verdict C = counted, X = excluded)
#   P day host path type count nonbrowser    counted, per path (query string removed)
#   U day host class user-agent count        counted, per user agent
#   I day host ip count nonbrowser           counted, per client IP
#   G day host country count                 counted, per country (JSON logs only)
#   E reason host example count              excluded, top examples per reason (whole file)
#   #lines n / #invalid n
# Only the TOP_PATHS / TOP_UAS / TOP_IPS busiest values are listed one by one; the rest are
# folded into "(other …)" rows so the output stays small for multi-gigabyte logs.
set -u

in="${1:?usage: $0 input [output.tsv]}"
out="${2:-${in%.*}_analysis.tsv}"

TOP_PATHS="${TOP_PATHS:-5000}" TOP_UAS="${TOP_UAS:-500}" TOP_IPS="${TOP_IPS:-500}" \
perl - "$in" "$out" <<'PERL'
use strict;
use warnings;
my ($in, $out) = @ARGV;

# Well-known search engines, social networks and HTTP libraries tagged by the CDN (excluded).
my $known_bot = qr/AddSearchBot|AhrefsBot|Applebot|Ask Jeeves Corporate Spider|Bingbot|BingPreview|BLEXBot|BuiltWith|Bytespider|CrawlerKengo|Facebookexternalhit|Google AdsBot|Googlebot|lmspider|LucidWorks|MJ12bot|Pinterest|SemrushBot|SiteImprove|StashBot|StatusCake|YandexBot|ContentKing|Claudebot/i;
# Well-known AI / LLM crawlers (excluded).
my $ai_crawler = qr/ChatGPT|Gmail Image Proxy|Baidu Spider|Outbrain|Yahoo! Mail Proxy|aiHitBot|Mail\.Ru Bot|DomainStatsBot|Rainmeter|MetaInspector|Yahoo Gemini|Perplexity|Gemini Deep Research|Sogou/i;
# Monitoring and health check tools (counted when they request pages).
my $monitoring = qr/UptimeRobot|Amazon-Route53-Health-Check-Service|EyeMonIT|Site24x7|ThousandEyes|OmtrBot|WebMon|Pingdom|Uptime-Kuma|Better ?Uptime|Checkly|Datadog/i;
# HTTP libraries and automation (counted).
my $library = qr/Amazon CloudFront|Apache-HttpClient|AsyncHttpClient|axios|Azureus|\bcurl\/|node-fetch|GuzzleHttp|Go-http-client|HeadlessChrome|\bJava\/|Jersey|oembed|okhttp|python-requests|python-urllib|aiohttp|python-httpx|ReactorNetty|\bWget\/|WinHTTP|fasthttp|libwww-perl|PostmanRuntime|insomnia/i;
# Anything else that looks automated (counted: Adobe only excludes the lists above).
my $bot_like = qr/bot|crawl|spider|scrap|slurp|fetch|scan|archiv|https?:\/\//i;
my $static = qr/\.(?:jpe?g|png|gif|webp|avif|svg|ico|bmp|tiff?|heic|mp4|webm|mov|avi|mkv|wmv|flv|m4v|mpe?g|ogv|3gp|css|m?js|woff2?|ttf|otf|eot|map|pdf)$/i;

my @keys = qw(timestamp cli_ip url req_ua method status res_ctype cache host cli_country);
my %re = map { $_ => qr/"\Q$_\E"\s*:\s*(?:"((?:[^"\\]|\\.)*)"|([^,}\s]+))/ } @keys;

my (%S, %P, %PN, %ptot, %U, %utot, %I, %IN, %itot, %G, %E);
my ($lines, $invalid, $counted) = (0, 0, 0);

open my $fh, '<', $in or die "Cannot read $in: $!\n";
while (<$fh>) {
  $lines++;
  s/\r?\n\z//;
  my ($ts, $ip, $url, $ua, $method, $status, $ctype, $host, $country);
  if (/^\s*\{/) {
    my %v;
    for my $k (@keys) {
      $v{$k} = $_ =~ $re{$k} ? (defined $1 ? $1 : $2) : '';
      $v{$k} =~ s/\\(["\\\/])/$1/g;
    }
    ($ts, $ip, $url, $ua, $method, $status, $ctype, $host, $country) =
      @v{qw(timestamp cli_ip url req_ua method status res_ctype host cli_country)};
  } elsif (/^"([^"]*)","([^"]*)","([^"]*)","(.*)",([A-Za-z]*),(\d*),"([^"]*)","[^"]*","([^"]*)"\s*$/) {
    ($ts, $ip, $url, $ua, $method, $status, $ctype, $host) = ($1, $2, $3, $4, $5, $6, $7, $8);
  } else {
    # Not the expected layout: keep the legacy assumptions (date in characters 2-11, domain last).
    $ts = substr($_, 1, 10);
    ($host = (split /,/)[-1] // '') =~ s/"//g;
    ($ip, $url, $ua, $method, $status, $ctype) = ('', '', '', '', '', '');
  }
  my $day = substr($ts // '', 0, 10);
  if ($day !~ /^\d{4}-\d\d-\d\d$/) { $invalid++; next }
  $host //= '';
  (my $path = $url) =~ s/[?#].*//s;
  $path = '/' if $path eq '';

  # The response Content-Type alone decides the type, never the path: application/json,
  # application/*+json (hal+json, ld+json…) and text/json are JSON. JSONP (javascript) is not.
  my $type = $ctype =~ /text\/html/i ? 'html' : $ctype =~ /(?:application\/(?:[\w.+-]*\+)?|text\/)json/i ? 'json' : '';
  my $reason;
  my $example = $path;
  if    ($method eq '' && $status eq '')        { $reason = 'unparsed'; $example = substr($_, 0, 200) }
  elsif (uc $method ne 'GET')                   { $reason = 'method' }
  elsif ($status !~ /^[12]\d\d$/)               { $reason = $status =~ /^([345])\d\d$/ ? "${1}xx" : 'other-status' }
  elsif ($path =~ m{^/libs/}i)                  { $reason = 'libs' }
  elsif ($path =~ m{^/system/probes/health}i)   { $reason = 'health-probe' }
  elsif ($path =~ m{^/etc\.clientlibs/}i)       { $reason = 'clientlibs' }
  elsif ($path =~ m{^/api/graphql}i)            { $reason = 'graphql' }
  elsif ($path =~ m{/favicon\.ico$}i)           { $reason = 'favicon' }
  elsif ($path =~ m{^/content/experience-fragments/}i) { $reason = 'xf' }
  elsif ($type eq '')                           { $reason = $path =~ $static ? 'static-asset' : 'other-type' }
  elsif ($ua =~ /skyline-service-warmup/i)      { $reason = 'warmup';     $example = $ua }
  elsif ($ua =~ $known_bot)                     { $reason = 'known-bot';  $example = $ua }
  elsif ($ua =~ $ai_crawler)                    { $reason = 'ai-crawler'; $example = $ua }

  if (defined $reason) {
    $S{"$day\t$host\tX\t$reason\t" . ($type || '-')}++;
    $E{$reason}{"$host\t$example"}++;
    next;
  }

  my $class = $ua =~ /^\s*-?\s*$/ ? 'empty-ua'
            : $ua =~ $monitoring  ? 'monitoring'
            : $ua =~ $library     ? 'http-library'
            : $ua =~ $bot_like    ? 'unclassified-bot'
            :                       'browser';
  my $nb = $class eq 'browser' ? 0 : 1;
  $counted++;
  $S{"$day\t$host\tC\t$class\t$type"}++;
  my $pk = "$host\t$path";
  $P{"$day\t$pk\t$type"}++; $PN{"$day\t$pk\t$type"} += $nb; $ptot{$pk}++;
  $ua =~ s/\t/ /g;
  $U{"$day\t$host\t$class\t$ua"}++; $utot{"$class\t$ua"}++;
  $I{"$day\t$host\t$ip"}++; $IN{"$day\t$host\t$ip"} += $nb; $itot{$ip}++;
  $G{"$day\t$host\t$country"}++ if defined $country && $country ne '';
}
close $fh;

sub top { my ($h, $n) = @_; my @k = sort { $h->{$b} <=> $h->{$a} || $a cmp $b } keys %$h; splice @k, $n if @k > $n; return { map { $_ => 1 } @k } }

open my $o, '>', $out or die "Cannot write $out: $!\n";
print $o "S\t$_\t$S{$_}\n" for sort keys %S;

my $keep = top(\%ptot, $ENV{TOP_PATHS});
my (%fold, %foldn);
for my $k (keys %P) {
  my ($day, $host, $path, $type) = split /\t/, $k, 4;
  if ($keep->{"$host\t$path"}) { print $o "P\t$k\t$P{$k}\t$PN{$k}\n" }
  else { my $f = "$day\t$host\t(other paths)\t$type"; $fold{$f} += $P{$k}; $foldn{$f} += $PN{$k} }
}
print $o "P\t$_\t$fold{$_}\t$foldn{$_}\n" for keys %fold;

$keep = top(\%utot, $ENV{TOP_UAS});
%fold = ();
for my $k (keys %U) {
  my ($day, $host, $class, $ua) = split /\t/, $k, 4;
  if ($keep->{"$class\t$ua"}) { print $o "U\t$k\t$U{$k}\n" } else { $fold{"$day\t$host\t$class\t(other user agents)"} += $U{$k} }
}
print $o "U\t$_\t$fold{$_}\n" for keys %fold;

$keep = top(\%itot, $ENV{TOP_IPS});
(%fold, %foldn) = ();
for my $k (keys %I) {
  my ($day, $host, $ip) = split /\t/, $k, 3;
  if ($keep->{$ip}) { print $o "I\t$k\t$I{$k}\t$IN{$k}\n" }
  else { my $f = "$day\t$host\t(other IPs)"; $fold{$f} += $I{$k}; $foldn{$f} += $IN{$k} }
}
print $o "I\t$_\t$fold{$_}\t$foldn{$_}\n" for keys %fold;

print $o "G\t$_\t$G{$_}\n" for sort keys %G;

for my $r (sort keys %E) {
  my $h = $E{$r};
  my @k = sort { $h->{$b} <=> $h->{$a} || $a cmp $b } keys %$h;
  splice @k, 15 if @k > 15;
  print $o "E\t$r\t$_\t$h->{$_}\n" for @k;
}
print $o "#lines\t$lines\n#invalid\t$invalid\n";
close $o or die "Cannot write $out: $!\n";

(my $n = $lines) =~ s/(?<=\d)(?=(\d{3})+$)/./g;
(my $c = $counted) =~ s/(?<=\d)(?=(\d{3})+$)/./g;
my $x = $lines - $counted - $invalid;
$x =~ s/(?<=\d)(?=(\d{3})+$)/./g;
print "Input lines: $n | Content requests: $c | Excluded: $x -> $out\n";
PERL
