# Sample data

Synthetic raw CDN logs (no real traffic) to try AEM Conest without your own files.

- **Period:** 2026-09-01 to 2026-09-30, a single file, `cdn-2026-09.csv` (56,291 lines, sorted by day).
- **Domains:** `jlopellicer.com` and `www.jlopellicer.com`.
- **Format:** one request per line, no header, quoted date first and domain last:
  `"timestamp","client_ip","url","user_agent",METHOD,STATUS,"content_type","cache","domain"`
- **Content:** human page views plus the noise the cleaning step removes (bots and AI agents,
  images/CSS/JS, `/etc.clientlibs/`, `/api/graphql`, experience fragments, 404/304 and POST requests).
  Weekdays have more traffic than weekends, with spikes on Sep 9, 10 and 23.

Drop `cdn-2026-09.csv` onto the app.
