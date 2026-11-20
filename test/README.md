# Sample data

Synthetic raw CDN logs (no real traffic) to try AEM Conest without your own files.

- **Period:** 2026-09-01 to 2026-09-30, a single file, `cdn-2026-09.csv` (66,391 lines, sorted by time).
- **Domains:** `jlopellicer.com` and `www.jlopellicer.com`.
- **Format:** one request per line, no header, quoted date first and domain last:
  `"timestamp","client_ip","url","user_agent",METHOD,STATUS,"content_type","cache","domain"`
- **Content:** human page views plus the noise the cleaning step removes (bots and AI agents,
  images/CSS/JS, `/etc.clientlibs/`, `/api/graphql`, experience fragments, 404/304 and POST requests).
  Weekdays have more traffic than weekends, with spikes on Sep 9, 10 and 23.
- **Content Requests section:** traffic that shows up in *Insights*:
  - billable: an UptimeRobot check on `/` every 15 minutes, bots that are not on Adobe's list
    (DataForSeoBot, PetalBot), curl / python-requests / Go clients, requests without a user
    agent, a scraper with a browser user agent from a single IP on Sep 23, a "not found" page
    answered with 200, campaign query strings, and a persisted GraphQL query
    (`/graphql/execute.json/…`);
  - not billable: Route53 checks on `/system/probes/health`, HEAD checks, the pod warm-up,
    `/libs/granite/csrf/token.json` and a few 503s.

Drop `cdn-2026-09.csv` onto the app.

`cdn-2026-09-aemcs.log` holds every 20th request of the same data (3,320 lines) in the AEM as a
Cloud Service CDN log format (one JSON object per line; the extra fields such as `ttfb`, `rid` or
`pop` are made up). Use it to check that JSON logs are recognised.
